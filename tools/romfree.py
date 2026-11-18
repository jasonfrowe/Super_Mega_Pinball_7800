#!/usr/bin/env python3
"""Report free space in each code segment from the dasm symbol file."""
import re, sys
syms = {}
for line in open(sys.argv[1]):
    m = re.match(r"(\S+)\s+([0-9a-fA-F]{4})\b", line)
    if m:
        syms[m.group(1)] = int(m.group(2), 16)
# the last label in each 4K segment approximates its end
for seg in (0x9000, 0xB000, 0xD000, 0xF000):
    top = max((v for v in syms.values() if seg <= v < seg + 0x1000), default=seg)
    print(f"  ${seg:04X}: about {seg + 0x1000 - top} bytes free")
