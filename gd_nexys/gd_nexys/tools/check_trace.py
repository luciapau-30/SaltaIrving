#!/usr/bin/env python3
"""Compare sim/out/trace_rtl.txt (from tb_game_sm.v) with the Python model, tick by tick."""
import os
import sys
import gd_model as m

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def model_trace(level):
    sched, _ = m.solve(level)
    tiles, speed = m.tiles_of(level), m.SPEED[level]
    s, h, v, out = 0, 0, 0, []
    for j in sched:
        r, s, h, v = m.step(tiles, speed, s, h, v, j)
        out.append((level, s, h, r))
    return out


def no_jump_crash(level):
    tiles, speed = m.tiles_of(level), m.SPEED[level]
    s, h, v, n = 0, 0, 0, 0
    while True:
        n += 1
        r, s, h, v = m.step(tiles, speed, s, h, v, 0)
        if r == 'crash':
            return n, s


def main():
    rtl = [tuple(map(int, ln.split())) for ln in open(os.path.join(ROOT, 'sim/out/trace_rtl.txt'))]
    ref = model_trace(1) + model_trace(2) + model_trace(3)
    if len(rtl) != len(ref):
        print(f'FAIL: RTL has {len(rtl)} ticks, model has {len(ref)}')
        return 1
    bad = 0
    for i, (a, b) in enumerate(zip(rtl, ref)):
        if b[3] == 'clear':
            continue          # RTL has already moved on to LOAD (scroll reset) on this tick
        if a != b[:3]:
            bad += 1
            if bad <= 5:
                print(f'mismatch at tick {i}: rtl {a} model {b[:3]}')
    n, s = no_jump_crash(1)
    print(f'model: no-jump crash on level 1 after {n} ticks (scroll {s})')
    if bad:
        print(f'FAIL: {bad} mismatching ticks out of {len(ref)}')
        return 1
    print(f'PASS: RTL matches the Python model on all {len(ref)} ticks (levels 1-3)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
