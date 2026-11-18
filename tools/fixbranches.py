#!/usr/bin/env python3
"""Turn out-of-range branches reported by dasm into inverted branch + jmp."""
import re, subprocess, sys
INV = {"beq": "bne", "bne": "beq", "bcc": "bcs", "bcs": "bcc", "bmi": "bpl", "bpl": "bmi", "bvc": "bvs", "bvs": "bvc"}
for it in range(20):
    r = subprocess.run(["wasmtime", "run", "--dir=.", "tools/7800basic/dasm.wasm", "src/main.asm", "-Isrc", "-f3",
                        "-obuild/pinball.bin"], capture_output=True, text=True)
    errs = re.findall(r"^(\S+\.asm) \((\d+)\): error: Branch out of range", r.stdout + r.stderr, re.M)
    if not errs:
        print("no out-of-range branches left")
        break
    byfile = {}
    for f, n in errs:
        byfile.setdefault(f, set()).add(int(n))
    for f, ns in byfile.items():
        path = f if f.startswith("src/") else "src/" + f
        lines = open(path).read().split("\n")
        for n in sorted(ns, reverse=True):
            l = lines[n - 1]
            m = re.match(r"^(\s*)(b(?:eq|ne|cc|cs|mi|pl|vc|vs))\s+(\S+)(.*)$", l)
            if not m:
                continue
            ind, op, tgt, rest = m.groups()
            lines[n - 1:n] = [f"{ind}{INV[op]} *+5{rest}", f"{ind}jmp {tgt}"]
        open(path, "w").write("\n".join(lines))
    print(f"pass {it}: fixed {len(errs)}")
