#!/usr/bin/env python3
"""Generate 160A graphics, playfield tilemap, and assembly tables for Super Mega Pinball 7800.

Pure Python (zero external dependencies). Inspired by NES Pinball & Pinball Dreams,
using AtariGammaForce's 160A vertical scrolling engine.
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
    [0x04, 0x0A, 0x0F],  # P0: HUD Text, Chrome Rails, Islands & Divider Walls (Dark Gray, Silver, White)
    [0x24, 0x1A, 0x0F],  # P1: Gold Flippers, Plunger & Score Callouts (Bronze, Bright Gold, White)
    [0x32, 0x36, 0x1E],  # P2: Hot Neon Red / Crimson Pop Bumpers & Bottom Funnel (Dark Red, Red, Yellow)
    [0x84, 0x98, 0x9E],  # P3: Electric Cyan Channels, Upper Island & Rollover Dividers (Blue, Cyan, Ice White)
    [0x52, 0x58, 0x5E],  # P4: Neon Pink/Magenta Slingshots, Right Gate & Spinner (Violet, Magenta, Pink)
    [0xC2, 0xC8, 0xCE],  # P5: Emerald Green Center Cards, Upper Lock Chute & Plunger Track (Forest, Lime, Mint)
    [0x22, 0x28, 0x1E],  # P6: Orange/Gold Left Target Bank & Center Bumper Ring (Rust, Orange, Yellow)
    [0x94, 0x0C, 0x0F],  # P7: Chrome Steel Pinballs & Specular Glint (Steel Blue, Chrome Silver, White)
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
    h, w = len(grid), len(grid[0])
    assert w % 4 == 0, f"Width {w} must be a multiple of 4 for 2-bit PNG"
    raw = bytearray()
    for row in grid:
        raw.append(0)
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
#    Modeled after NES Pinball's two-tier playfield with side channels,
#    islands, upper & lower flippers, inlane/outlane dividers, and V-drain!
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

    # Tile 1: Left Outer Wall (col 1, X=8..15) - P0 Chrome
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][4] = 1
        t[y][5] = 2
        t[y][6] = 2
        t[y][7] = 3
    T_WALL_L = add_tile(t, 0)

    # Tile 2: Right Outer Wall (col 18, X=144..151) - P0 Chrome
    T_WALL_R = add_tile(mirror_h(t), 0)

    # Tile 3: Plunger Lane Divider Wall (col 16, X=128..135) - P0 Chrome
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][1] = 3
        t[y][2] = 2
        t[y][3] = 2
        t[y][4] = 1
    T_PLUNGE_DIV = add_tile(t, 0)

    # Tile 4: Plunger Shooter Lane Track (col 17, X=136..143) - P5 Emerald ticks
    t = empty_grid(16, 8)
    for y in range(0, 16, 4):
        for x in range(2, 6):
            t[y][x] = 1
    t[2][3] = t[2][4] = 2
    t[10][3] = t[10][4] = 2
    T_PLUNGE_TRK = add_tile(t, 5)

    # Tile 5: Top Arch Left Curve (P3 Electric Cyan)
    t = empty_grid(16, 8)
    for y in range(16):
        x0 = max(0, 6 - y // 2)
        for x in range(x0, min(8, x0 + 3)):
            t[y][x] = 3 if x == x0 else 2
    T_ARCH_L = add_tile(t, 3)

    # Tile 6: Top Arch Horizontal Roof (P3 Electric Cyan)
    t = empty_grid(16, 8)
    for x in range(8):
        t[2][x] = 3
        t[3][x] = 3
        t[4][x] = 2
        t[5][x] = 1
    T_ARCH_H = add_tile(t, 3)

    # Tile 7: Top Arch Right Curve (P3 Electric Cyan)
    T_ARCH_R = add_tile(mirror_h(tiles[T_ARCH_L]), 3)

    # Tile 8: Vertical Channel / Lane Divider Wall (P3 Electric Cyan)
    # Used for:
    #   - Upper-left orbit inner wall (col 3, separating col 2 orbit channel from main arena!)
    #   - Top rollover lane dividers (cols 5, 7, 9, 11)
    #   - Center target lane dividers
    #   - Lower inlane/outlane divider posts (col 3 and col 14!)
    t = empty_grid(16, 8)
    for y in range(1, 15):
        t[y][2] = 1
        t[y][3] = 3
        t[y][4] = 2
        t[y][5] = 1
    t[0][3] = t[0][4] = 3
    t[15][3] = t[15][4] = 2
    T_CHAN_WALL = add_tile(t, 3)

    # Tile 9: Solid Mid-Table Island Block (P3 Blue/Cyan, separates outer side channel from upper flippers!)
    t = empty_grid(16, 8)
    for y in range(16):
        for x in range(1, 7):
            t[y][x] = 2 if (y in (0, 15) or x in (1, 6)) else 1
        t[y][1] = 3
        t[y][6] = 3
    T_ISLAND = add_tile(t, 3)

    # Tile 10: Upper Flipper Anchor Shoulder Left (P3 Cyan/White, connects col 4 island to Upper Left Flipper at col 5!)
    t = empty_grid(16, 8)
    for y in range(12):
        lim = min(8, 2 + y // 2)
        for x in range(lim):
            t[y][x] = 2
        if lim < 8:
            t[y][lim] = 3
    T_UP_ANCHOR_L = add_tile(t, 3)

    # Tile 11: Upper Flipper Anchor Shoulder Right (P3 Cyan/White, connects col 13 island to Upper Right Flipper at col 12!)
    T_UP_ANCHOR_R = add_tile(mirror_h(t), 3)

    # Tile 12: Upper-Right Green Lock Chute Wall & Track (P5 Emerald Green, like NES Pinball's 500 chute!)
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][0] = 3
        t[y][1] = 2
        t[y][6] = 2
        t[y][7] = 3
        if (y % 4) < 2:
            t[y][3] = t[y][4] = 3
    T_LOCK_CHUTE = add_tile(t, 5)

    # Tile 13: Left Side Target Bank ("1..7" yellow/orange side targets on col 2) - P6
    t = empty_grid(16, 8)
    for y in range(16):
        t[y][0] = 1
        if (y % 4) != 3:
            t[y][1] = 2
            t[y][2] = 3
            t[y][3] = 3
    T_SIDE_TGTS_L = add_tile(t, 6)

    # Tile 14: Right Side Pink Gate / Chute (col 15) - P4 Neon Magenta
    t = empty_grid(16, 8)
    for y in range(0, 16, 3):
        for x in range(1, 7):
            t[y][x] = 3
            if y + 1 < 16:
                t[y + 1][x] = 2
    T_SIDE_GATE_R = add_tile(t, 4)

    # Tile 15: Left Slingshot Kicker Triangle (P4 Neon Magenta)
    t = empty_grid(16, 8)
    for y in range(2, 15):
        w = min(5, (y - 1) // 2 + 1)
        t[y][1] = 2
        for x in range(2, 1 + w):
            t[y][x] = 2
        t[y][1 + w] = 3
    T_SLING_L = add_tile(t, 4)

    # Tile 16: Right Slingshot Kicker Triangle (P4 Neon Magenta)
    T_SLING_R = add_tile(mirror_h(t), 4)

    # Tile 17: Left Inlane Chrome Rail (slopes down-right in cols 4..5 directly to Left Flipper at col 6!) - P0 Chrome
    t = empty_grid(16, 8)
    for y in range(16):
        x = y // 2
        t[y][x] = 2
        if x + 1 < 8:
            t[y][x + 1] = 3
        if x > 0:
            t[y][x - 1] = 1
    T_INLANE_L = add_tile(t, 0)

    # Tile 18: Right Inlane Chrome Rail (slopes down-left in cols 12..13 directly to Right Flipper at col 11!) - P0 Chrome
    T_INLANE_R = add_tile(mirror_h(t), 0)

    # Tile 19: Lower Flipper Anchor Left (col 5 at row 1, connects inlane rail solidly to Left Flipper pivot at X=48!) - P0 Chrome
    t = empty_grid(16, 8)
    for y in range(8):
        for x in range(y, 8):
            t[y][x] = 3 if x == 7 else 2
    T_LOW_ANCHOR_L = add_tile(t, 0)

    # Tile 20: Lower Flipper Anchor Right (col 12 at row 1, connects inlane rail solidly to Right Flipper pivot at X=95!) - P0 Chrome
    T_LOW_ANCHOR_R = add_tile(mirror_h(t), 0)

    # Tile 21: Bottom V-Funnel Drain Wall Left (slopes down-right toward center drain hole) - P2 Red/Gold
    t = empty_grid(16, 8)
    for y in range(16):
        lim = min(8, 1 + y // 2)
        for x in range(lim):
            t[y][x] = 1
        if lim < 8:
            t[y][lim] = 2
        if lim + 1 < 8:
            t[y][lim + 1] = 3
    T_APRON_L = add_tile(t, 2)

    # Tile 22: Bottom V-Funnel Drain Wall Right (slopes down-left toward center drain hole) - P2 Red/Gold
    T_APRON_R = add_tile(mirror_h(t), 2)

    # Tile 23: Center Table Star / Arrow Decal (P6 Orange/Yellow)
    t = empty_grid(16, 8)
    arrow = [
        "...33...",
        "..2332..",
        ".232232.",
        "231..132",
        "...22...",
        "...22...",
        "..1221..",
        "........",
    ]
    for y, r in enumerate(arrow):
        for x, c in enumerate(r):
            if c != ".":
                t[4 + y][x] = int(c)
    T_DEC_ARROW = add_tile(t, 6)

    names = {
        "EMPTY": 0,
        "WALL_L": T_WALL_L,
        "WALL_R": T_WALL_R,
        "PLUNGE_DIV": T_PLUNGE_DIV,
        "PLUNGE_TRK": T_PLUNGE_TRK,
        "ARCH_L": T_ARCH_L,
        "ARCH_H": T_ARCH_H,
        "ARCH_R": T_ARCH_R,
        "CHAN_WALL": T_CHAN_WALL,
        "ISLAND": T_ISLAND,
        "UP_ANCHOR_L": T_UP_ANCHOR_L,
        "UP_ANCHOR_R": T_UP_ANCHOR_R,
        "LOCK_CHUTE": T_LOCK_CHUTE,
        "SIDE_TGTS_L": T_SIDE_TGTS_L,
        "SIDE_GATE_R": T_SIDE_GATE_R,
        "SLING_L": T_SLING_L,
        "SLING_R": T_SLING_R,
        "INLANE_L": T_INLANE_L,
        "INLANE_R": T_INLANE_R,
        "LOW_ANCHOR_L": T_LOW_ANCHOR_L,
        "LOW_ANCHOR_R": T_LOW_ANCHOR_R,
        "APRON_L": T_APRON_L,
        "APRON_R": T_APRON_R,
        "DEC_ARROW": T_DEC_ARROW,
    }
    return tiles, pals, names


# ---------------------------------------------------------------------------
# 3. Build 20-Row x 20-Column Pinball Table Map (NES Pinball Inspired Layout!)
#    Row 19 = Top of Table (world_y = 0..15)
#    Row 0  = Bottom of Table (world_y = 304..319)
#    Playfield spans cols 2..15 (X = 16..127), symmetric around X = 72!
# ---------------------------------------------------------------------------
def build_pinball_map(T):
    m = [[0] * 20 for _ in range(20)]

    # Outer left wall (col 1) and right wall (col 18) on all rows 0..19
    for r in range(20):
        m[r][1] = T["WALL_L"]
        m[r][18] = T["WALL_R"]

    # Plunger divider wall (col 16) and shooter track (col 17) on rows 0..16
    for r in range(17):
        m[r][16] = T["PLUNGE_DIV"]
        m[r][17] = T["PLUNGE_TRK"]
    m[17][17] = T["PLUNGE_TRK"]

    # Row 19 (world_y = 0..15): Top Orbital Arch Roof
    m[19][2] = T["ARCH_L"]
    for c in range(3, 17):
        m[19][c] = T["ARCH_H"]
    m[19][17] = T["ARCH_R"]

    # Row 18 (world_y = 16..31): Upper Arch & Left Orbit Channel Entrance
    m[18][2] = T["ARCH_L"]
    m[18][4] = T["CHAN_WALL"]   # Separates Left Orbit Channel (cols 2..3) from Top Rollover Lanes!
    m[18][8] = T["DEC_ARROW"]
    m[18][13] = T["ARCH_R"]
    m[18][17] = T["ARCH_R"]

    # Row 17 (world_y = 32..47): Top Rollover Lanes (I - G - N) + Left Orbit Channel
    # Col 2..3 is the Upper-Left Orbit Channel; Cols 4, 7, 10, 13 are the 3 Rollover Lane dividers!
    m[17][4] = T["CHAN_WALL"]
    m[17][7] = T["CHAN_WALL"]
    m[17][10] = T["CHAN_WALL"]
    m[17][13] = T["CHAN_WALL"]

    # Rows 14..16 (world_y = 48..95):
    #   - Left Orbit Channel wall at col 3 (so col 2 is a dedicated narrow left orbit chute!)
    #   - Center-Upper Pop Bumper Arena (cols 5..11)
    #   - Upper-Right Green Multi-Ball Lock Chute at cols 13..14 (walled on left by col 12!)
    for r in (14, 15, 16):
        m[r][3] = T["CHAN_WALL"]
        m[r][12] = T["CHAN_WALL"]
        m[r][13] = T["LOCK_CHUTE"]
        m[r][14] = T["LOCK_CHUTE"]

    # Rows 12..13 (world_y = 96..127):
    #   - Left Side Bypass Channel (col 2, X=16..23) separated from main arena by Left Island (cols 3..4)!
    #   - Right Upper Island (cols 13..14) separating upper lock chute from lower arena!
    for r in (12, 13):
        m[r][3] = T["ISLAND"]
        m[r][4] = T["ISLAND"]
        m[r][8] = T["DEC_ARROW"]
        m[r][13] = T["ISLAND"]
        m[r][14] = T["ISLAND"]

    # Row 11 (world_y = 128..143): Upper Flippers Row!
    #   - Col 2: Left Side Bypass Channel (continues down!)
    #   - Col 3: Left Island, Col 4: Upper Flipper Anchor Left -> connects to Upper Left Flipper at cols 5..6 (X=40..55)!
    #   - Col 13: Upper Flipper Anchor Right -> connects to Upper Right Flipper at cols 11..12 (X=88..103)!
    #   - Col 14: Right Island
    m[11][3] = T["ISLAND"]
    m[11][4] = T["UP_ANCHOR_L"]
    m[11][13] = T["UP_ANCHOR_R"]
    m[11][14] = T["ISLAND"]

    # Row 10 (world_y = 144..159): Below Upper Flippers, Left Side Channel still walled by col 3!
    m[10][3] = T["ISLAND"]
    m[10][14] = T["ISLAND"]

    # Row 9 (world_y = 160..175): 4 Center Green Targets (I - G - N - T) sit here across cols 5..11
    m[9][3] = T["CHAN_WALL"]
    m[9][14] = T["CHAN_WALL"]

    # Row 8 (world_y = 176..191): Vertical Lane Dividers below the 4 Center Targets + Left Side Target Bank
    m[8][2] = T["SIDE_TGTS_L"]
    for c in (5, 7, 9, 11):
        m[8][c] = T["CHAN_WALL"]
    m[8][15] = T["SIDE_GATE_R"]

    # Rows 6..7 (world_y = 192..223): Lower 3 Pop Bumpers Arena + Left Target Bank (col 2) + Right Pink Gate (col 15)
    for r in (6, 7):
        m[r][2] = T["SIDE_TGTS_L"]
        m[r][15] = T["SIDE_GATE_R"]
    m[7][8] = T["DEC_ARROW"]

    # Rows 3..5 (world_y = 224..271): Walled Side Channels (Outlanes & Inlanes) + Slingshot Kickers!
    #   - Col 2 (X=16..23): Left Outlane Drain Channel!
    #   - Col 3 (X=24..31): Solid Inlane/Outlane Divider Wall!
    #   - Col 4 (X=32..39): Left Inlane Channel!
    #   - Col 5 (X=40..47): Left Slingshot Kicker Triangle!
    #   - Col 12 (X=96..103): Right Slingshot Kicker Triangle!
    #   - Col 13 (X=104..111): Right Inlane Channel!
    #   - Col 14 (X=112..119): Solid Inlane/Outlane Divider Wall!
    #   - Col 15 (X=120..127): Right Outlane Drain Channel!
    for r in (4, 5):
        m[r][3] = T["CHAN_WALL"]
        m[r][5] = T["SLING_L"]
        m[r][12] = T["SLING_R"]
        m[r][14] = T["CHAN_WALL"]

    # Row 3 (world_y = 256..271): Inlanes begin curving inward toward Lower Flippers; Outlanes stay outside!
    m[3][3] = T["CHAN_WALL"]
    m[3][4] = T["INLANE_L"]
    m[3][13] = T["INLANE_R"]
    m[3][14] = T["CHAN_WALL"]

    # Row 2 (world_y = 272..287): Inlane Rails feed directly into Lower Flipper Anchors at cols 5 and 12!
    m[2][2] = T["APRON_L"]
    m[2][4] = T["INLANE_L"]
    m[2][5] = T["INLANE_L"]
    m[2][12] = T["INLANE_R"]
    m[2][13] = T["INLANE_R"]
    m[2][15] = T["APRON_R"]

    # Row 1 (world_y = 288..303): Lower Flipper Row!
    #   - Cols 2..4: Left Bottom V-Funnel Wall
    #   - Col 5 (X=40..47): Lower Flipper Anchor Left -> touches Left Flipper at X=48..63 (cols 6..7)!
    #   - Cols 8..9 (X=64..79): 16-pixel Center Drain Gap between the flippers!
    #   - Col 12 (X=96..103): Lower Flipper Anchor Right -> touches Right Flipper at X=80..95 (cols 10..11)!
    #   - Cols 13..15: Right Bottom V-Funnel Wall
    m[1][2] = T["APRON_L"]
    m[1][3] = T["APRON_L"]
    m[1][4] = T["APRON_L"]
    m[1][5] = T["LOW_ANCHOR_L"]
    m[1][12] = T["LOW_ANCHOR_R"]
    m[1][13] = T["APRON_R"]
    m[1][14] = T["APRON_R"]
    m[1][15] = T["APRON_R"]

    # Row 0 (world_y = 304..319): Bottom V-Funnel Drain Hole (Open at cols 7..10, X=56..87)
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

    # 2. Left Flipper (16x12 in 160A = 32x12 TV pixels, 4 bytes = 16 pixels wide!
    #    Spans full 16 pixels from pivot X=0 to tip X=15 so Left & Right flippers
    #    anchor flush against cols 5 and 12 with ZERO floating gap!) - P1
    flipl_down = art_to_grid([
        "................",
        "................",
        "3333............",
        "233322..........",
        "12233322........",
        ".112233322......",
        "...112233322....",
        ".....11223332...",
        ".......1122332..",
        ".........112232.",
        "...........1122.",
        "................",
    ])
    flipl_mid = art_to_grid([
        "................",
        "................",
        "................",
        "................",
        "33333333333332..",
        "233322222222232.",
        "122211111111112.",
        "................",
        "................",
        "................",
        "................",
        "................",
    ])
    flipl_up = art_to_grid([
        "...........1122.",
        ".........112232.",
        ".......1122332..",
        ".....11223332...",
        "...112233322....",
        ".112233322......",
        "12233322........",
        "233322..........",
        "3333............",
        "................",
        "................",
        "................",
    ])
    add_sprite("flipl", [flipl_down, flipl_mid, flipl_up], 1, used_h=11)

    # 3. Right Flipper (16x12 in 160A, 4 bytes = 16 pixels wide, mirrored so right pivot is at X+15!) - P1
    add_sprite("flipr", [mirror_h(f) for f in (flipl_down, flipl_mid, flipl_up)], 1, used_h=11)

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

    # 5. Center Card / Rollover / Lock Gem (8x8 in 160A, 2 bytes wide, 2 frames: Up Card, Lit/Down) - P5
    gem_0 = art_to_grid([
        ".222222.",
        "23333332",
        "23133132",
        "23113132",
        "23131132",
        "23333332",
        "12222221",
        ".111111.",
    ])
    gem_1 = art_to_grid([
        "........",
        "..2222..",
        ".233332.",
        ".231132.",
        ".233332.",
        "..2222..",
        "........",
        "........",
    ])
    add_sprite("gem", [gem_0, gem_1], 5, used_h=8)

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
    save_160a(GFX / "padblock.png", empty_grid(16, 4), 0)
    bas.append("  newblock")
    bas.append("  incgraphic gfx/padblock.png 160A 0 1 2 3")
    (GEN / "gfx.bas").write_text("\n".join(bas) + "\n")

    screen_texts = {
        "title1": "SUPER MEGA PINBALL",
        "title2": "IGNITION  7800",
        "press": "PULL DOWN TO LAUNCH",
        "multiball": "MULTI-BALL MANIA!",
        "jackpot": "LOCK LIT! SHOOT TOP",
        "lock1": "BALL 1 LOCKED!",
        "lock2": "READY MULTI-BALL!",
        "ramp": "ORBIT LOOP 10000!",
        "skill": "SKILL BONUS 5000!",
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
