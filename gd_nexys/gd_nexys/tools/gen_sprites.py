#!/usr/bin/env python3
"""
Draws the obstacle sprites for both themes as pixel art and writes:

  src/sprite_rom.v   32x32 obstacle sprites, 3-bit colour index (0 = transparent)
  src/hole_rom.v     64x80 floor overlays: pothole (city) / river (jungle), 2-bit index
  docs/sprites.png   zoomed preview

Sprite ids (both themes):
  0 spike            city: traffic cone            jungle: metal spike trap
  1 block            city: construction barricade  jungle: wooden crate
  2 tall block, top  city: tall barricade (top)    jungle: crate
  3 tall block, bot  city: tall barricade (bottom) jungle: crate
  4 block under a spike (no warning lamp)          jungle: crate
Colour indices map to the palettes in vga_bitchange.v (CITY_PAL / JUNGLE_PAL).
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

# palettes (12-bit RGB) - must match vga_bitchange.v
CITY_PAL = {1: 'F61', 2: 'B30', 3: 'FFF', 4: '112', 5: '445', 6: 'FC1', 7: 'AAB'}
JUNGLE_PAL = {1: 'D94', 2: 'A62', 3: '631', 4: '211', 5: 'EEF', 6: '99A', 7: '556'}
CITY_HOLE_PAL = {1: '111', 2: '333', 3: '644'}
JUNGLE_HOLE_PAL = {1: '38D', 2: '7CF', 3: 'CEF'}

ORANGE, DORANGE, WHITE, INK, DGRAY, YELLOW, LGRAY = range(1, 8)
WOOD_L, WOOD_M, WOOD_D, BROWN_INK, METAL_L, METAL_M, METAL_D = range(1, 8)


# ------------------------------------------------------------------ city
def cone():
    s = np.zeros((32, 32), int)
    for r in range(1, 28):                          # body: 4 px wide at the top, 24 at the base
        hw = 1.5 + (r - 1) * 10.5 / 26
        c0, c1 = int(round(15.5 - hw)), int(round(15.5 + hw))
        for c in range(c0, c1 + 1):
            stripe = 8 <= r <= 11 or 17 <= r <= 20
            shade = c > 15.5 + hw * 0.35
            s[r, c] = (LGRAY if shade else WHITE) if stripe else (DORANGE if shade else ORANGE)
        s[r, c0] = INK
        s[r, c1] = INK
    s[0, 15:17] = INK
    s[27, 3:29] = INK                               # base plate
    s[28:31, 2:30] = DGRAY
    s[28, 4:28] = LGRAY
    s[31, 2:30] = INK
    s[28:31, 2] = INK
    s[28:31, 29] = INK
    return s


def barricade(rows=32, boards=(6,), lamp=True):
    s = np.zeros((rows, 32), int)
    if lamp:                                        # amber warning lamp
        s[0, 14:18] = INK
        s[1:5, 13] = INK
        s[1:5, 18] = INK
        s[1:5, 14:18] = YELLOW
        s[1, 15] = WHITE
        s[5, 15:17] = DGRAY
    for leg in (5, 24):                             # two legs with feet
        s[boards[0] + 10:rows - 2, leg:leg + 3] = YELLOW
        s[boards[0] + 10:rows - 2, leg + 2] = DORANGE
        s[boards[0] + 10:rows - 2, leg - 1] = INK
        s[boards[0] + 10:rows - 2, leg + 3] = INK
        s[rows - 3:rows, leg - 3:leg + 6] = DGRAY
        s[rows - 1, leg - 3:leg + 6] = INK
        s[rows - 3, leg - 3:leg + 6] = INK
    for top in boards:                              # striped boards
        s[top:top + 10, 1:31] = INK
        for r in range(top + 1, top + 9):
            for c in range(2, 30):
                s[r, c] = ORANGE if ((c + r) // 4) % 2 else WHITE
        s[top + 8, 2:30] = np.where(s[top + 8, 2:30] == ORANGE, DORANGE, LGRAY)
    return s


def pothole():
    h = np.zeros((80, 64), int)
    for r in range(0, 16):
        for c in range(0, 32):
            d = ((c - 15.5) / 15.0) ** 2 + ((r - 7.5) / 6.5) ** 2
            if d <= 1.0:
                h[r, c] = 1 if d <= 0.55 else 2
    for (r, c) in ((7, 0), (6, 1), (8, 31), (9, 30), (14, 9), (15, 8), (14, 22), (15, 23)):
        h[r, c] = 3                                 # little cracks around the rim
    return h


# ------------------------------------------------------------------ jungle
def spikes():
    s = np.zeros((32, 32), int)
    for cx in (4, 12, 19, 27):                      # four sharp steel spikes
        for r in range(5, 27):
            hw = (r - 5) * 3.6 / 21
            for c in range(int(np.floor(cx - hw)), int(np.ceil(cx + hw)) + 1):
                if 0 <= c < 32 and abs(c - cx) <= hw + 0.25:
                    s[r, c] = METAL_L if c <= cx else METAL_M
        s[5, cx] = METAL_L
    s[27, 1:31] = METAL_M                           # base plate
    s[28:31, 1:31] = METAL_D
    s[29, 3:29:4] = METAL_L                         # bolts
    s[31, 1:31] = BROWN_INK
    s[27:31, 0] = BROWN_INK
    s[27:31, 31] = BROWN_INK
    return s


def crate():
    s = np.zeros((32, 32), int)
    s[:, :] = WOOD_M
    for r in range(4, 28):                          # horizontal planks with seams
        if (r - 4) % 6 == 5:
            s[r, 4:28] = WOOD_D
    for r in range(4, 28):                          # diagonal brace (bottom-left to top-right)
        c = int(round(4 + (27 - r) * 23 / 23))
        s[r, max(4, c - 2):min(28, c + 3)] = WOOD_L
        if c - 3 >= 4:
            s[r, c - 3] = WOOD_D
        if c + 3 < 28:
            s[r, c + 3] = WOOD_D
    s[0:4, :] = WOOD_D                              # frame
    s[28:32, :] = WOOD_D
    s[:, 0:4] = WOOD_D
    s[:, 28:32] = WOOD_D
    s[1, 1:31] = WOOD_L
    s[1:31, 1] = WOOD_L
    for (r, c) in ((2, 2), (2, 29), (29, 2), (29, 29)):
        s[r, c] = METAL_L                           # nails
    s[0, :] = BROWN_INK
    s[31, :] = BROWN_INK
    s[:, 0] = BROWN_INK
    s[:, 31] = BROWN_INK
    return s


def river():
    h = np.zeros((80, 64), int)
    for r in range(80):
        t = r / 79.0
        c = 15.5 + 9 * np.sin(t * 3.4) + 14 * t       # meanders right as it comes "towards" you
        w = 15.5 + 6 * t                            # wide enough that two rivers in a row merge
        for col in range(64):
            d = abs(col - c)
            if d <= w:
                h[r, col] = 3 if d > w - 1.6 else 1
        for col in range(64):                       # ripples
            if h[r, col] == 1 and ((col * 3 + r * 5) % 23) < 3 and abs(col - c) < w - 3:
                h[r, col] = 2
    return h


def to_vhex(rows, bits):
    """Pack a row of indices (index 0 in the lowest bits) into a hex literal."""
    v = 0
    for x in range(len(rows) - 1, -1, -1):
        v = (v << bits) | int(rows[x])
    return f"{len(rows) * bits}'h{v:0{(len(rows) * bits + 3) // 4}X}"


def main():
    city = {0: cone(), 1: barricade(), 4: barricade(lamp=False)}
    tall = barricade(rows=64, boards=(6, 32))
    city[2], city[3] = tall[:32], tall[32:]
    jungle = {0: spikes(), 1: crate(), 2: crate(), 3: crate(), 4: crate()}
    holes = {0: pothole(), 1: river()}

    L = ['`timescale 1ns / 1ps',
         '// AUTO-GENERATED by tools/gen_sprites.py -- do not edit by hand.',
         '// Obstacle sprites, 32x32, 3 bits per pixel (0 = transparent).',
         '//   theme 0 = Panama City: 0 cone, 1 barricade, 2/3 tall barricade top/bottom, 4 barricade (no lamp)',
         '//   theme 1 = jungle:      0 metal spikes, 1-4 wooden crate',
         'module sprite_rom(',
         '\tinput        theme,',
         '\tinput  [2:0] id,',
         '\tinput  [4:0] row,     // 0 = top',
         '\tinput  [4:0] col,     // 0 = left',
         '\toutput [2:0] px',
         '\t);',
         '\treg [95:0] bits;',
         '\talways @(*) begin',
         '\t\tcase ({theme, id, row})']
    for th, sp in ((0, city), (1, jungle)):
        for sid in sorted(sp):
            for r in range(32):
                if sp[sid][r].any():
                    L.append(f"\t\t\t{{1'b{th}, 3'd{sid}, 5'd{r}}}: bits = {to_vhex(sp[sid][r], 3)};")
    L += ["\t\t\tdefault: bits = 96'd0;", '\t\tendcase', '\tend',
          "\tassign px = bits[col * 3 +: 3];", 'endmodule', '']
    open(os.path.join(ROOT, 'src', 'sprite_rom.v'), 'w').write('\n'.join(L))

    L = ['`timescale 1ns / 1ps',
         '// AUTO-GENERATED by tools/gen_sprites.py -- do not edit by hand.',
         '// Floor overlay for a hole tile, 64 wide x 80 tall (the whole floor depth),',
         '// starting at the left edge of the hole tile. 2 bits per pixel, 0 = transparent.',
         '//   theme 0: pothole (1 black, 2 rim, 3 cracks)   theme 1: river (1 water, 2 ripple, 3 foam)',
         'module hole_rom(',
         '\tinput        theme,',
         '\tinput  [6:0] row,     // 0..79 below the floor line',
         '\tinput  [5:0] col,     // 0..63',
         '\toutput [1:0] px',
         '\t);',
         '\treg [127:0] bits;',
         '\talways @(*) begin',
         '\t\tcase ({theme, row})']
    for th in (0, 1):
        for r in range(80):
            if holes[th][r].any():
                L.append(f"\t\t\t{{1'b{th}, 7'd{r}}}: bits = {to_vhex(holes[th][r], 2)};")
    L += ["\t\t\tdefault: bits = 128'd0;", '\t\tendcase', '\tend',
          "\tassign px = bits[{col, 1'b0} +: 2];", 'endmodule', '']
    open(os.path.join(ROOT, 'src', 'hole_rom.v'), 'w').write('\n'.join(L))

    # preview
    def rgb(pal, idx, bg):
        return tuple(int(pal[idx][k], 16) * 17 for k in range(3)) if idx else bg
    tiles = [(city, CITY_PAL, (200, 240, 230)), (jungle, JUNGLE_PAL, (245, 190, 110))]
    img = Image.new('RGB', (6 * 40 + 70, 2 * 72 + 90), (40, 40, 40))
    for row, (sp, pal, bg) in enumerate(tiles):
        for k, sid in enumerate((0, 1, 4)):
            for y in range(32):
                for x in range(32):
                    img.putpixel((8 + k * 40 + x, 8 + row * 72 + 32 + y), rgb(pal, sp[sid][y, x], bg))
        for y in range(64):                         # tall
            for x in range(32):
                v = (sp[2] if y < 32 else sp[3])[y % 32, x]
                img.putpixel((8 + 3 * 40 + x, 8 + row * 72 + y), rgb(pal, v, bg))
    for th, pal, bg in ((0, CITY_HOLE_PAL, (220, 60, 0)), (1, JUNGLE_HOLE_PAL, (120, 75, 40))):
        for y in range(80):
            for x in range(64):
                img.putpixel((8 + 4 * 40 + th * 70 + x, 150 + y), rgb(pal, holes[th][y, x], bg))
    img = img.resize((img.width * 3, img.height * 3), Image.NEAREST)
    img.save(os.path.join(ROOT, 'docs', 'sprites.png'))
    print('wrote src/sprite_rom.v, src/hole_rom.v, docs/sprites.png')


if __name__ == '__main__':
    main()
