#!/usr/bin/env bash
# Test-suite for the Arrow interpreter (Phase 1) and compiler (Phase 2).
#   bash tests/run_tests.sh            run everything
# Every program in tests/programs is run by the interpreter and by the compiled
# executable (twice: -O2 and -O0 --no-bce) and the output is compared with the
# .expected file.  The error programs must be rejected / must fail at run time
# with the message given on their first line ("-- EXPECT: ...").
cd "$(dirname "$0")/.." || exit 1
INTERP=./arrow-interp
COMP=./arrowc
TMP=tests/tmp
rm -rf "$TMP"; mkdir -p "$TMP"
pass=0; fail=0

ok()   { pass=$((pass+1)); if [ -n "$VERBOSE" ]; then echo "  ok    $1"; fi; return 0; }
bad()  { fail=$((fail+1)); echo "  FAIL  $1"; [ -n "$2" ] && echo "        $2"; }
expect_of() { sed -n 's/^-- EXPECT: //p' "$1" | head -1; }

for tool in "$INTERP" "$COMP"; do
    [ -x "$tool" ] || { echo "$tool is missing - run 'make' first"; exit 1; }
done

echo "== programs: interpreter and compiler must print the expected output"
for src in tests/programs/*.arw; do
    name=$(basename "$src" .arw)
    exp=tests/programs/$name.expected
    in=/dev/null; [ -f "tests/programs/$name.in" ] && in=tests/programs/$name.in

    "$INTERP" "$src" < "$in" > "$TMP/$name.interp.out" 2> "$TMP/$name.interp.err"
    if cmp -s "$exp" "$TMP/$name.interp.out"; then ok "interp  $name"; else bad "interp  $name" "output differs from $exp"; fi

    for cfg in "-O2" "-O0 --no-bce"; do
        tag=$(echo "$cfg" | tr -d ' -')
        if "$COMP" $cfg "$src" -o "$TMP/$name.$tag" > "$TMP/$name.$tag.build" 2>&1; then
            "$TMP/$name.$tag" < "$in" > "$TMP/$name.$tag.out" 2> "$TMP/$name.$tag.err"
            if cmp -s "$exp" "$TMP/$name.$tag.out"; then ok "arrowc $cfg  $name"; else bad "arrowc $cfg  $name" "output differs from $exp"; fi
        else
            bad "arrowc $cfg  $name" "compilation failed: $(head -1 "$TMP/$name.$tag.build")"
        fi
    done
done

echo "== compile errors: both tools must reject the program"
for src in tests/compile_errors/*.arw; do
    name=$(basename "$src" .arw); want=$(expect_of "$src")
    "$INTERP" "$src" > /dev/null 2> "$TMP/$name.ie"; rc1=$?
    "$COMP" "$src" -o "$TMP/$name.bin" > /dev/null 2> "$TMP/$name.ce"; rc2=$?
    if [ $rc1 -eq 1 ] && grep -qF -- "$want" "$TMP/$name.ie"; then ok "interp  $name"; else bad "interp  $name" "rc=$rc1, wanted message: $want"; fi
    if [ $rc2 -eq 1 ] && grep -qF -- "$want" "$TMP/$name.ce" && [ ! -e "$TMP/$name.bin" ]; then ok "arrowc  $name"; else bad "arrowc  $name" "rc=$rc2, wanted message: $want"; fi
done

echo "== run-time errors: exit status 1 and the right message"
for src in tests/runtime_errors/*.arw; do
    name=$(basename "$src" .arw); want=$(expect_of "$src")
    "$INTERP" "$src" > /dev/null 2> "$TMP/$name.ie" < /dev/null; rc1=$?
    if [ $rc1 -eq 1 ] && grep -qF -- "$want" "$TMP/$name.ie"; then ok "interp  $name"; else bad "interp  $name" "rc=$rc1, wanted message: $want"; fi
    if grep -q 'INTERP-ONLY' "$src"; then continue; fi
    if "$COMP" "$src" -o "$TMP/$name.bin" > /dev/null 2>&1; then
        "$TMP/$name.bin" > /dev/null 2> "$TMP/$name.ce" < /dev/null; rc2=$?
        if [ $rc2 -eq 1 ] && grep -qF -- "$want" "$TMP/$name.ce"; then ok "arrowc  $name"; else bad "arrowc  $name" "rc=$rc2, wanted message: $want"; fi
    else
        bad "arrowc  $name" "compilation failed"
    fi
done

echo "== command line"
"$INTERP" > /dev/null 2>&1; [ $? -eq 2 ] && ok "interp without arguments exits 2" || bad "interp without arguments"
"$COMP"   > /dev/null 2>&1; [ $? -eq 2 ] && ok "arrowc without arguments exits 2" || bad "arrowc without arguments"
"$INTERP" /nonexistent.arw > /dev/null 2>&1; [ $? -eq 2 ] && ok "interp missing file exits 2" || bad "interp missing file"
"$INTERP" --check examples/merge_sort.arw 2>&1 | grep -q OK && ok "interp --check" || bad "interp --check"
"$COMP" --stats tests/programs/bce.arw -o "$TMP/bce" 2>&1 | grep -q '7 array accesses, 6 checks eliminated' && ok "bounds-check statistics" || bad "bounds-check statistics"
"$COMP" -S examples/merge_sort.arw -o "$TMP/ms" > /dev/null 2>&1 && grep -q 'define.*@f_msort' "$TMP/ms.ll" && ok "arrowc -S writes LLVM IR" || bad "arrowc -S"

echo
echo "passed: $pass   failed: $fail"
[ $fail -eq 0 ]
