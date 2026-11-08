#!/usr/bin/env bash
# Test-suite for the Arrow interpreter (Phase 1).
#   bash tests/run_tests.sh            run interpreter tests
cd "$(dirname "$0")/.." || exit 1
INTERP=./arrow-interp
TMP=tests/tmp
rm -rf "$TMP"; mkdir -p "$TMP"
pass=0; fail=0

ok()   { pass=$((pass+1)); if [ -n "$VERBOSE" ]; then echo "  ok    $1"; fi; return 0; }
bad()  { fail=$((fail+1)); echo "  FAIL  $1"; [ -n "$2" ] && echo "        $2"; }
expect_of() { sed -n 's/^-- EXPECT: //p' "$1" | head -1; }

[ -x "$INTERP" ] || { echo "$INTERP is missing - run 'make' first"; exit 1; }

echo "== programs: interpreter must print the expected output"
for src in tests/programs/*.arw; do
    name=$(basename "$src" .arw)
    exp=tests/programs/$name.expected
    in=/dev/null; [ -f "tests/programs/$name.in" ] && in=tests/programs/$name.in

    "$INTERP" "$src" < "$in" > "$TMP/$name.interp.out" 2> "$TMP/$name.interp.err"
    if cmp -s "$exp" "$TMP/$name.interp.out"; then ok "interp  $name"; else bad "interp  $name" "output differs from $exp"; fi
done

echo "== compile errors: interpreter must reject the program"
for src in tests/compile_errors/*.arw; do
    name=$(basename "$src" .arw); want=$(expect_of "$src")
    "$INTERP" "$src" > /dev/null 2> "$TMP/$name.ie"; rc1=$?
    if [ $rc1 -eq 1 ] && grep -qF -- "$want" "$TMP/$name.ie"; then ok "interp  $name"; else bad "interp  $name" "rc=$rc1, wanted message: $want"; fi
done

echo "== run-time errors: exit status 1 and the right message"
for src in tests/runtime_errors/*.arw; do
    name=$(basename "$src" .arw); want=$(expect_of "$src")
    "$INTERP" "$src" > /dev/null 2> "$TMP/$name.ie" < /dev/null; rc1=$?
    if [ $rc1 -eq 1 ] && grep -qF -- "$want" "$TMP/$name.ie"; then ok "interp  $name"; else bad "interp  $name" "rc=$rc1, wanted message: $want"; fi
done

echo "== command line"
"$INTERP" > /dev/null 2>&1; [ $? -eq 2 ] && ok "interp without arguments exits 2" || bad "interp without arguments"
"$INTERP" /nonexistent.arw > /dev/null 2>&1; [ $? -eq 2 ] && ok "interp missing file exits 2" || bad "interp missing file"
"$INTERP" --check examples/merge_sort.arw 2>&1 | grep -q OK && ok "interp --check" || bad "interp --check"

echo
echo "passed: $pass   failed: $fail"
[ $fail -eq 0 ]
