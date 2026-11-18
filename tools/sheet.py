#!/usr/bin/env python3
"""Tile PNG snapshots into one contact sheet: sheet.py OUT.png COLS a.png b.png ..."""
import struct, sys, zlib


def read_png(path):
    d = open(path, "rb").read()
    pos, chunks = 8, []
    w = h = ct = 0
    idat = b""
    while pos < len(d):
        n = struct.unpack(">I", d[pos:pos + 4])[0]
        t = d[pos + 4:pos + 8]
        body = d[pos + 8:pos + 8 + n]
        if t == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", body[:10])
        elif t == b"IDAT":
            idat += body
        pos += 12 + n
    bpp = {2: 3, 6: 4}[ct]
    raw = zlib.decompress(idat)
    rows, prev = [], bytearray(w * bpp)
    i = 0
    for y in range(h):
        f = raw[i]; i += 1
        line = bytearray(raw[i:i + w * bpp]); i += w * bpp
        for x in range(len(line)):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x * bpp:x * bpp + 3]) for x in range(w)])
        prev = line
    return w, h, rows


def write_png(path, w, h, rows):
    raw = b"".join(b"\0" + bytes(c for p in r for c in p) for r in rows)
    ch = lambda t, b: struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) +
                           ch(b"IDAT", zlib.compress(raw, 6)) + ch(b"IEND", b""))


def main():
    out, cols, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
    imgs = [read_png(f) for f in files]
    w, h = imgs[0][0], imgs[0][1]
    nr = (len(imgs) + cols - 1) // cols
    W, H = cols * (w + 4), nr * (h + 4)
    sheet = [[(40, 40, 40)] * W for _ in range(H)]
    for k, (iw, ih, rows) in enumerate(imgs):
        ox, oy = (k % cols) * (w + 4), (k // cols) * (h + 4)
        for y in range(ih):
            sheet[oy + y][ox:ox + iw] = rows[y]
    write_png(out, W, H, sheet)


if __name__ == "__main__":
    main()
