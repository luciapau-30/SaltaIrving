#!/usr/bin/env python3
"""Compare sim/out/trace_rtl.txt (from tb_game_sm.v) with the Python model, tick by tick."""
import os
import sys
import gd_model as m

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def model_trace(level):
    sched, _ = m.solve(level)
    tiles, speed = m.tiles_of(level), m.SPEED[level]
    s, h, v, out = 0, 0, 0, []
    for j in sched:
        if j and m.grounded(tiles, s, h):
            model_trace.jumps += 1          # game_sm counts every take-off
        r, s, h, v = m.step(tiles, speed, s, h, v, j)
        out.append((level, s, h, model_trace.jumps, r))
    return out


model_trace.jumps = 0


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
    ref = sum((model_trace(lv) for lv in sorted(m.LEVELS)), [])
    if len(rtl) != len(ref):
        print(f'FAIL: RTL has {len(rtl)} ticks, model has {len(ref)}')
        return 1
    bad = 0
    for i, (a, b) in enumerate(zip(rtl, ref)):
        if b[4] == 'clear':
            continue          # RTL has already moved on to LOAD (scroll reset) on this tick
        if a != b[:4]:
            bad += 1
            if bad <= 5:
                print(f'mismatch at tick {i}: rtl {a} model {b[:4]}')
    n, s = no_jump_crash(1)
    print(f'model: no-jump crash on level 1 after {n} ticks (scroll {s})')
    import gen_roms
    _, hn, hs = gen_roms.hole_skip_schedule(1)
    rn, rs = map(int, open(os.path.join(ROOT, 'sim/out/hole_crash.txt')).read().split())
    if (rn, rs) != (hn, hs):
        print(f'FAIL: pothole crash RTL ({rn} ticks, scroll {rs}) vs model ({hn}, {hs})')
        return 1
    print(f'PASS: pothole crash matches the model ({hn} ticks, scroll {hs})')
    if bad:
        print(f'FAIL: {bad} mismatching ticks out of {len(ref)}')
        return 1
    print(f'PASS: RTL matches the Python model on all {len(ref)} ticks (levels 1-{len(m.LEVELS)}), '
          f'jump counter = {ref[-1][3]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
