#!/usr/bin/env python3
"""Wrap the 48K ROM in an .a78 header (version 4).

Cart type: no bank switching, POKEY at $0450 (bit 6) and at $0440 (bit 10,
the "dual POKEY 440 450" carts); the v4 audio field (byte 67) says the same
(3 = $0440 + $0450). Bytes 59-61 "ACM" turn on the AstroCart math unit.
"""
import sys

rom = open(sys.argv[1], "rb").read()
assert len(rom) == 48 * 1024
h = bytearray(128)
h[0] = 4
h[1:17] = b"ATARI7800".ljust(16, b" ")
h[17:49] = b"Super Mega Pinball 7800".ljust(32, b"\0")
h[49:53] = len(rom).to_bytes(4, "big")
ctype = 0x0040 | 0x0400
h[53] = ctype >> 8
h[54] = ctype & 0xFF
h[55] = 1          # joystick (7800 two-button)
h[56] = 1
h[57] = 0          # NTSC
h[58] = 0
h[59:62] = b"ACM"
h[67] = 3          # v4 audio: POKEYs at $0440 and $0450
h[100:128] = b"ACTUAL CART DATA STARTS HERE"
open(sys.argv[2], "wb").write(bytes(h) + rom)
print(f"{sys.argv[2]}: 48K, POKEYs $0450+$0440, math unit")
