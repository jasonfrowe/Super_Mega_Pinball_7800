#!/usr/bin/env python3
"""Where the CPU's time goes, from the a7800 fork's cycle profiler.

Run the game with A7800_PROFILE=<file> (and A7800_PROFILE_WAIT=1 to start
it paused, for "prof on" / "prof off" in a play.sh script), then:

    tools/pcprof.py <profile> [build/work/gammaforce.bas.list.txt] [-n 30]

Each instruction's cycles are charged to the nearest label before it in
7800basic's listing (by ROM address, so banked code is told apart), and to
the BASIC statement it was compiled from. MARIA's DMA is shown apart; time
waiting in WSYNC goes to the instruction that wrote WSYNC."""
import argparse
import bisect
import re
from collections import defaultdict

SKIP = {'endif', 'else', 'endm', 'repend', 'eif'}
LABEL = re.compile(r'^\s*\d+\s+([0-9a-f]{4,5})\s+([A-Za-z_.][\w.]*)\s*(;.*)?$')
ORG = re.compile(r'^\s*\d+\s+[0-9a-fU?]+\s+\bORG\s+\$([0-9A-Fa-f]+)')
RORG = re.compile(r'^\s*\d+\s+[0-9a-fU?]+\s+\bRORG\s+\$([0-9A-Fa-f]+)')
BASLINE = re.compile(r';;line (\d+);;\s*(.*)')


def read_listing(path):
    """Labels as (rom address, name, comment); and where $C000 maps."""
    labels, top, org = [], None, None
    for line in open(path, errors='replace'):
        m = ORG.match(line)
        if m:
            org = int(m.group(1), 16)
            continue
        m = RORG.match(line)
        if m:
            if int(m.group(1), 16) == 0xC000 and org is not None:
                top = org
            continue
        m = LABEL.match(line)
        if m and m.group(2).lower() not in SKIP:
            labels.append((int(m.group(1), 16), m.group(2), (m.group(3) or '').strip()))
    labels.sort()
    return labels, top


def rom_addr(bank, pc, top):
    if pc < 0x4000:
        return None
    if pc < 0x8000:
        return pc
    if pc < 0xC000:
        return 0x8000 + bank * 0x4000 + (pc - 0x8000)
    return top + (pc - 0xC000) if top is not None else pc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('profile')
    ap.add_argument('listing', nargs='?', default='build/work/gammaforce.bas.list.txt')
    ap.add_argument('-n', type=int, default=30, help='rows to show')
    a = ap.parse_args()

    labels, top = read_listing(a.listing)
    addrs = [l[0] for l in labels]
    routines = [(ad, n) for ad, n, _ in labels if not n.startswith('.')]
    raddrs = [r[0] for r in routines]
    stmts = [(ad, BASLINE.search(c)) for ad, n, c in labels if n.startswith('.L') and BASLINE.search(c)]
    saddrs = [s[0] for s in stmts]

    head, rows = {}, []
    for line in open(a.profile):
        p = line.split()
        if not p or p[0] == '#':
            continue
        if len(p) == 2:
            head[p[0]] = int(p[1], 16) if p[0] == 'minsp' else int(p[1])
        else:
            rows.append((None if p[0] == '--' else int(p[0], 16), int(p[1], 16), int(p[2]), int(p[3])))

    by_routine, by_stmt = defaultdict(int), defaultdict(int)
    for bank, pc, cyc, _ in rows:
        ra = rom_addr(bank or 0, pc, top)
        if ra is None:
            by_routine[f'RAM ${pc:04x}'] += cyc
            continue
        i = bisect.bisect_right(raddrs, ra) - 1
        by_routine[routines[i][1] if i >= 0 else '?'] += cyc
        j = bisect.bisect_right(saddrs, ra) - 1
        # code after an assembly label (inline .asm) is not the statement's
        if j >= 0 and (i < 0 or stmts[j][0] >= routines[i][0]):
            m = stmts[j][1]
            by_stmt[f'line {m.group(1)}: {m.group(2)[:60]}'] += cyc

    frames = max(head.get('frames', 1), 1)
    total, dma = head.get('cycles', 1), head.get('dma', 0)
    print(f"{frames} frames, {total / frames:.0f} cycles a frame: "
          f"MARIA DMA {dma / frames:.0f} ({100 * dma / total:.1f}%), "
          f"CPU {(total - dma) / frames:.0f}; {head.get('instructions', 0) / frames:.0f} instructions a frame; "
          f"lowest SP ${head.get('minsp', 0xff):02x}")

    def show(title, table):
        print(f"\n{title:52s} {'cyc/frame':>9s} {'%':>6s}")
        for name, cyc in sorted(table.items(), key=lambda kv: -kv[1])[:a.n]:
            print(f"{name[:52]:52s} {cyc / frames:9.0f} {100 * cyc / total:6.1f}")

    show('routine (nearest label)', by_routine)
    show('BASIC statement', by_stmt)


if __name__ == '__main__':
    main()
