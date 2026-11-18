#!/usr/bin/env python3
"""Find each attract frame's vertical scroll by matching it against the previous frame;
report frames whose shift is not the expected 0/1 line."""
import sys, glob
sys.path.insert(0, "tools")
from sheet import read_png  # noqa
files = sorted(glob.glob(sys.argv[1] + "/*.png"))
prev = None
cams = {}
for l in open(sys.argv[2]):
    p = l.split()
    if p[1] == "18fd":
        cams[int(p[0])] = int(p[2], 16) + 256 * int(p[3], 16)
for i, f in enumerate(files):
    w, h, rows = read_png(f)
    band = [tuple(r[0:320:3]) for r in rows[40:230]]
    if prev is not None:
        best = None
        for d in range(-20, 21):
            err = 0
            n = 0
            for y in range(30, 160):
                yy = y + d
                if 0 <= yy < len(prev):
                    err += sum(1 for a, b in zip(band[y], prev[yy]) if a != b); n += 1
            e = err / max(n, 1)
            if best is None or e < best[0]:
                best = (e, d)
        if abs(best[1]) > 1 or best[0] > 3:
            print(f"frame {i} ({f[-8:]}): shift {best[1]} err {best[0]:.2f} cam {cams.get(800 + i - 1)}->{cams.get(800 + i)}")
    prev = band
print("checked", len(files))
