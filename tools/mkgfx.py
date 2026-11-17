#!/usr/bin/env python3
"""Generate 160A graphics, playfield tilemap, and assembly tables for Super Mega Pinball 7800.

Pure Python (zero external dependencies). Inspired by Pinball Dreams (Amiga 500)
and AtariGammaForce's 160A vertical scrolling engine.
Outputs:
  src/gfx/*.png        160A indexed 2-bit PNGs (4 colors: 0 = transparent, 1..3 = palette slots)
  src/gen/gfx.bas      incgraphic statements for 7800basic
  src/gen/consts.bas   shared constants for 7800basic and assembly
  src/gen/data.asm     palette table, sprite descriptor tables, text strings, and 20-row table map
"""

from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parent.parent
GFX = ROOT / "src" / "gfx"
GEN = ROOT / "src" / "gen"

# 8 Hardware 160A Palettes (3 colors each + shared background $00 = black)
BG_CODE = 0x00
PAL_CODES = [
    [0x04, 0x0A, 0x0F],  # P0: HUD Text, Chrome Rails & Outer Walls (Dark Gray, Silver, White)
    [0x24, 0x1A, 0x0F],  # P1: Gold Flippers, Plunger & Score Popups (Bronze, Bright Gold, White)
    [0x32, 0x36, 0x1E],  # P2: Hot Neon Red / Crimson Pop Bumpers (Dark Red, Neon Red, Yellow Core)
    [0x84, 0x98, 0x9E],  # P3: Electric Cyan "HYPER RAMP" & Rollover Lanes (Deep Blue, Cyan, Ice White)
    [0x52, 0x58, 0x5E],  # P4: Neon Magenta "WARP CHUTE", Slingshots & Spinner (Violet, Magenta, Pink)
    [0xC2, 0xC8, 0xCE],  # P5: Emerald Green Drop Targets & Multi-Ball Lock (Forest, Neon Lime, Mint)
    [0x22, 0x28, 0x1E],  # P6: "IGNITION" Rocket Centerpiece & Jackpot Trim (Rust, Blazing Orange, Yellow)
    [0x94, 0x0C, 0x0F],  # P7: Chrome Steel Pinballs & Sparks (Steel Blue Shadow, Chrome Silver, White Glint)
]

PREVIEW_RGB = [
    (0, 0, 0),
    [(70, 70, 80), (170, 175, 190), (255, 255, 255)],
    [(140, 80, 20), (245, 200, 40), (255, 255, 255)],
    [(130, 20, 30), (240, 50, 60), (255, 235, 80)],
    [(20, 60, 160), (40, 190, 255), (210, 245, 255)],
    [(110, 20, 130), (220, 50, 210), (255, 180, 250)],
    [(20, 110, 40), (50, 225, 90), (200, 255, 210)],
    [(140, 50, 10), (245, 120, 20), (255, 235, 80)],
    [(60, 90, 140), (200, 205, 215), (255, 255, 255)],
]


def save_160a(path: Path, grid, pal_idx: int):
    """Write a 2D list of 2-bit slot indices (0..3) as a 2-bit indexed PNG for 7800basic."""
    h, w = len(grid), len(grid[0])
    assert w % 4 == 0, f"Width {w} must be a multiple of 4 for 2-bit PNG"
    raw = bytearray()
    for row in grid:
        raw.append(0)  # Filter type 0 (None)
        for x in range(0, w, 4):
            b = ((row[x] & 3) << 6) | ((row[x + 1] & 3) << 4) | ((row[x + 2] & 3) << 2) | (row[x + 3] & 3)
            raw.append(b)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    plte = bytearray(PREVIEW_RGB[0])
    for rgb in PREVIEW_RGB[pal_idx + 1]:
        plte.extend(rgb)

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 2, 3, 0, 0, 0))
        + chunk(b"PLTE", bytes(plte))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def empty_grid(h=16, w=8):
    return [[0] * w for _ in range(h)]


def mirror_h(grid):
    return [list(reversed(r)) for r in grid]


def hcat(grids):
    h = len(grids[0])
    return [[c for g in grids for c in g[y]] for y in range(h)]


def art_to_grid(rows):
    return [[".123".index(ch) for ch in r] for r in rows]


# ---------------------------------------------------------------------------
# 1. Font Glyphs (8x16 each, glyph drawn on bottom 7 lines 9..15 for 7-line HUD zone)
# ---------------------------------------------------------------------------
FONT_CHARS = "0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ:!x-"

GLYPH_BITMAPS = {
    "0": [".11111..", "11...11.", "11..111.", "11.1.11.", "111..11.", "11...11.", ".11111.."],
    "1": ["..111...", ".1111...", "...11...", "...11...", "...11...", "...11...", ".111111."],
    "2": [".11111..", "11...11.", ".....11.", "..1111..", ".11.....", "11......", "1111111."],
    "3": [".11111..", "11...11.", ".....11.", "..1111..", ".....11.", "11...11.", ".11111.."],
    "4": ["...111..", "..1111..", ".11.11..", "11..11..", "1111111.", "....11..", "....11.."],
    "5": ["1111111.", "11......", "111111..", ".....11.", ".....11.", "11...11.", ".11111.."],
    "6": [".11111..", "11......", "111111..", "11...11.", "11...11.", "11...11.", ".11111.."],
    "7": ["1111111.", ".....11.", "....11..", "...11...", "..11....", "..11....", "..11...."],
    "8": [".11111..", "11...11.", "11...11.", ".11111..", "11...11.", "11...11.", ".11111.."],
    "9": [".11111..", "11...11.", "11...11.", ".111111.", ".....11.", "11...11.", ".11111.."],
    " ": ["........"] * 7,
    "A": ["..111...", ".11.11..", "11...11.", "1111111.", "11...11.", "11...11.", "11...11."],
    "B": ["111111..", "11...11.", "11...11.", "111111..", "11...11.", "11...11.", "111111.."],
    "C": [".11111..", "11...11.", "11......", "11......", "11......", "11...11.", ".11111.."],
    "D": ["11111...", "11..11..", "11...11.", "11...11.", "11...11.", "11..11..", "11111..."],
    "E": ["1111111.", "11......", "11......", "111111..", "11......", "11......", "1111111."],
    "F": ["1111111.", "11......", "11......", "111111..", "11......", "11......", "11......"],
    "G": [".11111..", "11...11.", "11......", "11..111.", "11...11.", "11...11.", ".11111.."],
    "H": ["11...11.", "11...11.", "11...11.", "1111111.", "11...11.", "11...11.", "11...11."],
    "I": [".11111..", "...11...", "...11...", "...11...", "...11...", "...11...", ".11111.."],
    "J": ["..11111.", "....11..", "....11..", "....11..", "11..11..", "11..11..", ".1111..."],
    "K": ["11...11.", "11..11..", "11.11...", "1111....", "11.11...", "11..11..", "11...11."],
    "L": ["11......", "11......", "11......", "11......", "11......", "11......", "1111111."],
    "M": ["11...11.", "111.111.", "1111111.", "11.1.11.", "11...11.", "11...11.", "11...11."],
    "N": ["11...11.", "111..11.", "1111.11.", "11.1111.", "11..111.", "11...11.", "11...11."],
    "O": [".11111..", "11...11.", "11...11.", "11...11.", "11...11.", "11...11.", ".11111.."],
    "P": ["111111..", "11...11.", "11...11.", "111111..", "11......", "11......", "11......"],
    "Q": [".11111..", "11...11.", "11...11.", "11...11.", "11.1.11.", "11..11..", ".1111.1."],
    "R": ["111111..", "11...11.", "11...11.", "111111..", "11.11...", "11..11..", "11...11."],
    "S": [".11111..", "11...11.", "11......", ".11111..", ".....11.", "11...11.", ".11111.."],
    "T": ["1111111.", "...11...", "...11...", "...11...", "...11...", "...11...", "...11..."],
    "U": ["11...11.", "11...11.", "11...11.", "11...11.", "11...11.", "11...11.", ".11111.."],
    "V": ["11...11.", "11...11.", "11...11.", "11...11.", ".11.11..", "..111...", "...1...."],
    "W": ["11...11.", "11...11.", "11...11.", "11.1.11.", "1111111.", "111.111.", "11...11."],
    "X": ["11...11.", ".11.11..", "..111...", "..111...", "..111...", ".11.11..", "11...11."],
    "Y": ["11...11.", "11...11.", ".11.11..", "..111...", "...11...", "...11...", "...11..."],
    "Z": ["1111111.", "....11..", "...11...", "..11....", ".11.....", "11......", "1111111."],
    ":": ["........", "..11....", "..11....", "........", "..11....", "..11....", "........"],
    "!": ["..11....", "..11....", "..11....", "..11....", "........", "..11....", "..11...."],
    "x": ["........", "11...11.", ".11.11..", "..111...", ".11.11..", "11...11.", "........"],
    "-": ["........", "........", "........", ".11111..", "........", "........", "........"],
}

NFONT = len(FONT_CHARS)


def build_font_glyphs():
    glyphs = []
    for ch in FONT_CHARS:
        g = empty_grid(16, 8)
        rows = GLYPH_BITMAPS[ch]
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c == "1":
                    g[9 + y][x] = 3 if y < 5 else 2
        glyphs.append(g)
    return glyphs


def char_index(ch: str) -> int:
    idx = FONT_CHARS.index(ch) if ch in FONT_CHARS else FONT_CHARS.index(" ")
    return 2 * idx


# ---------------------------------------------------------------------------
# 2. Playfield Background Tiles (8x16 each in 160A)
# ---------------------------------------------------------------------------
def build_table_tiles():
    tiles = []
    pals = []

    def add_tile(grid, pal):
        t_idx = len(tiles)
        tiles.append(grid)
        pals.append(pal)
        return t_idx

    # Tile 0: Blank background (never drawn, costs 0 DMA!)
    add_tile(empty_grid(16, 8), 0)

    # Tile 1: Left Chrome Wall (col 1, X=8..15) - P0
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][4] = 1
        t[y][5] = 1
        t[y][6] = 2
        t[y][7] = 3
        if y in (0, 7, 8, 15):
            t[y][4] = 2
            t[y][5] = 2
    T_WALL_L = add_tile(t, 0)

    # Tile 2: Right Chrome Wall (col 18, X=144..151) - P0
    T_WALL_R = add_tile(mirror_h(t), 0)

    # Tile 3: Plunger Lane Divider Wall (col 16, X=128..135) - P0
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][2] = 3
        t[y][3] = 2
        t[y][4] = 2
        t[y][5] = 1
        if y in (3, 11):
            t[y][3] = 3
            t[y][4] = 3
    T_PLUNGE_DIV = add_tile(t, 0)

    # Tile 4: Plunger Shooter Lane Track (col 17, X=136..143) - P5 (Emerald gauge ticks)
    t = empty_grid(16, 8)
    for y in range(0, 16, 4):
        for x in range(2, 6):
            t[y][x] = 1
    t[2][3] = 2
    t[2][4] = 2
    t[10][3] = 2
    t[10][4] = 2
    T_PLUNGE_TRK = add_tile(t, 5)

    # Tile 5: Top Arch Left Curve (P3 Electric Cyan)
    t = empty_grid(16, 8)
    for y in range(16):
        x0 = max(0, 6 - y // 2)
        for x in range(x0, min(8, x0 + 2)):
            t[y][x] = 3
        if x0 + 2 < 8:
            t[y][x0 + 2] = 2
    T_ARCH_L = add_tile(t, 3)

    # Tile 6: Top Arch Horizontal Rail (P3 Electric Cyan)
    t = empty_grid(16, 8)
    for x in range(8):
        t[2][x] = 3
        t[3][x] = 3
        t[4][x] = 2
        t[5][x] = 2
        t[6][x] = 1
    T_ARCH_H = add_tile(t, 3)

    # Tile 7: Top Arch Right Curve (P3 Electric Cyan)
    T_ARCH_R = add_tile(mirror_h(tiles[T_ARCH_L]), 3)

    # Tile 8: Top Rollover Lane Divider Post (P3 Cyan/White)
    t = empty_grid(16, 8)
    for y in range(2, 14):
        t[y][3] = 3
        t[y][4] = 2
    t[1][3] = 3
    t[1][4] = 3
    t[14][3] = 1
    t[14][4] = 1
    T_ROLL_DIV = add_tile(t, 3)

    # Tile 9: Left "HYPER RAMP" Track (P3 Electric Cyan chevrons pointing up)
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][0] = 2
        t[y][7] = 2
    for base in (2, 10):
        t[base][3] = t[base][4] = 3
        for x in range(2, 6):
            t[base + 1][x] = 3
        for x in range(1, 7):
            t[base + 2][x] = 2
        t[base + 3][1] = t[base + 3][2] = t[base + 3][5] = t[base + 3][6] = 1
    T_RAMP_L = add_tile(t, 3)

    # Tile 10: Right "WARP CHUTE" Track (P4 Neon Magenta chevrons)
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][0] = 2
        t[y][7] = 2
    for base in (2, 10):
        t[base][3] = t[base][4] = 3
        for x in range(2, 6):
            t[base + 1][x] = 3
        for x in range(1, 7):
            t[base + 2][x] = 2
    T_CHUTE_R = add_tile(t, 4)

    # Tile 11: Center "IGNITION" Sunburst / Star Grid Left (P6 Orange/Yellow)
    t = empty_grid(16, 8)
    for y in range(2, 14):
        for x in range(1, 8):
            if (x + y) % 3 == 0:
                t[y][x] = 2 if (y < 6 or y > 10) else 3
            elif (x * y) % 5 == 0:
                t[y][x] = 1
    T_CORE_L = add_tile(t, 6)

    # Tile 12: Center "IGNITION" Sunburst / Star Grid Right (P6 Orange/Yellow)
    T_CORE_R = add_tile(mirror_h(t), 6)

    # Tile 13: Drop Target Backing Bank (col 2, X=16..23) - P5 Emerald Green
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][0] = 2
        t[y][1] = 2
        if y in (2, 3, 4, 5, 10, 11, 12, 13):
            t[y][2] = 3
            t[y][3] = 3
            t[y][4] = 2
    T_DROP_WALL = add_tile(t, 5)

    # Tile 14: Left Slingshot Diagonal Kicker (P4 Neon Magenta)
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][0] = 2
        dx = min(7, y // 2)
        t[y][dx] = 3
        if dx > 0:
            t[y][dx - 1] = 1
    T_SLING_L = add_tile(t, 4)

    # Tile 15: Right Slingshot Diagonal Kicker (P4 Neon Magenta)
    T_SLING_R = add_tile(mirror_h(t), 4)

    # Tile 16: Left Inlane Funnel Rail (slopes down-right toward Left Flipper) - P0 Chrome
    t = empty_grid(16, 8)
    for y in range(16):
        x = y // 2
        for k in range(x, min(8, x + 2)):
            t[y][k] = 3
        if x > 0:
            t[y][x - 1] = 2
    T_FUNNEL_L = add_tile(t, 0)

    # Tile 17: Right Inlane Funnel Rail (slopes down-left toward Right Flipper) - P0 Chrome
    T_FUNNEL_R = add_tile(mirror_h(t), 0)

    # Tile 18: Bonus Multiplier Diamond Floor Decal (P3 Cyan/Blue)
    t = empty_grid(16, 8)
    diamond = [
        "...22...",
        "..2332..",
        ".231132.",
        "23133132",
        "23133132",
        ".231132.",
        "..2332..",
        "...22...",
    ]
    for y, r in enumerate(diamond):
        for x, c in enumerate(r):
            if c != ".":
                t[4 + y][x] = int(c)
    T_DEC_DIAMOND = add_tile(t, 3)

    # Tile 19: Neon Starfield / Table Floor Accent (P4 Violet/Pink)
    t = empty_grid(16, 8)
    t[3][3] = 2
    t[3][4] = 3
    t[11][2] = 1
    t[12][5] = 2
    T_DEC_STAR = add_tile(t, 4)

    # Tile 20: Drain Apron Left (P2 Red/Gold)
    t = empty_grid(16, 8)
    for y in range(16):
        lim = min(8, 2 + y // 2)
        for x in range(lim):
            t[y][x] = 1
        if lim < 8:
            t[y][lim] = 2
        if lim + 1 < 8:
            t[y][lim + 1] = 3
    T_APRON_L = add_tile(t, 2)

    # Tile 21: Drain Apron Right (P2 Red/Gold)
    T_APRON_R = add_tile(mirror_h(t), 2)

    names = {
        "EMPTY": 0,
        "WALL_L": T_WALL_L,
        "WALL_R": T_WALL_R,
        "PLUNGE_DIV": T_PLUNGE_DIV,
        "PLUNGE_TRK": T_PLUNGE_TRK,
        "ARCH_L": T_ARCH_L,
        "ARCH_H": T_ARCH_H,
        "ARCH_R": T_ARCH_R,
        "ROLL_DIV": T_ROLL_DIV,
        "RAMP_L": T_RAMP_L,
        "CHUTE_R": T_CHUTE_R,
        "CORE_L": T_CORE_L,
        "CORE_R": T_CORE_R,
        "DROP_WALL": T_DROP_WALL,
        "SLING_L": T_SLING_L,
        "SLING_R": T_SLING_R,
        "FUNNEL_L": T_FUNNEL_L,
        "FUNNEL_R": T_FUNNEL_R,
        "DEC_DIAMOND": T_DEC_DIAMOND,
        "DEC_STAR": T_DEC_STAR,
        "APRON_L": T_APRON_L,
        "APRON_R": T_APRON_R,
    }
    return tiles, pals, names


# ---------------------------------------------------------------------------
# 3. Build 20-Row x 20-Column Pinball Table Map
#    Row 19 = Top of Table (world_y = 0..15)
#    Row 0  = Bottom of Table (world_y = 304..319)
# ---------------------------------------------------------------------------
def build_pinball_map(T):
    m = [[0] * 20 for _ in range(20)]

    for r in range(20):
        m[r][1] = T["WALL_L"]
        m[r][18] = T["WALL_R"]

    for r in range(17):
        m[r][16] = T["PLUNGE_DIV"]
        m[r][17] = T["PLUNGE_TRK"]
    m[17][17] = T["PLUNGE_TRK"]

    # Row 19 (world_y = 0..15): Top Orbital Arch Roof
    m[19][2] = T["ARCH_L"]
    for c in range(3, 17):
        m[19][c] = T["ARCH_H"]
    m[19][17] = T["ARCH_R"]

    # Row 18 (world_y = 16..31): Upper Arch & Shooter Exit
    m[18][2] = T["ARCH_L"]
    m[18][5] = T["DEC_STAR"]
    m[18][9] = T["DEC_DIAMOND"]
    m[18][13] = T["DEC_STAR"]
    m[18][17] = T["ARCH_R"]

    # Row 17 (world_y = 32..47): Top Rollover Lanes (I - G - N)
    for c in (4, 7, 10, 13):
        m[17][c] = T["ROLL_DIV"]

    # Rows 13..16 (world_y = 48..111): Upper Turbo Pop Bumper Arena
    m[16][3] = T["DEC_STAR"]
    m[16][14] = T["DEC_STAR"]
    m[15][8] = T["DEC_DIAMOND"]
    m[14][3] = T["DEC_STAR"]
    m[14][14] = T["DEC_STAR"]
    m[13][8] = T["DEC_DIAMOND"]

    # Rows 9..12 (world_y = 112..175): Left HYPER RAMP, Center IGNITION Core, Right WARP CHUTE
    for r in (9, 10, 11, 12):
        m[r][2] = T["RAMP_L"]
        m[r][3] = T["RAMP_L"]
        m[r][14] = T["CHUTE_R"]
        m[r][15] = T["CHUTE_R"]
    m[11][8] = T["CORE_L"]
    m[11][9] = T["CORE_R"]
    m[10][8] = T["CORE_L"]
    m[10][9] = T["CORE_R"]

    # Rows 6..8 (world_y = 176..223): Left Drop Target Bank & Center Bonus Diamonds
    for r in (6, 7, 8):
        m[r][2] = T["DROP_WALL"]
    m[8][8] = T["DEC_DIAMOND"]
    m[7][7] = T["DEC_DIAMOND"]
    m[7][9] = T["DEC_DIAMOND"]
    m[6][8] = T["DEC_DIAMOND"]

    # Rows 3..5 (world_y = 224..271): Slingshot Kickers & Inlane/Outlane Guides
    m[5][3] = T["ROLL_DIV"]
    m[5][4] = T["SLING_L"]
    m[5][13] = T["SLING_R"]
    m[5][14] = T["ROLL_DIV"]

    m[4][3] = T["ROLL_DIV"]
    m[4][4] = T["SLING_L"]
    m[4][5] = T["SLING_L"]
    m[4][8] = T["DEC_DIAMOND"]
    m[4][12] = T["SLING_R"]
    m[4][13] = T["SLING_R"]
    m[4][14] = T["ROLL_DIV"]

    m[3][2] = T["FUNNEL_L"]
    m[3][3] = T["FUNNEL_L"]
    m[3][14] = T["FUNNEL_R"]
    m[3][15] = T["FUNNEL_R"]

    # Row 2 (world_y = 272..287): Lower Funnel into Flippers
    m[2][3] = T["FUNNEL_L"]
    m[2][4] = T["FUNNEL_L"]
    m[2][5] = T["FUNNEL_L"]
    m[2][12] = T["FUNNEL_R"]
    m[2][13] = T["FUNNEL_R"]
    m[2][14] = T["FUNNEL_R"]

    # Row 1 (world_y = 288..303): Flipper Zone & Apron Top
    m[1][2] = T["APRON_L"]
    m[1][3] = T["APRON_L"]
    m[1][4] = T["APRON_L"]
    m[1][13] = T["APRON_R"]
    m[1][14] = T["APRON_R"]
    m[1][15] = T["APRON_R"]

    # Row 0 (world_y = 304..319): Drain Apron Bottom (Center Drain open at cols 7..10)
    for c in range(2, 7):
        m[0][c] = T["APRON_L"]
    for c in range(11, 16):
        m[0][c] = T["APRON_R"]

    return m


# ---------------------------------------------------------------------------
# 4. Interactive Sprites (160A, padded to 16 lines height)
# ---------------------------------------------------------------------------
def build_sprites():
    sprites = []

    def add_sprite(name, frames, pal, used_h):
        pad_frames = []
        for f in frames:
            h, w = len(f), len(f[0])
            w_pad = (4 - (w % 4)) % 4
            new_f = [r + [0] * w_pad for r in f]
            while len(new_f) < 16:
                new_f.append([0] * (w + w_pad))
            pad_frames.append(new_f)
        sheet = hcat(pad_frames)
        save_160a(GFX / f"{name}.png", sheet, pal)
        wb = len(pad_frames[0][0]) // 4
        sprites.append((name, wb, 1, len(pad_frames), used_h))

    # 0. Chrome Steel Pinball (4x6 in 160A = 8x6 TV pixels, 1 byte wide) - P7
    ball_f0 = art_to_grid([
        ".22.",
        "2332",
        "2321",
        "2211",
        "1211",
        ".11.",
    ])
    add_sprite("ball", [ball_f0], 7, used_h=6)

    # 1. Neon Pop Bumper (8x10 in 160A = 16x10 TV pixels, 2 bytes wide, 2 frames: Idle & Lit) - P2
    bmp_f0 = art_to_grid([
        "..1111..",
        ".122221.",
        "12333321",
        "12322321",
        "12233221",
        "12233221",
        "12322321",
        "12333321",
        ".122221.",
        "..1111..",
    ])
    bmp_f1 = art_to_grid([
        "..3333..",
        ".332233.",
        "33233233",
        "32333323",
        "32311323",
        "32311323",
        "32333323",
        "33233233",
        ".332233.",
        "..3333..",
    ])
    add_sprite("bumper", [bmp_f0, bmp_f1], 2, used_h=10)

    # 2. Left Flipper (12x12 in 160A = 24x12 TV pixels, 3 bytes wide, 3 frames: Down, Mid, Up) - P1
    flipl_down = art_to_grid([
        "............",
        "............",
        "............",
        ".333........",
        "23322.......",
        "1222322.....",
        "..1122322...",
        "....112232..",
        "......11232.",
        "........112.",
        "............",
        "............",
    ])
    flipl_mid = art_to_grid([
        "............",
        "............",
        "............",
        "............",
        ".333333332..",
        "23322222232.",
        "12211111111.",
        "............",
        "............",
        "............",
        "............",
        "............",
    ])
    flipl_up = art_to_grid([
        "........112.",
        "......11232.",
        "....112232..",
        "..1122322...",
        "1222322.....",
        "23322.......",
        ".333........",
        "............",
        "............",
        "............",
        "............",
        "............",
    ])
    add_sprite("flipl", [flipl_down, flipl_mid, flipl_up], 1, used_h=10)

    # 3. Right Flipper (12x12 in 160A, horizontally mirrored from Left Flipper) - P1
    add_sprite("flipr", [mirror_h(f) for f in (flipl_down, flipl_mid, flipl_up)], 1, used_h=10)

    # 4. Spring Plunger (4x12 in 160A, 1 byte wide, 3 compression frames) - P1
    plg_0 = art_to_grid([
        "3333",
        "2222",
        ".22.",
        ".22.",
        "1111",
        "..11",
        "11..",
        "..11",
        "11..",
        "..11",
        "1111",
        ".22.",
    ])
    plg_1 = art_to_grid([
        "....",
        "....",
        "....",
        "3333",
        "2222",
        ".22.",
        "1111",
        "..11",
        "11..",
        "1111",
        "..11",
        "1111",
    ])
    plg_2 = art_to_grid([
        "....",
        "....",
        "....",
        "....",
        "....",
        "....",
        "3333",
        "2222",
        "1111",
        "2222",
        "1111",
        "2222",
    ])
    add_sprite("plunger", [plg_0, plg_1, plg_2], 1, used_h=12)

    # 5. Drop Target / Lock Saucer Gem (4x6 in 160A, 1 byte wide, 2 frames: Active, Hit/Lit) - P5
    gem_0 = art_to_grid([
        ".22.",
        "2332",
        "2332",
        "2222",
        "1221",
        ".11.",
    ])
    gem_1 = art_to_grid([
        ".33.",
        "3113",
        "3113",
        ".33.",
        "....",
        "....",
    ])
    add_sprite("gem", [gem_0, gem_1], 5, used_h=6)

    # 6. Whirling Spinner (8x5 in 160A, 2 bytes wide, 2 frames) - P4
    spn_0 = art_to_grid([
        "11111111",
        ".233332.",
        "..2332..",
        ".233332.",
        "11111111",
    ])
    spn_1 = art_to_grid([
        "...33...",
        "11233211",
        "...33...",
        "11233211",
        "...33...",
    ])
    add_sprite("spinner", [spn_0, spn_1], 4, used_h=5)

    return sprites


def row_runs(pals, drawn):
    runs = []
    for c, p in enumerate(pals):
        if not drawn[c]:
            continue
        if runs and runs[-1][2] == p and runs[-1][0] + runs[-1][1] == c:
            runs[-1][1] += 1
        else:
            runs.append([c, 1, p])
    return runs


def main():
    GFX.mkdir(parents=True, exist_ok=True)
    GEN.mkdir(parents=True, exist_ok=True)

    font_glyphs = build_font_glyphs()
    t_slots, t_pals, T = build_table_tiles()

    sheet = hcat(font_glyphs + t_slots)
    save_160a(GFX / "charset.png", sheet, 0)

    sprites = build_sprites()
    m = build_pinball_map(T)

    bas = [
        "  rem Generated by tools/mkgfx.py. Do not edit.",
        "  incgraphic gfx/charset.png 160A 0 1 2 3",
    ]
    for name, *_ in sprites:
        bas.append(f"  incgraphic gfx/{name}.png 160A 0 1 2 3")
    # Put a dummy block at $E000 so charset + all gameplay sprites land at $C000
    # (surrounded by both $B000 and $D000 hardware 16-line DMA holes!)
    save_160a(GFX / "padblock.png", empty_grid(16, 4), 0)
    bas.append("  newblock")
    bas.append("  incgraphic gfx/padblock.png 160A 0 1 2 3")
    (GEN / "gfx.bas").write_text("\n".join(bas) + "\n")

    screen_texts = {
        "title1": "SUPER MEGA PINBALL",
        "title2": "IGNITION  7800",
        "press": "PULL DOWN TO LAUNCH",
        "multiball": "MULTI-BALL MANIA!",
        "jackpot": "SUPER JACKPOT!",
        "lock1": "BALL 1 LOCKED!",
        "lock2": "READY MULTI-BALL!",
        "ramp": "HYPER RAMP 10000!",
        "skill": "SKILL SHOT 5000!",
        "gameover": "GAME OVER",
    }

    consts = [
        "  rem Generated by tools/mkgfx.py. Do not edit.",
        f"  const BGCOLOR = ${BG_CODE:02X}",
        "  const FONTBASE = 0",
        f"  const NFONTCHARS = {2 * NFONT}",
    ]
    for i, (name, *_) in enumerate(sprites):
        consts.append(f"  const IMG_{name.upper()} = {i}")
    for i, label in enumerate(screen_texts):
        consts.append(f"  const TXT_{label.upper()} = {i}")
    (GEN / "consts.bas").write_text("\n".join(consts) + "\n")

    asm = [
        "; Generated by tools/mkgfx.py. Do not edit.",
        "",
        "hudinit .byte " + ",".join(str(char_index(c)) for c in "0000000  B:1  1X L:0"),
        "",
    ]
    for label, text in screen_texts.items():
        asm.append(f"txt_{label} .byte " + ",".join(str(char_index(c)) for c in text))
    names = list(screen_texts.keys())
    asm.append("txtlo .byte " + ",".join(f"<txt_{n}" for n in names))
    asm.append("txthi .byte " + ",".join(f">txt_{n}" for n in names))
    asm.append("txtlen .byte " + ",".join(str(len(screen_texts[n])) for n in names))
    asm.append("")

    asm.append("; P0C1..P7C3 hardware palette table")
    asm.append("palettedata")
    for i, p in enumerate(PAL_CODES):
        asm.append("  .byte " + ",".join(f"${c:02X}" for c in p) + f" ; P{i}")
    asm.append("")

    asm.append("imglo .byte " + ",".join(f"<{s[0]}" for s in sprites))
    asm.append("imghi .byte " + ",".join(f">{s[0]}" for s in sprites))
    asm.append("imgw .byte " + ",".join(str(s[1]) for s in sprites))
    asm.append("imgstrips .byte " + ",".join(str(s[2]) for s in sprites))
    asm.append("imgframes .byte " + ",".join(str(s[3]) for s in sprites))
    asm.append("imgh .byte " + ",".join(str(s[4]) for s in sprites))
    asm.append("")

    first_tile_char = 2 * NFONT
    def tile_char(t):
        return first_tile_char + 2 * int(t)

    asm.append("stg_rowlo")
    asm.append("  .byte " + ",".join(f"<pbo{r}" for r in range(10)))
    asm.append("  .byte " + ",".join(f"<pbo{r}" for r in range(10, 20)))
    asm.append("stg_rowhi")
    asm.append("  .byte " + ",".join(f">pbo{r}" for r in range(10)))
    asm.append("  .byte " + ",".join(f">pbo{r}" for r in range(10, 20)))
    asm.append("")

    max_bg = 0
    for r in range(20):
        row = m[r]
        runs = row_runs([t_pals[int(t)] for t in row], [int(t) != 0 for t in row])
        packed, offsets = [], []
        for start, k, pal in runs:
            offsets.append(len(packed))
            packed.extend(tile_char(t) for t in row[start:start + k])
        if packed:
            asm.append(f"pbr{r} .byte " + ",".join(str(v) for v in packed))
        nbytes = 5 * len(runs)
        max_bg = max(max_bg, nbytes)
        asm.append(f"pbo{r} .byte {nbytes}")
        for (start, k, pal), off in zip(runs, offsets):
            asm.append(f"  .byte <(pbr{r}+{off}),$60,>(pbr{r}+{off}),{(pal << 5) | ((-k) & 31)},{start * 8}")

    (GEN / "data.asm").write_text("\n".join(asm) + "\n")
    print(f"--> Generated {len(t_slots)} tiles, {len(sprites)} sprites, 20 playfield rows (max bg {max_bg} bytes/row)!")


if __name__ == "__main__":
    main()
