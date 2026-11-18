#!/usr/bin/env python3
"""The soundtrack and the sound effects: writes src/gen/music.asm.

One song, "Mega Drive" (A minor, a sixteenth = 6 frames, 150 BPM), played
three ways: the title (no drums, slower), the game, and multiball (faster);
and a short game over tune. See src/sound.asm for the stream format.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "src" / "gen"

NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
BASE = 24          # note 0 = C1


def midi(s):
    s = s.strip()
    name, octv = s[:-1], int(s[-1])
    return 12 * (octv + 1) + NAMES[name]


def note(s):
    return midi(s) - BASE


def parse(text):
    """'E5:2 A5:2 r:4' -> [(note or None, sixteenths)]"""
    out = []
    for tok in text.split():
        n, d = tok.split(":")
        out.append((None if n == "r" else note(n), int(d)))
    return out


# ---------------------------------------------------------------------------
# Instruments: envelope (volumes a frame, last held), arpeggio (offsets a frame, looped)
INSTR = [
    ("lead", [12, 13, 12, 11, 10, 10, 9, 9, 9, 8, 8, 8, 8, 7], None),
    ("bass", [13, 12, 11, 10, 9, 8, 7, 7, 6], None),
    ("arpmin", [7, 7, 6, 6, 6, 5, 5, 5, 5, 4], [0, 0, 3, 3, 7, 7, 12, 12]),
    ("arpmaj", [7, 7, 6, 6, 6, 5, 5, 5, 5, 4], [0, 0, 4, 4, 7, 7, 12, 12]),
    ("pluck", [13, 11, 9, 7, 6, 5, 4, 3, 2, 0], None),
    ("pad", [3, 4, 5, 6, 6, 6, 6, 5], None),
]
INS = {n: i for i, (n, _, _) in enumerate(INSTR)}

# Drums on POKEY 2 channel 3 at the 15 kHz clock: (AUDC, AUDF) a frame
DRUMS = [
    ("kick", [(0xAF, 18), (0xAD, 30), (0xAB, 46), (0xA9, 66), (0xA7, 92), (0xA5, 120), (0xA3, 150), (0xA1, 180)]),
    ("snare", [(0x8C, 5), (0x8B, 6), (0x8A, 7), (0x88, 8), (0x86, 8), (0x84, 9), (0x83, 9), (0x82, 10), (0x81, 10)]),
    ("hat", [(0x86, 0), (0x83, 0), (0x81, 0)]),
    ("ohat", [(0x86, 0), (0x85, 0), (0x84, 0), (0x83, 0), (0x82, 0), (0x81, 0)]),
    ("tom", [(0xAC, 40), (0xAA, 46), (0xA8, 52), (0xA6, 58), (0xA4, 64), (0xA2, 70)]),
]
DR = {n: i for i, (n, _) in enumerate(DRUMS)}

# ---------------------------------------------------------------------------
# The song. Chords a bar.
INTRO = ["Am", "Am", "F", "G"]
SEC_A = ["Am", "F", "C", "G", "Am", "F", "C", "G"]
SEC_B = ["F", "G", "Em", "Am", "F", "G", "Em", "E"]
SEC_C = ["Dm", "Am", "Dm", "Am", "F", "G", "Am", "E"]
FORM = SEC_A + SEC_B + SEC_A + SEC_C

ROOT_OF = {"Am": "A", "F": "F", "C": "C", "G": "G", "Em": "E", "E": "E", "Dm": "D"}
MINOR = {"Am", "Em", "Dm"}

LEAD_A = """
E5:2 A5:2 C6:2 B5:2 A5:4 E5:4
F5:2 A5:2 C6:4 A5:2 G5:2 F5:4
E5:2 G5:2 C6:2 D6:2 E6:4 D6:2 C6:2
B5:4 G5:4 D6:6 r:2
E5:2 A5:2 C6:2 B5:2 A5:4 C6:2 E6:2
F6:4 E6:2 D6:2 C6:4 A5:4
G5:2 C6:2 E6:2 G6:2 E6:2 D6:2 C6:4
D6:4 B5:4 G5:4 r:4
"""
LEAD_B = """
A5:6 C6:2 A5:4 F5:4
B5:6 D6:2 B5:4 G5:4
G5:4 B5:4 E6:6 D6:2
C6:8 B5:4 A5:4
A5:2 C6:2 F6:4 E6:2 D6:2 C6:4
D6:2 B5:2 G5:4 B5:2 D6:2 G6:4
G6:4 E6:4 B5:4 G5:4
G#5:4 B5:4 E6:4 G#6:4
"""
LEAD_C = """
D6:3 F6:3 A6:2 G6:2 F6:2 E6:2 D6:2
C6:3 E6:3 A6:6 E6:4
F6:2 E6:2 D6:2 A5:2 D6:4 F6:4
E6:2 D6:2 C6:2 B5:2 A5:8
A5:2 C6:2 F6:2 A6:2 G6:2 F6:2 E6:2 C6:2
B5:2 D6:2 G6:2 B6:2 A6:2 G6:2 F6:2 D6:2
E6:4 C6:4 A5:4 E6:4
E6:2 D6:2 C6:2 B5:2 G#5:4 E5:4
"""

DRUM_MAIN = "kick:2 hat:2 snare:2 hat:1 kick:1 r:2 kick:2 snare:2 hat:1 hat:1"
DRUM_MAIN2 = "kick:2 hat:2 snare:2 hat:2 kick:2 hat:1 kick:1 snare:2 ohat:2"
DRUM_INTRO = "kick:4 hat:4 kick:4 hat:2 hat:2"
DRUM_FILL = "snare:2 snare:2 snare:2 snare:2 tom:2 tom:2 snare:1 snare:1 snare:2"


def drum_parse(text):
    out = []
    for tok in text.split():
        n, d = tok.split(":")
        out.append((None if n == "r" else DR[n], int(d)))
    return out


class Stream:
    def __init__(self, label):
        self.label = label
        self.lines = []
        self.marks = {}

    def mark(self, name):
        self.lines.append(f"{self.label}_{name}")

    def ins(self, name):
        self.lines.append(f"    .byte $81,{INS[name]}")

    def trans(self, t):
        self.lines.append(f"    .byte $85,{t & 255}")

    def notes(self, seq):
        for n, d in seq:
            while d > 0:
                dd = min(d, 32)
                if n is None:
                    self.lines.append(f"    .byte $80,{dd}")
                else:
                    self.lines.append(f"    .byte {n},{dd}")
                d -= dd

    def call(self, label):
        self.lines.append(f"    .byte $83,<{label},>{label}")

    def jump(self, name):
        self.lines.append(f"    .byte $82,<{self.label}_{name},>{self.label}_{name}")

    def end(self):
        self.lines.append("    .byte $86")


def song_main():
    v0, v1, v2, v3 = Stream("mm_v0"), Stream("mm_v1"), Stream("mm_v2"), Stream("mm_v3")
    # intro
    v0.ins("lead")
    v0.notes([(None, 16 * len(INTRO))])
    v0.mark("loop")
    for sec in (LEAD_A, LEAD_B, LEAD_A, LEAD_C):
        v0.notes(parse(sec))
    v0.jump("loop")

    v1.ins("bass")
    v2.trans(0)

    def bass_bar(ch, busy):
        r = ROOT_OF[ch]
        lo, hi = note(r + "2"), note(r + "3")
        if r in ("A", "G", "F"):
            lo, hi = note(r + "1"), note(r + "2")
        if busy:
            return [(lo, 2), (hi, 2)] * 4
        return [(lo, 4), (lo, 2), (hi, 2), (lo, 4), (hi, 4)]

    def harm_bar(ch):
        r = ROOT_OF[ch]
        return ("arpmin" if ch in MINOR else "arpmaj", note(r + "4"))

    for ch in INTRO:
        v1.notes(bass_bar(ch, False))
    v1.mark("loop")
    for i, ch in enumerate(FORM):
        v1.notes(bass_bar(ch, i % 16 >= 8 or i >= 24))
    v1.jump("loop")

    cur = None
    v2.notes([(None, 32)])
    for ch in INTRO[2:]:
        ins, n = harm_bar(ch)
        if ins != cur:
            v2.ins(ins)
            cur = ins
        v2.notes([(n, 16)])
    v2.mark("loop")
    cur = None
    for ch in FORM:
        ins, n = harm_bar(ch)
        if ins != cur:
            v2.ins(ins)
            cur = ins
        v2.notes([(n, 8), (n, 8)])
    v2.jump("loop")

    for i in range(len(INTRO)):
        v3.call("drum_intro" if i < 3 else "drum_fill")
    v3.mark("loop")
    for i in range(len(FORM)):
        if i % 8 == 7:
            v3.call("drum_fill")
        else:
            v3.call("drum_main2" if i % 2 else "drum_main")
    v3.jump("loop")
    return [v0, v1, v2, v3]


def song_over():
    v0, v1, v2, v3 = Stream("mo_v0"), Stream("mo_v1"), Stream("mo_v2"), Stream("mo_v3")
    v0.ins("lead")
    v0.notes(parse("E6:2 D6:2 C6:2 B5:2 A5:4 E5:4 F5:3 E5:3 D#5:2 E5:12"))
    v0.end()
    v1.ins("bass")
    v1.notes(parse("A2:8 F2:8 E2:8 A1:12"))
    v1.end()
    v2.ins("arpmin")
    v2.notes(parse("A4:8"))
    v2.ins("arpmaj")
    v2.notes(parse("F4:8 E4:8"))
    v2.ins("arpmin")
    v2.notes(parse("A4:12"))
    v2.end()
    v3.notes([(DR["kick"], 4), (DR["snare"], 4), (DR["kick"], 4), (DR["snare"], 4), (DR["tom"], 2),
              (DR["tom"], 2), (DR["tom"], 4), (DR["kick"], 12)])
    v3.end()
    return [v0, v1, v2, v3]


# ---------------------------------------------------------------------------
# TIA effects: (AUDC, AUDF, AUDV) a frame; channel; priority
def sweep(c, f0, f1, v0, v1, n):
    return [(c, round(f0 + (f1 - f0) * i / (n - 1)), round(v0 + (v1 - v0) * i / (n - 1))) for i in range(n)]


def notes_fx(c, fs, each, v):
    out = []
    for f in fs:
        out += [(c, f, v)] * each
    return out


SFX = [
    ("FLIPPER", 0, 2, [(8, 3, 10), (8, 5, 7), (8, 8, 4), (8, 12, 2)]),
    ("PULL", 0, 1, [(12, 24, 4), (12, 24, 2)]),
    ("LAUNCH", 0, 3, sweep(8, 22, 2, 12, 2, 12)),
    ("BUMPER", 1, 3, [(12, 9, 14), (12, 9, 12)] + sweep(4, 17, 19, 12, 2, 8)),
    ("SLING", 1, 2, [(8, 12, 12), (1, 20, 10), (1, 24, 8), (1, 28, 5), (1, 30, 2)]),
    ("DROP", 1, 3, sweep(12, 18, 28, 12, 4, 6)),
    ("TARGET", 1, 3, [(4, 12, 12)] * 3 + [(4, 12, 8), (4, 12, 5), (4, 12, 2)]),
    ("LANE", 1, 3, notes_fx(4, [9, 7, 5], 3, 10)),
    ("LIT", 1, 5, notes_fx(4, [15, 12, 10, 8, 6, 5], 4, 12)),
    ("AWARD", 1, 6, notes_fx(4, [11, 9, 7, 5, 7, 5, 4], 4, 13)),
    ("RAMPIN", 1, 3, sweep(12, 28, 12, 10, 6, 8)),
    ("RAMP", 1, 5, sweep(4, 20, 4, 13, 8, 18)),
    ("JACKPOT", 1, 7, notes_fx(4, [15, 11, 9, 7, 9, 7, 5, 4, 5, 4, 3], 4, 14)),
    ("SPIN", 0, 1, [(8, 1, 6), (8, 1, 2)]),
    ("HOLE", 1, 4, sweep(12, 8, 30, 13, 4, 20)),
    ("KICK", 1, 4, sweep(8, 10, 20, 14, 2, 8)),
    ("DRAIN", 1, 8, sweep(1, 12, 31, 13, 4, 50)),
]


def f16(n):
    f = 440.0 * 2 ** ((n + BASE - 69) / 12)
    v = round(1789773 / (2 * f) - 7)
    return max(0, min(65535, v))


def main():
    out = ["; Generated by tools/music.py. Do not edit.", ""]
    out.append("MUS_TITLE = 0")
    out.append("MUS_MAIN = 1")
    out.append("MUS_MBALL = 2")
    out.append("MUS_OVER = 3")
    songs = [("main", 7, 7), ("main", 6, 15), ("main", 5, 15), ("over", 7, 15)]
    out.append("song_lo .byte " + ",".join(f"<song_{i}" for i in range(len(songs))))
    out.append("song_hi .byte " + ",".join(f">song_{i}" for i in range(len(songs))))
    pre = {"main": "mm", "over": "mo"}
    for i, (nm, speed, mask) in enumerate(songs):
        p = pre[nm]
        out.append(f"song_{i} .byte {speed},{mask}")
        out.append("    .word " + ",".join(f"{p}_v{k}" for k in range(4)))
    for s in song_main() + song_over():
        out.append(s.label)
        out += s.lines
    for name, txt in (("drum_main", DRUM_MAIN), ("drum_main2", DRUM_MAIN2), ("drum_intro", DRUM_INTRO),
                      ("drum_fill", DRUM_FILL)):
        seq = drum_parse(txt)
        assert sum(d for _, d in seq) == 16, name
        out.append(name)
        for n, d in seq:
            out.append(f"    .byte {'$80' if n is None else n},{d}")
        out.append("    .byte $84")
    # instruments
    for i, (nm, env, arp) in enumerate(INSTR):
        out.append(f"ins_env_{i} .byte " + ",".join(str(v) for v in env) + ",$FF")
        if arp:
            out.append(f"ins_arp_{i} .byte " + ",".join(str(v) for v in arp) + ",$FF")
    out.append("ins_env_lo .byte " + ",".join(f"<ins_env_{i}" for i in range(len(INSTR))))
    out.append("ins_env_hi .byte " + ",".join(f">ins_env_{i}" for i in range(len(INSTR))))
    out.append("ins_arp_lo .byte " + ",".join(f"<ins_arp_{i}" if a else "0" for i, (_, _, a) in enumerate(INSTR)))
    out.append("ins_arp_hi .byte " + ",".join(f">ins_arp_{i}" if a else "0" for i, (_, _, a) in enumerate(INSTR)))
    for i, (nm, mac) in enumerate(DRUMS):
        out.append(f"drum_{i} .byte " + ",".join(f"${c:02X},{f}" for c, f in mac) + ",0")
    out.append("drum_lo .byte " + ",".join(f"<drum_{i}" for i in range(len(DRUMS))))
    out.append("drum_hi .byte " + ",".join(f">drum_{i}" for i in range(len(DRUMS))))
    # frequencies
    fr = [f16(n) for n in range(96)]
    out.append("f16lo")
    for i in range(0, 96, 16):
        out.append("    .byte " + ",".join(str(v & 255) for v in fr[i:i + 16]))
    out.append("f16hi")
    for i in range(0, 96, 16):
        out.append("    .byte " + ",".join(str(v >> 8) for v in fr[i:i + 16]))
    # effects (id 0 = none)
    for i, (nm, ch, pri, data) in enumerate(SFX):
        out.append(f"SFX_{nm} = {i + 1}")
        out.append(f"sfxd_{i + 1} .byte " + ",".join(f"{c},{f},{v}" for c, f, v in data) + ",$FF")
    ids = range(len(SFX) + 1)
    out.append("sfx_chan .byte 0," + ",".join(str(s[1]) for s in SFX))
    out.append("sfx_pri .byte 0," + ",".join(str(s[2]) for s in SFX))
    out.append("sfx_dlo .byte 0," + ",".join(f"<sfxd_{i}" for i in ids if i))
    out.append("sfx_dhi .byte 0," + ",".join(f">sfxd_{i}" for i in ids if i))
    GEN.mkdir(parents=True, exist_ok=True)
    (GEN / "music.asm").write_text("\n".join(out) + "\n")
    print(f"music: {sum(1 for l in out if '.byte' in l)} data lines")


if __name__ == "__main__":
    main()
