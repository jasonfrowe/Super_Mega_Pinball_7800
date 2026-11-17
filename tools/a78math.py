#!/usr/bin/env python3
"""Mark an .a78 file as using the AstroCart math unit (docs/MATHUNIT.md).

  a78math.py GAME.a78             set header bytes 59-61 to "ACM"
  a78math.py --off GAME.a78       clear them
  a78math.py --show GAME.a78      say whether they are set
  a78math.py --new ROM.bin OUT.a78 [--title T]
                                  wrap a plain ROM (a multiple of 4K, at most 48K,
                                  no bank switching) in a header with the bytes set
"""
import argparse
import sys

SIG = b"ACM"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--off", action="store_true")
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--new", action="store_true")
    ap.add_argument("--title", default="")
    a = ap.parse_args()
    if a.new:
        if not a.out:
            sys.exit("--new needs ROM.bin and OUT.a78")
        rom = open(a.file, "rb").read()
        if len(rom) % 4096 or not 0 < len(rom) <= 48 * 1024:
            sys.exit("the ROM must be a multiple of 4K, at most 48K")
        h = bytearray(128)
        h[0] = 3
        h[1:17] = b"ATARI7800".ljust(16, b" ")
        h[17:49] = a.title.encode("ascii")[:32].ljust(32, b"\0")
        h[49:53] = len(rom).to_bytes(4, "big")
        h[55] = h[56] = 1                      # joysticks
        h[59:62] = SIG
        h[100:128] = b"ACTUAL CART DATA STARTS HERE"
        open(a.out, "wb").write(bytes(h) + rom)
        print(f"{a.out}: {len(rom) // 1024}K ROM, math unit on")
        return
    d = bytearray(open(a.file, "rb").read())
    if d[1:10] != b"ATARI7800":
        sys.exit(f"{a.file}: not an .a78 file")
    if a.show:
        print(f"{a.file}: math unit {'on' if d[59:62] == SIG else 'off'}")
        return
    d[59:62] = b"\0\0\0" if a.off else SIG
    open(a.file, "wb").write(d)
    print(f"{a.file}: math unit {'off' if a.off else 'on'}")


if __name__ == "__main__":
    main()
