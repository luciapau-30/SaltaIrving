#!/usr/bin/env python3
"""Renders consecutive PLAY frames with the RTL renderer: docs/parallax_city.gif / parallax_jungle.gif.

    python3 tools/make_parallax_gif.py [level]
"""
import os, sys, subprocess
import gd_model as m
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join(ROOT, 'sim', 'out')


def main(level=1, first_tick=300, n=60, step=2):
    sched, _ = m.solve(level)
    tiles, speed = m.tiles_of(level), m.SPEED[level]
    tag = 'city' if level == 1 else 'jungle'
    s, h, v, trace = 0, 0, 0, []
    for j in sched:
        trace.append((s, h))
        _, s, h, v = m.step(tiles, speed, s, h, v, j)
    os.makedirs(OUT, exist_ok=True)
    scen = os.path.join(OUT, f'scenarios_{tag}.txt')
    with open(scen, 'w') as f:
        for i in range(n):
            sc, hh = trace[first_tick + i * step]
            f.write(f'{tag}{i:03d} 3 {level} 9 0 {sc} {hh} 0 0\n')
    src = [os.path.join(ROOT, p) for p in ('sim/tb_render.v', 'src/vga_bitchange.v', 'src/level_rom.v',
                                           'src/text_rom.v', 'src/font_rom.v', 'src/skyline_rom.v',
                                           'src/jungle_rom.v', 'src/sprite_rom.v', 'src/hole_rom.v')]
    vvp = os.path.join(OUT, f'tb_render_{tag}.vvp')
    subprocess.run(['iverilog', '-g2005', f'-DSCEN="sim/out/scenarios_{tag}.txt"', '-o', vvp] + src, check=True)
    subprocess.run(['vvp', '-n', vvp], check=True, cwd=ROOT, stdout=subprocess.DEVNULL)
    frames = []
    for i in range(n):
        ppm = os.path.join(OUT, f'frame_{tag}{i:03d}.ppm')
        vals = open(ppm).read().split()[4:]
        img = Image.new('RGB', (640, 480))
        img.putdata([tuple(int(vals[k + c]) * 17 for c in range(3)) for k in range(0, len(vals), 3)])
        frames.append(img)
        os.remove(ppm)
    # 2 game ticks per GIF frame -> play at 30 fps for real-time speed
    out = os.path.join(ROOT, 'docs', f'parallax_{tag}.gif')
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=33, loop=0, optimize=True)
    print('wrote', os.path.relpath(out, ROOT))


if __name__ == '__main__':
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
