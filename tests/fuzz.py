#!/usr/bin/env python3
"""Differential fuzz test: random Arrow programs must behave identically in
  * the interpreter                      (./arrow-interp)
  * the compiler at -O2 with the BCE pass (./arrowc)
  * the compiler at -O0 without the pass  (./arrowc -O0 --no-bce)
(same standard output, same exit status, same error message).

usage:  python3 tests/fuzz.py [number_of_programs] [seed]
"""
import os, random, subprocess, sys, tempfile

N = int(sys.argv[1]) if len(sys.argv) > 1 else 100
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 1
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INTERP, COMP = os.path.join(ROOT, "arrow-interp"), os.path.join(ROOT, "arrowc")

class Gen:
    def __init__(self, rnd):
        self.r = rnd
        self.loopvars = 0
        self.nfuncs = 0

    # ---- expressions ------------------------------------------------------
    def ints(self, loops):
        return ["v0", "v1", "v2", "p", "q"] + loops

    def idx(self, d, loops, arr):
        r = self.r.random()
        if loops and r < 0.45:                     # index patterns that the BCE pass looks at
            v = self.r.choice(loops)
            return self.r.choice([v, v, f"{v} + 1", f"{v} - 1", f"{v} + 2"])
        if r < 0.75:                               # always in range (unless the array is empty)
            return f"(({self.expr(d + 1, loops)}) % len({arr}) + len({arr})) % len({arr})"
        return self.expr(d + 1, loops)             # arbitrary: may be out of range

    def expr(self, d, loops):
        r = self.r.random()
        if d > 2 or r < 0.25:
            return self.r.choice([str(self.r.randint(0, 12)), str(self.r.randint(-5, 5))] + self.ints(loops))
        if r < 0.45:
            op = self.r.choice(["+", "-", "*", "/", "%", "<", "<=", ">", ">=", "==", "!=", "&", "|"])
            return f"({self.expr(d + 1, loops)} {op} {self.expr(d + 1, loops)})"
        if r < 0.52:
            return f"(-{self.expr(d + 1, loops)})" if self.r.random() < 0.5 else f"(~{self.expr(d + 1, loops)})"
        if r < 0.75:
            arr = self.r.choice(["arr", "L"])
            return f"{arr}[{self.idx(d, loops, arr)}]"
        if r < 0.82:
            return f"len({self.r.choice(['arr', 'L'])})"
        if r < 0.92 and self.cur > 0:
            f = self.r.randrange(self.cur)
            return f"f{f}({self.expr(d + 1, loops)}, {self.expr(d + 1, loops)}, {self.r.choice(['arr', 'L'])})"
        return str(self.r.randint(0, 9))

    # ---- statements -------------------------------------------------------
    def stmt(self, d, loops, ind):
        sp = "  " * ind
        r = self.r.random()
        if r < 0.22:
            return f"{sp}{self.expr(1, loops)} => {self.r.choice(['v0', 'v1', 'v2'])};"
        if r < 0.38:
            arr = self.r.choice(["arr", "L"])
            return f"{sp}{self.expr(1, loops)} => {arr}[{self.idx(1, loops, arr)}];"
        if r < 0.50:
            return f"{sp}{self.expr(1, loops)} => show;"
        if r < 0.56:
            return f"{sp}new[{self.r.randint(0, 9)}] => L;"
        if r < 0.59:
            return f"{sp}arr => L;"
        if r < 0.64 and self.cur > 0:
            f = self.r.randrange(self.cur)
            return f"{sp}f{f}({self.expr(2, loops)}, {self.expr(2, loops)}, {self.r.choice(['arr', 'L'])});"
        if d >= 2:
            return f"{sp}{self.expr(1, loops)} => v0;"
        if r < 0.76:
            body = self.block(d + 1, loops, ind + 1)
            s = f"{sp}when {self.expr(1, loops)} {{\n{body}\n{sp}}}"
            if self.r.random() < 0.5:
                s += f" otherwise {{\n{self.block(d + 1, loops, ind + 1)}\n{sp}}}"
            return s
        if r < 0.92:
            v = f"i{self.loopvars}"; self.loopvars += 1
            arr = self.r.choice(["arr", "L"])
            lo = self.r.choice(["0", "0", "1", str(self.r.randint(-2, 3))])
            hi = self.r.choice([f"len({arr})", f"len({arr})", f"len({arr}) - 1", f"len({arr}) - 2", str(self.r.randint(0, 6)), self.expr(2, loops)])
            body = self.block(d + 1, loops + [v], ind + 1)
            return f"{sp}loop {v} in {lo}..{hi} {{\n{body}\n{sp}}}"
        g = f"g{self.loopvars}"; self.loopvars += 1
        body = self.block(d + 1, loops, ind + 1)
        return f"{sp}0 => {g};\n{sp}loop {g} < 3 & {self.expr(1, loops)} {{\n{body}\n{sp}  {g} + 1 => {g};\n{sp}}}"

    def block(self, d, loops, ind):
        return "\n".join(self.stmt(d, loops, ind) for _ in range(self.r.randint(1, 3)))

    def function(self, i):
        self.cur = i
        body = [f"  {self.r.randint(0, 5)} => v0;  {self.r.randint(0, 5)} => v1;  {self.r.randint(0, 5)} => v2;",
                f"  new[{self.r.randint(0, 9)}] => L;"]
        body += [self.stmt(0, [], 1) for _ in range(self.r.randint(3, 6))]
        if self.r.random() < 0.7:
            body.append(f"  give {self.expr(1, [])};")
        return f"fn f{i}(p, q, arr[]) {{\n" + "\n".join(body) + "\n}\n"

    def program(self):
        n = self.r.randint(1, 4)
        parts = [self.function(i) for i in range(n)]
        self.cur = n
        main = ["fn main() {", f"  {self.r.randint(0,9)} => v0;  {self.r.randint(0,9)} => v1;  {self.r.randint(0,9)} => v2;  {self.r.randint(0,9)} => p;  {self.r.randint(0,9)} => q;",
                f"  [{', '.join(str(self.r.randint(-5, 20)) for _ in range(self.r.randint(0, 9)))}] => arr;",
                "  new[5] => L;"]
        for _ in range(self.r.randint(2, 4)):
            f = self.r.randrange(n)
            main.append(f"  f{f}({self.expr(2, [])}, {self.expr(2, [])}, arr) => show;")
        main.append("}\n")
        return "\n".join(parts) + "\n".join(main)

def run(cmd, **kw):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kw)
    return p.returncode, p.stdout, p.stderr

def main():
    rnd = random.Random(SEED)
    bad = skipped = elim = checks = 0
    with tempfile.TemporaryDirectory() as tmp:
        for n in range(N):
            src = os.path.join(tmp, "p.arw")
            open(src, "w").write(Gen(rnd).program())
            irc, iout, ierr = run([INTERP, src])
            if irc == 1 and "error(s)" in ierr:           # the generator made an invalid program: skip it
                skipped += 1
                continue
            for flags in (["-O2", "--stats"], ["-O0", "--no-bce"]):
                exe = os.path.join(tmp, "p.bin")
                c = subprocess.run([COMP, *flags, src, "-o", exe], capture_output=True, text=True)
                if c.returncode != 0:
                    print(f"program {n}: COMPILER FAILED\n{c.stdout}{c.stderr}"); bad += 1; break
                if "--stats" in flags:
                    for line in c.stdout.splitlines():
                        if line.startswith("bounds checks:"):
                            parts = line.split()
                            checks += int(parts[2]); elim += int(parts[5])
                rc, out, err = run([exe])
                if (rc, out, err) != (irc, iout, ierr):
                    bad += 1
                    keep = f"/tmp/arrow_fuzz_fail_{SEED}_{n}.arw"
                    os.replace(src, keep)
                    print(f"program {n}: MISMATCH with {' '.join(flags)} (saved as {keep})")
                    print(f"  interpreter: rc={irc} out={iout[:80]!r} err={ierr.strip()[:100]!r}")
                    print(f"  compiled   : rc={rc} out={out[:80]!r} err={err.strip()[:100]!r}")
                    break
    ran = N - skipped
    print(f"fuzz: {ran} programs compared ({skipped} invalid ones skipped), {bad} mismatches; "
          f"BCE removed {elim} of {checks} checks")
    return 1 if bad else 0

sys.exit(main())
