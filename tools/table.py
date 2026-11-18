#!/usr/bin/env python3
"""The table: one description of the playfield that becomes

  * its picture, as MARIA display-list objects (160A, direct mode) and the
    graphics they read, packed into 4K blocks (gen/bg.bin, gen/rows.asm)
  * its walls, posts and bumpers as colliders for the CORDIC physics, with a
    grid so a ball only tests what is near it (gen/colliders.asm)
  * its switches (rollovers, ramps, spinner, the lock) as sensor boxes
  * its lamps: inserts drawn as objects of their own whose palette the game
    flips between an unlit and a lit one (gen/rows.asm, the lamp lists)
  * a preview, build/table.png (and build/table_geo.png with the colliders)

Coordinates are "units": x 0..319 across (one unit = half a 160A pixel,
so units are square on the screen), y 0..479 down (one unit = one line).
The physics works in 1/16 units.

Pure Python, no dependencies.
"""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "src" / "gen"
BUILD = ROOT / "build"

ROWS = 30
H = ROWS * 16            # 480 lines
WU = 320                 # units across
PXW = 160                # 160A pixels across
NTSC = json.load(open(ROOT / "tools" / "a7800_ntsc_palette.json"))["rgb"]

# ---------------------------------------------------------------------------
# Palettes. BG is the floor: everything not drawn is floor and costs no DMA.
# P7 is the playfield's; the HUD gets its own P7 (swapped by a DLI).
BG = 0x60
PALS = [
    [0x04, 0x0A, 0x0F],   # P0 chrome: dark, steel, white (rails, guides, ball)
    [0x52, 0x56, 0x5C],   # P1 neon magenta (outer walls, slingshots)
    [0x92, 0x98, 0x9E],   # P2 neon cyan (ramp, inner guides, unlit blue lamps)
    [0x62, 0x66, 0x6A],   # P3 floor art violet
    [0x32, 0x36, 0x0E],   # P4 red: lamps unlit, flipper rubber + white body
    [0x28, 0x1C, 0x0F],   # P5 LIT: orange, yellow, white (every lit lamp)
    [0xC2, 0xC6, 0xCC],   # P6 green (drop targets, lock)
    [0x14, 0x18, 0x1E],   # P7 gold (bumpers, apron)
]
HUD_P7 = [0x20, 0x26, 0x2E]   # DMD orange for the score display


def rgb(code):
    return tuple(NTSC[code])


# ---------------------------------------------------------------------------
# The canvas: per 160A pixel, (palette, shade 1-3, lamp id or -1) or None.
class Canvas:
    def __init__(self):
        self.px = [[None] * PXW for _ in range(H)]

    def put(self, x, y, pal, shade, lamp=-1):
        if 0 <= x < PXW and 0 <= y < H:
            self.px[y][x] = (pal, shade, lamp)

    def clear(self, x, y):
        if 0 <= x < PXW and 0 <= y < H:
            self.px[y][x] = None

    def paint(self, bbox, fn):
        """fn(ux, uy) -> (pal, shade[, lamp]) | None | 'clear', sampled at pixel centers."""
        x0, y0, x1, y1 = bbox
        for py in range(max(0, int(y0) - 1), min(H, int(y1) + 2)):
            uy = py + 0.5
            for px in range(max(0, int(x0 / 2) - 1), min(PXW, int(x1 / 2) + 2)):
                ux = px * 2 + 1.0
                v = fn(ux, uy)
                if v is None:
                    continue
                if v == "clear":
                    self.clear(px, py)
                else:
                    self.put(px, py, *v)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy), t


def poly_bbox(pts, pad=0):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)


def inside_poly(x, y, pts):
    c = False
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if x < xi:
                c = not c
    return c


def ellipse_pts(cx, cy, rx, ry, a0, a1, n):
    """Points along an ellipse, angles in degrees (0 = right, 90 = down)."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return out


# ---------------------------------------------------------------------------
# Physics description
LAYER_PF = 1
LAYER_RAMP = 2

K_SEG, K_CAPS, K_CIRC = 0, 1, 2
F_KICK = 0x04         # bumper / slingshot: adds a kick
F_RUBBER = 0x08       # livelier bounce


class Table:
    def __init__(self):
        self.colliders = []    # dicts
        self.sensors = []      # dicts
        self.lamps = {}        # name -> id
        self.events = {}       # name -> id
        self.flippers = []
        self.consts = {}

    def event(self, name):
        if name not in self.events:
            self.events[name] = len(self.events) + 1
        return self.events[name]

    def lamp(self, name):
        if name not in self.lamps:
            self.lamps[name] = len(self.lamps)
        return self.lamps[name]

    # one-sided walls along a polyline; `front` is a point on the side the
    # ball lives on (the side is checked on the first segment, the rest
    # follow the polyline's turning direction)
    def wall(self, pts, front, layers=LAYER_PF, flags=0, event=None, drop=0, e=0.45):
        ax, ay = pts[0]
        bx, by = pts[1]
        # cross product sign: which side of A->B is `front`
        cr = (bx - ax) * (front[1] - ay) - (by - ay) * (front[0] - ax)
        # front must be on the side where YR < 0 after turning A->B to +x:
        # YR = -sin(t) dx + cos(t) dy, which is cross(d, p) / |d|; so cross < 0.
        if cr > 0:
            pts = list(reversed(pts))
        for i in range(len(pts) - 1):
            self.colliders.append(dict(kind=K_SEG, a=pts[i], b=pts[i + 1], r=0, layers=layers,
                                       flags=flags, event=event or 0, drop=drop, e=e))

    def capsule(self, pts, r, layers=LAYER_PF, flags=0, event=None, e=0.45):
        for i in range(len(pts) - 1):
            self.colliders.append(dict(kind=K_CAPS, a=pts[i], b=pts[i + 1], r=r, layers=layers,
                                       flags=flags, event=event or 0, drop=0, e=e))

    def circle(self, c, r, layers=LAYER_PF, flags=0, event=None, e=0.5):
        self.colliders.append(dict(kind=K_CIRC, a=c, b=c, r=r, layers=layers, flags=flags,
                                   event=event or 0, drop=0, e=e))

    def sensor(self, name, box, layers=LAYER_PF, cond=0, setlayer=0):
        """box in units; cond: 0 any, 1 moving up, 2 moving down."""
        self.sensors.append(dict(name=name, event=self.event(name), box=box, layers=layers,
                                 cond=cond, setlayer=setlayer))


T = Table()
C = Canvas()

# ---------------------------------------------------------------------------
# Geometry (units)
ARCH = (160, 112, 152, 104)          # the outer arch: center, radii
BALL_R = 6

# Outer boundary: left wall, arch, shooter lane outer wall
arch = ellipse_pts(160, 112, 152, 104, 180, 360, 28)       # left -> top -> right
T.wall([(8, 300), (8, 112)] + arch[1:] + [(312, 470)], front=(160, 200))
# floor of the shooter lane is the plunger (handled by the game)

# shooter lane inner wall
T.capsule([(288, 146), (288, 478)], 3)
# one-way gate at the top of the shooter lane: deflects balls coming down
# the right side into the return lane; lets a plunged ball through
T.wall([(312, 120), (290, 142)], front=(296, 120), layers=LAYER_PF, e=0.3)

# left orbit / ramp wall (both layers: orbit inner wall, ramp's walls)
T.capsule([(40, 300), (40, 112)], 3, layers=LAYER_PF | LAYER_RAMP)
# inner arch guide (left), playfield only
inner_l = ellipse_pts(160, 112, 120, 72, 180, 238, 8)
T.capsule(inner_l, 3)
# gate at the top-left: balls coming around the top from the right bounce back
# (it runs from the arch down to the guide's top end, sloping down to the
# right, so a slow ball on it rolls off toward the lanes instead of
# settling in a pocket)
GATE_L = [(78, 24), (96, 50)]
T.wall(GATE_L, front=(110, 30), e=0.3)

# ramp lane right wall (both layers up to the ramp's turn, then playfield)
T.capsule([(80, 266), (80, 112)], 3, layers=LAYER_PF | LAYER_RAMP)
T.capsule([(80, 112), (80, 62)], 3, layers=LAYER_PF)
# the ramp: the turn (layer 2) and the way down over the orbit
ramp_turn = ellipse_pts(44, 112, 36, 46, 0, -180, 12)
T.capsule(ramp_turn, 2, layers=LAYER_RAMP)
RAMP_EXIT = [(8, 112), (9, 284), (16, 310), (27, 330), (34, 346), (36, 358)]
T.capsule(RAMP_EXIT, 2, layers=LAYER_RAMP)

# return lane (right orbit) inner wall + inner arch guide (right)
inner_r = ellipse_pts(160, 112, 102, 72, 0, -58, 8)
T.capsule(list(reversed(inner_r)) + [(262, 328), (239, 335)], 3)

# left inlane outer wall
T.wall([(8, 300), (34, 342), (34, 392), (88, 422)], front=(60, 360))
# right inlane outer wall (the shooter wall's capsule is its upper part)
T.wall([(285, 330), (264, 384), (208, 422)], front=(240, 380))

# slingshots: kicker faces (one-sided, kick), backs (plain)
SL = [(58, 336), (58, 378), (84, 398)]
SR = [(238, 336), (238, 378), (212, 398)]
T.wall([SL[0], SL[2]], front=(100, 340), flags=F_KICK, event=T.event("sling"), e=0.6)
T.wall([SL[0], SL[1], SL[2]], front=(40, 400))
T.wall([SR[0], SR[2]], front=(200, 340), flags=F_KICK, event=T.event("sling"), e=0.6)
T.wall([SR[0], SR[1], SR[2]], front=(256, 400))
for p in SL + SR:
    T.circle(p, 2, flags=F_RUBBER)

# top lanes (M E G A): five guides
LANE_X = [96, 128, 160, 192, 224]
for x in LANE_X:
    T.capsule([(x, 58), (x, 92)], 3, flags=F_RUBBER)

# pop bumpers
BUMPERS = [(128, 134), (192, 134), (160, 176)]
BUMPER_R = 13
for i, c in enumerate(BUMPERS):
    T.circle(c, BUMPER_R, flags=F_KICK, event=T.event("bumper"), e=0.5)

# drop targets (one-sided, facing down), each its own drop id
DROPS = [(124, 144), (150, 170), (176, 196)]
DROP_Y = 232
for i, (x0, x1) in enumerate(DROPS):
    T.wall([(x0, DROP_Y), (x1, DROP_Y)], front=((x0 + x1) / 2, DROP_Y + 20),
           event=T.event(f"drop{i}"), drop=i + 1, e=0.35)
    # the back face: a standing target is solid from behind too (no event)
    T.wall([(x0, DROP_Y - 6), (x1, DROP_Y - 6)], front=((x0 + x1) / 2, DROP_Y - 30),
           drop=i + 1, e=0.35)

# over the bank, a sloped roof (one way: balls from above roll off to the
# right; balls from below pass up through it when the targets are down)
DROP_ROOF = [(116, DROP_Y - 2), (120, DROP_Y - 18), (200, DROP_Y - 7), (204, DROP_Y - 2)]
T.wall(DROP_ROOF, front=(100, DROP_Y - 12), e=0.3)

# standup targets on the return lane wall (S T A R)
STANDUPS = [(250, 266), (274, 290), (298, 322)]
for i, (y0, y1) in enumerate(STANDUPS):
    T.wall([(258, y0), (258, y1)], front=(220, (y0 + y1) / 2), event=T.event(f"stand{i}"), e=0.35)

# lock hole (the BLACK HOLE)
LOCK = (234, 204)
T.consts["LOCK_X"] = LOCK[0]
T.consts["LOCK_Y"] = LOCK[1]

# flippers: pivot, length, radius
FLIP_L = (92, 428)
FLIP_R = (204, 428)
FLIP_LEN = 44
FLIP_RAD = 4.5
FLIP_REST = 28.0       # degrees below horizontal
FLIP_UP = -30.0

# sensors
T.sensor("lane0", (100, 60, 124, 90))
T.sensor("lane1", (132, 60, 156, 90))
T.sensor("lane2", (164, 60, 188, 90))
T.sensor("lane3", (196, 60, 220, 90))
T.sensor("ramp_in", (44, 250, 78, 270), cond=1, setlayer=LAYER_RAMP)
T.sensor("ramp_back", (44, 252, 78, 272), layers=LAYER_RAMP, cond=2, setlayer=LAYER_PF)
T.sensor("ramp_top", (10, 66, 78, 96), layers=LAYER_RAMP)
T.sensor("ramp_out", (30, 340, 62, 362), layers=LAYER_RAMP, setlayer=LAYER_PF)
T.sensor("spinner", (10, 196, 38, 214))
T.sensor("orbit_l", (10, 120, 38, 140), cond=1)
T.sensor("orbit_r", (264, 180, 286, 200), cond=2)
T.sensor("lock", (LOCK[0] - 7, LOCK[1] - 7, LOCK[0] + 7, LOCK[1] + 7))
T.sensor("inlane_l", (36, 350, 56, 366))
T.sensor("inlane_r", (240, 352, 262, 368))
T.sensor("skill", (290, 100, 312, 116), cond=1)

# ---------------------------------------------------------------------------
# Art helpers
def tube(pts, r, pal, lamp=-1, hi=0.35, mid=0.75):
    """A beveled rail along a polyline: bright core, darker edges."""
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        bb = poly_bbox([a, b], r + 2)

        def f(x, y, a=a, b=b):
            d, _ = seg_dist(x, y, a[0], a[1], b[0], b[1])
            if d > r:
                return None
            s = 3 if d < r * hi else (2 if d < r * mid else 1)
            return (pal, s, lamp)
        C.paint(bb, f)


def disc(c, r, fn):
    C.paint((c[0] - r, c[1] - r, c[0] + r, c[1] + r),
            lambda x, y: fn(x - c[0], y - c[1], math.hypot(x - c[0], y - c[1])) if math.hypot(x - c[0], y - c[1]) <= r else None)


def poly(pts, fn):
    C.paint(poly_bbox(pts), lambda x, y: fn(x, y) if inside_poly(x, y, pts) else None)


# A tiny 3x5 font for playfield lettering (drawn at 2 lines per row)
FONT35 = {
    "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
    "C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"], "G": ["011", "100", "101", "101", "011"],
    "H": ["101", "101", "111", "101", "101"], "I": ["111", "010", "010", "010", "111"],
    "K": ["101", "110", "100", "110", "101"], "L": ["100", "100", "100", "100", "111"],
    "M": ["101", "111", "111", "101", "101"], "N": ["110", "101", "101", "101", "101"],
    "O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
    "R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"],
    "T": ["111", "010", "010", "010", "010"], "U": ["101", "101", "101", "101", "111"],
    "W": ["101", "101", "111", "111", "101"], "X": ["101", "101", "010", "101", "101"],
    "Y": ["101", "101", "010", "010", "010"], "J": ["001", "001", "001", "101", "010"],
    "2": ["110", "001", "010", "100", "111"], "3": ["110", "001", "010", "001", "110"],
    "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "110", "001", "110"],
    "6": ["011", "100", "110", "101", "010"], "0": ["010", "101", "101", "101", "010"],
    "1": ["010", "110", "010", "010", "111"], "F": ["111", "100", "110", "100", "100"],
    "V": ["101", "101", "101", "101", "010"], "!": ["010", "010", "010", "000", "010"],
    " ": ["000"] * 5,
}


def text(s, cx, y, pal, shade=3, lamp=-1, sy=2, shadow=None):
    """Center a string at unit x cx, top y; each glyph 3 px wide + 1 gap."""
    w = len(s) * 4 - 1
    x0 = int(round(cx / 2 - w / 2))
    for i, ch in enumerate(s):
        g = FONT35[ch]
        for r in range(5):
            for c in range(3):
                if g[r][c] == "1":
                    for k in range(sy):
                        if shadow is not None:
                            C.put(x0 + i * 4 + c + 1, y + r * sy + k + 1, *shadow)
                        C.put(x0 + i * 4 + c, y + r * sy + k, pal, shade, lamp)


def arrow(tip, direction, length, width, pal, lamp, shade_fn=None):
    """An insert arrow: triangle pointing along `direction` (degrees)."""
    a = math.radians(direction)
    ux, uy = math.cos(a), math.sin(a)
    vx, vy = -uy, ux
    base = (tip[0] - ux * length, tip[1] - uy * length)
    pts = [tip, (base[0] + vx * width, base[1] + vy * width), (base[0] - vx * width, base[1] - vy * width)]

    def f(x, y):
        # shade by distance along the arrow: bright tip
        t = ((x - base[0]) * ux + (y - base[1]) * uy) / length
        edge = min(abs((x - tip[0]) * vx + (y - tip[1]) * vy), 99)
        s = 3 if t > 0.62 else 2
        if t < 0.18:
            s = 1
        return (pal, s, lamp)
    poly(pts, f)


def round_insert(c, r, pal, lamp):
    disc(c, r, lambda dx, dy, d: (pal, 3 if d < r * 0.4 else (2 if d < r * 0.8 else 1), lamp))


# ---------------------------------------------------------------------------
# Paint the table. Order: floor art first, then structures, then inserts.
def draw():
    # -- outside the table: dark cabinet (P0 shade 1)
    def outside(x, y):
        ex = (x - ARCH[0]) / (ARCH[2] + 8)
        ey = (y - ARCH[1]) / (ARCH[3] + 8)
        if y < ARCH[1] and ex * ex + ey * ey > 1:
            return (0, 1)
        if x < 2 or x > 318:
            return (0, 1)
        return None
    C.paint((0, 0, 320, H), outside)

    # -- floor art: a perspective grid fading in towards the flippers,
    #    sun rays behind the bumpers, a starfield
    def grid(x, y):
        if y < 250 or y > 470:
            return None
        # horizontal lines getting closer towards the top
        t = (y - 250) / 220.0
        k = (t ** 0.6) * 9
        if abs(k - round(k)) < 0.05 + 0.04 * t:
            return (3, 1)
        # rays converging to (148, 210)
        ang = math.atan2(y - 210, x - 148)
        a = math.degrees(ang)
        if 30 < a < 150 and abs((a - 90) / 15.0 - round((a - 90) / 15.0)) < 0.05:
            return (3, 1)
        return None
    C.paint((10, 250, 286, 470), grid)

    # sunburst behind the bumpers
    def sun(x, y):
        dx, dy = x - 160, y - 150
        d = math.hypot(dx, dy)
        if d > 74 or d < 20:
            return None
        a = math.degrees(math.atan2(dy, dx))
        if abs(a / 22.5 - round(a / 22.5)) < 0.16:
            return (3, 2 if d < 50 else 1)
        return None
    C.paint((80, 70, 240, 230), sun)

    # stars
    import random
    rnd = random.Random(7)
    for _ in range(40):
        x = rnd.randrange(6, 154)
        y = rnd.randrange(10, 470)
        C.put(x, y, 3, rnd.choice((2, 3, 3)))

    # big logo plate in the middle: "SUPER MEGA" over "PINBALL"
    plate = [(100, 270), (196, 270), (204, 300), (196, 330), (100, 330), (92, 300)]
    poly(plate, lambda x, y: (3, 1))
    tube(plate + [plate[0]], 2, 1)
    text("SUPER", 148, 276, 5, 2, shadow=(1, 1, -1))
    text("MEGA", 148, 290, 5, 3, shadow=(1, 1, -1))
    text("PINBALL", 148, 308, 2, 3, sy=3, shadow=(2, 1, -1))

    # -- apron: below the inlanes, gold with dark trim
    apron_l = [(0, 300), (8, 300), (34, 342), (34, 392), (88, 422), (92, 440), (100, 480), (0, 480)]
    apron_r = [(320, 480), (196, 480), (204, 440), (208, 422), (264, 384), (285, 330), (285, 480)]
    for ap in (apron_l, apron_r):
        poly(ap, lambda x, y: (0, 2 if int(y) % 16 == 0 else 1))
    # shooter lane floor
    poly([(291, 140), (312, 140), (312, 480), (291, 480)], lambda x, y: (0, 1) if int(y) % 6 < 3 else None)

    # -- walls
    tube([(6, 300), (6, 112)], 3, 1)
    tube(ellipse_pts(160, 112, 154, 106, 180, 360, 40), 3, 1)
    tube([(314, 112), (314, 480)], 3, 1)
    tube([(288, 146), (288, 480)], 3, 0)
    tube([(40, 300), (40, 112)], 3, 2)
    tube(inner_l, 3, 2)
    tube([(80, 266), (80, 62)], 3, 2)
    tube(list(reversed(inner_r)) + [(262, 328), (239, 335)], 3, 2)
    tube([(8, 300), (34, 342), (34, 392), (88, 422)], 2, 0)
    tube([(285, 330), (264, 384), (208, 422)], 2, 0)
    # gates
    tube([(312, 120), (290, 142)], 1.5, 0)
    tube(GATE_L, 1.5, 0)

    # -- slingshots: plastic triangle + rubber band on the kicker face
    for s in (SL, SR):
        poly(s, lambda x, y: (1, 1))
        tube([s[0], s[2]], 2.5, 1)
        tube([s[0], s[1], s[2]], 1.5, 1, hi=0.0, mid=0.9)

    # -- top lanes: guides and lamps
    for x in LANE_X:
        tube([(x, 58), (x, 92)], 3, 0)
    for i, ch in enumerate("MEGA"):
        cx = 112 + 32 * i
        L = T.lamp(f"lane{i}")
        round_insert((cx, 74), 7, 4, L)
        text(ch, cx, 100, 0, 2)

    # -- bumpers: gold body ring, cap is a lamp
    for i, c in enumerate(BUMPERS):
        disc(c, BUMPER_R + 1, lambda dx, dy, d: (7, 1 if d > BUMPER_R - 1 else 2))
        L = T.lamp(f"bumper{i}")
        disc(c, BUMPER_R - 4, lambda dx, dy, d, L=L: (2, 3 if (dx + dy) < -3 else (2 if d < 6 else 1), L))

    # -- ramp (wireform): two rails and ties, drawn over everything
    ramp_l = [(40, 266), (40, 112)]
    ramp_rt = ellipse_pts(44, 112, 36, 46, 0, -180, 24)
    for rail in ([(43, 266), (43, 112)], [(77, 266), (77, 112)]):
        tube(rail, 1.6, 2)
    tube(ellipse_pts(44, 112, 37, 47, 0, -180, 30), 1.6, 2)
    tube(ellipse_pts(44, 112, 3, 3, 0, -180, 6), 1.6, 2)
    tube([(x + 2, y) for x, y in RAMP_EXIT], 1.6, 2)
    tube([(37, 112), (37, 290)], 1.6, 2)
    for y in range(120, 266, 12):
        tube([(43, y), (77, y)], 0.8, 0)
    for y in range(124, 290, 12):
        tube([(11, y), (37, y)], 0.8, 0)
    # ramp entrance arrow
    arrow((60, 236), -90, 22, 9, 4, T.lamp("ramp_arrow"))
    text("RAMP", 60, 274, 2, 2)

    # -- left orbit arrow & spinner plate
    arrow((24, 160), -90, 18, 8, 4, T.lamp("orbit_arrow"))
    poly([(12, 200), (36, 200), (36, 210), (12, 210)], lambda x, y: (0, 2 if int(y) % 3 else 3))

    # -- drop targets (each a lamp object: hidden when dropped). The game
    # indexes LAMP_DROP0+n and LAMP_DROPLIT0+n, so each group's ids must run
    # in order: register them before drawing.
    for i in range(len(DROPS)):
        T.lamp(f"drop{i}")
    for i in range(len(DROPS)):
        T.lamp(f"droplit{i}")
    for i, (x0, x1) in enumerate(DROPS):
        L = T.lamp(f"drop{i}")
        poly([(x0, DROP_Y - 6), (x1, DROP_Y - 6), (x1, DROP_Y + 2), (x0, DROP_Y + 2)],
             lambda x, y, L=L: (6, 3 if y < DROP_Y - 3 else 2, L))
        # their indicator lamps below
        round_insert(((x0 + x1) / 2, DROP_Y + 14), 4, 4, T.lamp(f"droplit{i}"))

    tube(DROP_ROOF, 1.6, 0)

    # -- standup targets
    for i, (y0, y1) in enumerate(STANDUPS):
        L = T.lamp(f"stand{i}")
        poly([(252, y0 + 2), (258, y0 + 2), (258, y1 - 2), (252, y1 - 2)], lambda x, y, L=L: (4, 2, L))

    # -- the lock hole: a dark well with a lit ring
    disc(LOCK, 14, lambda dx, dy, d: (6, 1) if d > 10 else None)
    disc(LOCK, 10, lambda dx, dy, d: (0, 1) if d > 6 else None)
    arrow((LOCK[0] - 6, LOCK[1] + 18), -60, 16, 7, 4, T.lamp("lock_arrow"))
    text("LOCK", LOCK[0] - 2, LOCK[1] + 40, 6, 3)

    # -- bonus multiplier lamps across the middle
    for i, s in enumerate(("2X", "3X", "4X", "5X")):
        cx = 112 + i * 24
        L = T.lamp(f"bonus{i}")
        round_insert((cx, 352), 9, 4, L)
        text(s, cx, 348, 4, 3, lamp=L)

    # -- shoot again
    L = T.lamp("shoot_again")
    round_insert((148, 462), 8, 4, L)
    # inlane lamps
    round_insert((46, 372), 5, 4, T.lamp("inlane_l"))
    round_insert((250, 376), 5, 4, T.lamp("inlane_r"))


draw()


# ---------------------------------------------------------------------------
# Convert the canvas into rows of MARIA objects.
def nearest_shade(color_rgb, pal):
    best, bd = 0, 1e9
    cand = [(0, rgb(BG))] + [(i + 1, rgb(PALS[pal][i])) for i in range(3)]
    for s, c in cand:
        d = sum((a - b) ** 2 for a, b in zip(color_rgb, c))
        if d < bd:
            best, bd = s, d
    return best


MERGE_GAP = 4
EMPTY = [[0] * 4 for _ in range(16)]


def build_rows():
    rows = []
    stats = []
    for r in range(ROWS):
        cells = []   # per byte column: list of (key, 16x4 pixels shades)
        for col in range(40):
            counts = {}
            for y in range(16):
                for x in range(4):
                    v = C.px[r * 16 + y][col * 4 + x]
                    if v is None:
                        continue
                    key = (v[0], v[2])
                    counts[key] = counts.get(key, 0) + (1000 if v[2] >= 0 else 1)
            keys = sorted(counts, key=lambda k: -counts[k])[:2]
            layers = {}
            for k in keys:
                layers[k] = [[0] * 4 for _ in range(16)]
            for y in range(16):
                for x in range(4):
                    v = C.px[r * 16 + y][col * 4 + x]
                    if v is None:
                        continue
                    key = (v[0], v[2])
                    if key in layers:
                        layers[key][y][x] = v[1]
                    else:
                        # remap into a kept key: closest color
                        c = rgb(PALS[v[0]][v[1] - 1])
                        best = None
                        for k in keys:
                            if k[1] >= 0:
                                continue
                            s = nearest_shade(c, k[0])
                            d = 0 if s == 0 else sum((a - b) ** 2 for a, b in zip(c, rgb(PALS[k[0]][s - 1])))
                            if best is None or d < best[0]:
                                best = (d, k, s)
                        if best and best[2]:
                            layers[best[1]][y][x] = best[2]
            cells.append(layers)
        # objects: runs of the same key across columns, at most 31 wide
        objs = []
        runs = []
        keys_all = set()
        for col in range(40):
            keys_all |= set(cells[col].keys())
        for k in keys_all:
            cols_k = [c for c in range(40) if k in cells[c]]
            # runs, bridging gaps of up to MERGE_GAP empty columns (a header
            # costs MARIA more than a few transparent bytes)
            start = prev = cols_k[0]
            for c in cols_k[1:] + [None]:
                if c is not None and c - prev <= MERGE_GAP + 1 and c - start < 31:
                    prev = c
                    continue
                runs.append((k, start, prev + 1))
                if c is not None:
                    start = prev = c
        runs.sort(key=lambda t: (t[0][1] >= 0, t[1]))   # plain art first, lamps after
        for (pal, lamp), c0, c1 in runs:
            w = c1 - c0
            data = []
            for y in range(16):
                line = []
                for col in range(c0, c1):
                    px = cells[col].get((pal, lamp), EMPTY)[y]
                    b = (px[0] << 6) | (px[1] << 4) | (px[2] << 2) | px[3]
                    line.append(b)
                data.append(bytes(line))
            objs.append(dict(pal=pal, lamp=lamp, col=c0, w=w, data=data))
        rows.append(objs)
        stats.append((len(objs), sum(o["w"] for o in objs)))
    return rows, stats


# Graphics blocks for the background: $4000-$8FFF and $E000 (never in
# the $9000/$B000/$D000/$F000 holes, which read as zeros with holey DMA)
BG_BLOCKS = [0x40, 0x50, 0x60, 0x70, 0x80, 0xE0]


def pack(rows):
    blocks = [[bytearray(256) for _ in range(16)] for _ in BG_BLOCKS]
    used = [0] * len(BG_BLOCKS)
    seen = {}
    for objs in rows:
        for o in objs:
            key = b"".join(o["data"])
            if key in seen:
                o["lo"], o["hi"] = seen[key]
                continue
            for bi in range(len(BG_BLOCKS)):
                if used[bi] + o["w"] <= 256:
                    break
            else:
                raise SystemExit("background graphics do not fit in the blocks")
            lo = used[bi]
            used[bi] += o["w"]
            for y in range(16):
                page = 15 - y           # MARIA reads the top line from hi+15
                blocks[bi][page][lo:lo + o["w"]] = o["data"][y]
            o["lo"], o["hi"] = lo, BG_BLOCKS[bi]
            seen[key] = (lo, BG_BLOCKS[bi])
    data = b"".join(b"".join(bytes(p) for p in blk) for blk in blocks)
    return data, used


def emit_rows(rows):
    """Row and lamp lists go in the free tails of the $C000 sprite block's
    pages (written into gen/spr1.bin); the asm gets only pointer tables."""
    used = int((GEN / "spr_used.txt").read_text().split()[1])
    blk = bytearray((GEN / "spr1.bin").read_bytes())
    pos = [used] * 16                      # next free byte in each page

    def place(data):
        for pg in range(16):
            if pos[pg] + len(data) <= 256:
                a = pg * 256 + pos[pg]
                blk[a:a + len(data)] = data
                pos[pg] += len(data)
                return 0xC000 + a
        raise SystemExit("row data does not fit in the $C000 block")

    rptr, lptr = [], []
    for r, objs in enumerate(rows):
        bs = []
        lamps = []
        for i, o in enumerate(objs):
            pw = (o["pal"] << 5) | ((-o["w"]) & 31)
            bs += [o["lo"], pw, o["hi"], o["col"] * 4]
            if o["lamp"] >= 0:
                name = LAMP_NAMES[o["lamp"]]
                if name.startswith("drop") and not name.startswith("droplit"):
                    lamps += [i * 4, o["lamp"], 0xFF, o["col"] * 4]   # drop targets: shown or hidden
                else:
                    lamps += [i * 4, o["lamp"], pw, (5 << 5) | ((-o["w"]) & 31)]
        rptr.append(place(bytes([len(bs)] + bs)))
        lptr.append(place(bytes(lamps + [0xFF])))
    (GEN / "spr1.bin").write_bytes(bytes(blk))
    out = ["; Generated by tools/table.py. Do not edit.",
           f"; rows and lamp lists live in the $C000 block's free page tails ({sum(pos) - 16 * used} bytes)", ""]
    for nm, v in (("row_lo", [a & 255 for a in rptr]), ("row_hi", [a >> 8 for a in rptr]),
                  ("rowlamp_lo", [a & 255 for a in lptr]), ("rowlamp_hi", [a >> 8 for a in lptr])):
        out.append(nm)
        out.append("    .byte " + ",".join(f"${x:02X}" for x in v))
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Colliders, grid and sensors
SUB = 16
GRID = 32                 # units per grid cell
GW, GH = WU // GRID, H // GRID


def emit_colliders():
    cols = T.colliders
    n = len(cols)
    assert n < 255, n
    rec = dict(axl=[], axh=[], ayl=[], ayh=[], tl=[], th=[], ll=[], lh=[], r=[], kind=[], lay=[], ev=[], drop=[], e=[])
    for c in cols:
        ax, ay = c["a"]
        bx, by = c["b"]
        A = (round(ax * SUB), round(ay * SUB))
        ang = math.atan2(by - ay, bx - ax)
        t = int(round(ang / (2 * math.pi) * 65536)) & 0xFFFF
        L = round(math.hypot(bx - ax, by - ay) * SUB)
        rr = round(c["r"] * SUB)
        assert rr < 256
        rec["axl"].append(A[0] & 255); rec["axh"].append(A[0] >> 8)
        rec["ayl"].append(A[1] & 255); rec["ayh"].append(A[1] >> 8)
        rec["tl"].append(t & 255); rec["th"].append(t >> 8)
        rec["ll"].append(L & 255); rec["lh"].append(L >> 8)
        rec["r"].append(rr)
        rec["kind"].append(c["kind"] | c["flags"])
        rec["lay"].append(c["layers"])
        rec["ev"].append(c["event"])
        rec["drop"].append(c["drop"])
        rec["e"].append(min(255, int(round(c["e"] * 256))))
    grow = BALL_R + 5
    for c in cols:
        ax, ay = c["a"]
        bx, by = c["b"]
        rr = c["r"] + grow
        rec.setdefault("bx0", []).append(max(0, int((min(ax, bx) - rr) // 2)))
        rec.setdefault("bx1", []).append(min(255, int((max(ax, bx) + rr) // 2) + 1))
        rec.setdefault("by0", []).append(max(0, int((min(ay, by) - rr) // 2)))
        rec.setdefault("by1", []).append(min(255, int((max(ay, by) + rr) // 2) + 1))
    out = ["; Generated by tools/table.py. Do not edit.", f"NCOLL = {n}", ""]
    for k, v in rec.items():
        out.append(f"col_{k}")
        for i in range(0, len(v), 16):
            out.append("    .byte " + ",".join(str(x) for x in v[i:i + 16]))

    # grid: which colliders come within reach of each cell
    reach = BALL_R + 4
    lists = []
    for gy in range(GH):
        for gx in range(GW):
            x0, y0, x1, y1 = gx * GRID - reach, gy * GRID - reach, (gx + 1) * GRID + reach, (gy + 1) * GRID + reach
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            hit = []
            for i, c in enumerate(cols):
                ax, ay = c["a"]
                bx, by = c["b"]
                # sample the collider; conservative test against the box grown by r
                rr = c["r"]
                found = False
                steps = max(2, int(math.hypot(bx - ax, by - ay) / 4) + 1)
                for s in range(steps + 1):
                    px = ax + (bx - ax) * s / steps
                    py = ay + (by - ay) * s / steps
                    if x0 - rr <= px <= x1 + rr and y0 - rr <= py <= y1 + rr:
                        found = True
                        break
                if found:
                    hit.append(i)
            lists.append(hit)
    mx = max(len(l) for l in lists)
    out.append(f"GRIDW = {GW}")
    out.append(f"GRIDH = {GH}")
    out.append("grid_lo")
    for gy in range(GH):
        out.append("    .byte " + ",".join(f"<gl_{gy * GW + gx}" for gx in range(GW)))
    out.append("grid_hi")
    for gy in range(GH):
        out.append("    .byte " + ",".join(f">gl_{gy * GW + gx}" for gx in range(GW)))
    done = {}
    for i, l in enumerate(lists):
        key = tuple(l)
        if key in done:
            out.append(f"gl_{i} = gl_{done[key]}")
            continue
        done[key] = i
        out.append(f"gl_{i}")
        out.append("    .byte " + ",".join(str(x) for x in l + [255]))

    # sensors near each grid cell (a ball's center in the cell can only be in these)
    S = T.sensors
    out.append("sgrid_lo")
    slists = []
    for gy in range(GH):
        for gx in range(GW):
            x0, y0, x1, y1 = gx * GRID, gy * GRID, (gx + 1) * GRID, (gy + 1) * GRID
            slists.append([i for i, sn in enumerate(S)
                           if sn["box"][0] <= x1 and sn["box"][2] >= x0 and sn["box"][1] <= y1 and sn["box"][3] >= y0])
    for gy in range(GH):
        out.append("    .byte " + ",".join(f"<sl_{gy * GW + gx}" for gx in range(GW)))
    out.append("sgrid_hi")
    for gy in range(GH):
        out.append("    .byte " + ",".join(f">sl_{gy * GW + gx}" for gx in range(GW)))
    done = {}
    for i, l in enumerate(slists):
        key = tuple(l)
        if key in done:
            out.append(f"sl_{i} = sl_{done[key]}")
            continue
        done[key] = i
        out.append(f"sl_{i}")
        out.append("    .byte " + ",".join(str(x) for x in l + [255]))

    out.append(f"NSENS = {len(S)}")
    for fld in ("x0", "x1", "y0", "y1"):
        idx = {"x0": 0, "y0": 1, "x1": 2, "y1": 3}[fld]
        out.append(f"sen_{fld}")
        out.append("    .byte " + ",".join(str(int(s["box"][idx]) // 2) for s in S))
    out.append("sen_ev")
    out.append("    .byte " + ",".join(str(s["event"]) for s in S))
    out.append("sen_lay")
    out.append("    .byte " + ",".join(str(s["layers"]) for s in S))
    out.append("sen_cond")
    out.append("    .byte " + ",".join(str(s["cond"]) for s in S))
    out.append("sen_set")
    out.append("    .byte " + ",".join(str(s["setlayer"]) for s in S))
    out.append("")
    for name, i in T.events.items():
        out.append(f"EV_{name.upper()} = {i}")
    for name, i in T.lamps.items():
        out.append(f"LAMP_{name.upper()} = {i}")
    out.append(f"NLAMPS = {len(T.lamps)}")
    for k, v in T.consts.items():
        out.append(f"{k} = {v}")
    # flippers (1/16 units)
    out.append(f"FLIPL_X = {FLIP_L[0] * SUB}")
    out.append(f"FLIPR_X = {FLIP_R[0] * SUB}")
    out.append(f"FLIP_Y = {FLIP_L[1] * SUB}")
    out.append(f"FLIP_LEN = {FLIP_LEN * SUB}")
    out.append(f"FLIP_RAD = {int(FLIP_RAD * SUB)}")
    out.append(f"FLIP_REST = ${int(round(FLIP_REST / 360 * 65536)) & 0xFFFF:04X}")
    out.append(f"FLIP_UPANG = ${int(round(FLIP_UP / 360 * 65536)) & 0xFFFF:04X}")
    out.append(f"BALL_R = {BALL_R * SUB}")
    out.append(f"TABLE_ROWS = {ROWS}")
    out.append(f"BGCOLOR = ${BG:02X}")
    out.append("palettes")
    out.append("    .byte " + ",".join(f"${c:02X}" for p in PALS for c in p))
    out.append("pal7 = palettes+21")
    out.append("hud_p7 .byte " + ",".join(f"${c:02X}" for c in HUD_P7))
    return "\n".join(out) + "\n", mx


# ---------------------------------------------------------------------------
# PNG output
def write_png(path, w, h, pixels):
    raw = b"".join(b"\x00" + bytes(c for p in row for c in p) for row in pixels)
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def preview(rows, path, geo=False):
    """Render what MARIA will show (the converted objects), 2x wide pixels."""
    img = [[rgb(BG)] * 320 for _ in range(H)]
    for r, objs in enumerate(rows):
        for o in objs:
            pal = 5 if (o["lamp"] >= 0 and LAMP_NAMES[o["lamp"]] in PREVIEW_LIT) else o["pal"]
            for y in range(16):
                for i in range(o["w"]):
                    b = o["data"][y][i]
                    for k in range(4):
                        v = (b >> (6 - 2 * k)) & 3
                        if v:
                            x = (o["col"] + i) * 4 + k
                            c = rgb(PALS[pal][v - 1])
                            img[r * 16 + y][2 * x] = c
                            img[r * 16 + y][2 * x + 1] = c
    if geo:
        def plot(x, y, c):
            xi, yi = int(round(x)), int(round(y))
            if 0 <= xi < 320 and 0 <= yi < H:
                img[yi][xi] = c
        for c in T.colliders:
            col = (255, 255, 0) if c["layers"] & 1 else (0, 255, 0)
            if c["layers"] == 2:
                col = (0, 255, 0)
            if c["kind"] == K_CIRC:
                for k in range(64):
                    a = k / 64 * 2 * math.pi
                    plot(c["a"][0] + c["r"] * math.cos(a), c["a"][1] + c["r"] * math.sin(a), col)
            else:
                ax, ay = c["a"]
                bx, by = c["b"]
                n = int(math.hypot(bx - ax, by - ay)) + 1
                for k in range(n + 1):
                    plot(ax + (bx - ax) * k / n, ay + (by - ay) * k / n, col)
                if c["kind"] == K_SEG:
                    # front normal tick
                    mx, my = (ax + bx) / 2, (ay + by) / 2
                    d = math.hypot(bx - ax, by - ay)
                    nx, ny = (by - ay) / d, -(bx - ax) / d
                    for k in range(5):
                        plot(mx + nx * k, my + ny * k, (255, 0, 0))
        for s in T.sensors:
            x0, y0, x1, y1 = s["box"]
            for x in range(int(x0), int(x1) + 1):
                plot(x, y0, (0, 200, 255)); plot(x, y1, (0, 200, 255))
            for y in range(int(y0), int(y1) + 1):
                plot(x0, y, (0, 200, 255)); plot(x1, y, (0, 200, 255))
        for (fx, fy), sgn in ((FLIP_L, 1), (FLIP_R, -1)):
            for ang in (FLIP_REST, FLIP_UP):
                a = math.radians(ang)
                for k in range(FLIP_LEN):
                    plot(fx + sgn * k * math.cos(a), fy + k * math.sin(a), (255, 128, 0))
    write_png(path, 320, H, img)


PREVIEW_LIT = {"lane1", "bumper2", "ramp_arrow", "bonus0", "shoot_again", "droplit1", "lock_arrow"}
LAMP_NAMES = {}


def main():
    global LAMP_NAMES
    LAMP_NAMES = {v: k for k, v in T.lamps.items()}
    rows, stats = build_rows()
    data, used = pack(rows)
    GEN.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    (GEN / "bg0.bin").write_bytes(data[:5 * 4096])      # $4000-$8FFF
    (GEN / "bg1.bin").write_bytes(data[5 * 4096:])      # $E000-$EFFF
    (GEN / "rows.asm").write_text(emit_rows(rows))
    txt, mx = emit_colliders()
    (GEN / "colliders.asm").write_text(txt)
    preview(rows, BUILD / "table.png")
    preview(rows, BUILD / "table_geo.png", geo=True)
    worst = max(stats)
    print(f"table: {ROWS} rows, objects/row max {max(s[0] for s in stats)}, "
          f"bytes/row max {max(s[1] for s in stats)}, bg columns used {used} of 256 each, "
          f"{len(T.colliders)} colliders (grid cell max {mx}), {len(T.sensors)} sensors, {len(T.lamps)} lamps")
    for r, s in enumerate(stats):
        if s[0] > 13:
            print(f"  row {r}: {s[0]} objects, {s[1]} bytes")


if __name__ == "__main__":
    main()
