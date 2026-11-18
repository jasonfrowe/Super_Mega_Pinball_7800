#!/usr/bin/env python3
"""Decode 'peek 2300 34' lines from a test run: ball 0 position (units), velocity, layer."""
import sys
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) > 2 and p[1] == "2300":
        b = [int(x, 16) for x in p[2:]]
        s16 = lambda lo, hi: (b[hi] * 256 + b[lo]) - (65536 if b[hi] & 128 else 0)
        x = (b[9] * 256 + b[6]) / 16
        y = (b[18] * 256 + b[15]) / 16
        vx = s16(0x15, 0x18) / 256
        vy = s16(0x1B, 0x1E) / 256
        print(f"{p[0]:>5} act={b[0]} x={x:6.1f} y={y:6.1f} vx={vx:6.2f} vy={vy:6.2f} lay={b[0x21]}")
    else:
        print(line.rstrip())
