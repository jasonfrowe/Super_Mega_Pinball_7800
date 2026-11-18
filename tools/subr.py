#!/usr/bin/env python3
"""strip|add the SUBROUTINE lines dasm needs before each routine label (local label scopes)."""
import re, sys
mode, files = sys.argv[1], sys.argv[2:]
for f in files:
    lines = open(f).read().split("\n")
    lines = [l for l in lines if l.strip() != "SUBROUTINE"]
    if mode == "add":
        out = []
        for l in lines:
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*\s*(;.*)?$", l) and l.split()[0] not in ("START", "IRQ"):
                out.append("    SUBROUTINE")
            out.append(l)
        lines = out
    open(f, "w").write("\n".join(lines))
