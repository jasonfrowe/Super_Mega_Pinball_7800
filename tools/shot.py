#!/usr/bin/env python3
"""Make a test script: start a game, put ball 0 at x,y (units) with vx,vy (units/frame), log it.
   shot.py OUT x y vx vy [frames] [snap_every]"""
import sys
out, x, y, vx, vy = sys.argv[1], *map(float, sys.argv[2:6])
n = int(sys.argv[6]) if len(sys.argv) > 6 else 300
se = int(sys.argv[7]) if len(sys.argv) > 7 else 0
L = ["250 press P1 Button 1", "256 release P1 Button 1"]
f0 = 300
x16, y16 = int(x * 16), int(y * 16)
vxi, vyi = int(vx * 256) & 0xFFFF, int(vy * 256) & 0xFFFF
L += [f"{f0} poke 2306 {x16 & 255:02x}", f"{f0} poke 2309 {x16 >> 8:02x}",
      f"{f0} poke 230f {y16 & 255:02x}", f"{f0} poke 2312 {y16 >> 8:02x}",
      f"{f0} poke 2315 {vxi & 255:02x}", f"{f0} poke 2318 {vxi >> 8:02x}",
      f"{f0} poke 231b {vyi & 255:02x}", f"{f0} poke 231e {vyi >> 8:02x}"]
for f in range(f0, f0 + n, 3):
    L.append(f"{f} peek 2300 34")
if se:
    for f in range(f0, f0 + n, se):
        L.append(f"{f} snap")
L.append(f"{f0 + n} exit")
open(out, "w").write("\n".join(L) + "\n")
