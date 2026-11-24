#!/usr/bin/env python3
"""
Renders real frames from the RTL renderer (sim/tb_render.v) for a set of game
moments taken from the model's winning runs, then converts them to PNG.
Usage: python3 tools/make_frames.py      (needs iverilog + Pillow)
"""
import os
import subprocess
import gd_model as m
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join(ROOT, 'sim', 'out')
INIT, MENU, LOAD, PLAY, PAUSE, CRASH, CLEAR, GAME_OVER, WIN = range(9)


def trace(level):
    sched, _ = m.solve(level)
    tiles, speed = m.tiles_of(level), m.SPEED[level]
    s, h, v, out = 0, 0, 0, []
    for j in sched:
        out.append((s, h))
        r, s, h, v = m.step(tiles, speed, s, h, v, j)
    return out


def moment(level, world_x, want_air=True):
    """First tick where the runner is near world_x (and in the air, if asked)."""
    best = None
    for s, h in trace(level):
        if s + m.RX >= world_x - 64:
            if not want_air or h >= 40:
                return s, h
            best = best or (s, h)
    return best


def main():
    os.makedirs(OUT, exist_ok=True)
    l1 = moment(1, 35 * 32)          # cones + first pothole
    l1b = moment(1, 66 * 32)         # barricade run with a cone on top
    l1c = moment(1, 84 * 32, False)  # tall barricades
    l2 = moment(2, 31 * 32)          # steel spikes + river
    l2b = moment(2, 60 * 32)         # crate run with spikes on top
    l2c = moment(2, 79 * 32)         # wide river + stacked crates
    rows = [
        # name        state     lv lives prac scroll        h       timer crashes
        ('menu',      MENU,      1, 9, 0, 0,       0,      0, 0),
        ('play_l1',   PLAY,      1, 9, 0, l1[0],   l1[1],  0, 0),
        ('play_l1b',  PLAY,      1, 8, 0, l1b[0],  l1b[1], 0, 1),
        ('play_l1c',  PLAY,      1, 8, 0, l1c[0],  l1c[1], 0, 1),
        ('play_l2',   PLAY,      2, 7, 0, l2[0],   l2[1],  0, 2),
        ('play_l2b',  PLAY,      2, 7, 0, l2b[0],  l2b[1], 0, 2),
        ('play_l2c',  PLAY,      2, 7, 1, l2c[0],  l2c[1], 0, 2),
        ('pause',     PAUSE,     1, 8, 0, l1b[0],  l1b[1], 0, 1),
        ('crash',     CRASH,     1, 8, 0, 975,     0,      4, 1),
        ('game_over', GAME_OVER, 1, 0, 0, 975,     0,      59, 9),
        ('win',       WIN,       2, 6, 0, 7168,    0,      0, 3),
        ('menu_l2',   MENU,      2, 9, 1, 0,       0,      0, 0),
    ]
    with open(os.path.join(OUT, 'scenarios.txt'), 'w') as f:
        for r in rows:
            f.write(' '.join(str(x) for x in r) + '\n')
    src = [os.path.join(ROOT, p) for p in
           ('sim/tb_render.v', 'src/vga_bitchange.v', 'src/level_rom.v', 'src/text_rom.v', 'src/font_rom.v',
            'src/skyline_rom.v', 'src/jungle_rom.v', 'src/sprite_rom.v', 'src/hole_rom.v')]
    vvp = os.path.join(OUT, 'tb_render.vvp')
    subprocess.run(['iverilog', '-g2005', '-o', vvp] + src, check=True)
    subprocess.run(['vvp', '-n', vvp], check=True, cwd=ROOT)
    for r in rows:
        ppm = os.path.join(OUT, f'frame_{r[0]}.ppm')
        vals = open(ppm).read().split()[4:]
        img = Image.new('RGB', (640, 480))
        img.putdata([tuple(int(vals[i + k]) * 17 for k in range(3)) for i in range(0, len(vals), 3)])
        img.save(os.path.join(OUT, f'frame_{r[0]}.png'))
        os.remove(ppm)
    print('frames in sim/out/frame_*.png')


if __name__ == '__main__':
    main()
