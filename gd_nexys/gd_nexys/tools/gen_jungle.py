#!/usr/bin/env python3
"""
Turns the jungle pixel-art picture into src/jungle_rom.v (level 2 background).

    python3 tools/gen_jungle.py [assets/jungle.jpg]

The picture is pixel art drawn on a 4x4-pixel grid (520x360 -> 130x90 art pixels).
  1. Finds the grid and takes the centre of every 4x4 block -> clean art pixels,
     no JPEG blur.
  2. Removes the sky (the renderer draws its own matching orange gradient and clouds)
     and the ground strip at the bottom (the renderer draws its own grass and dirt).
  3. Reduces the rest to 15 colours (4-bit index, 0 = transparent).
  4. Splits it into two depth layers, like the city skyline:
       front = the big palms (anchored on their brown trunks), the dark distant
               palm silhouettes and the bushes along the ground
       back  = the mountains. Where palms covered them, the ridge line is joined up
               and the hidden part is filled from the nearest visible mountain colour,
               so nothing looks cut out when the palms slide past.
  5. Writes a ROM of 130 columns x BAND rows per layer. The renderer draws every art
     pixel as a 4x4 block and mirrors the picture (130 -> 260 columns) so it loops.
Also writes docs/jungle_layers.png (back, front, together, and slid apart).
"""
import os
import sys
from collections import deque
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SCALE = 4            # art pixel size in the source picture (and on screen)
TOP, BOTTOM = 35, 82  # art-pixel rows kept: mountain tops .. dark line above the grass


def native(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(float)
    H, W, _ = a.shape
    best = None
    for oy in range(SCALE):                          # grid phase with the flattest blocks
        for ox in range(SCALE):
            v = np.mean([a[y:y + SCALE, x:x + SCALE].reshape(-1, 3).var(0).sum()
                         for y in range(oy, H - SCALE + 1, SCALE)
                         for x in range(ox, W - SCALE + 1, SCALE)])
            if best is None or v < best[0]:
                best = (v, ox, oy)
    _, ox, oy = best
    c0, c1 = SCALE // 2 - 1, SCALE // 2 + 1          # centre of each block
    return np.array([[np.median(a[y + c0:y + c1, x + c0:x + c1].reshape(-1, 3), 0)
                      for x in range(ox, W - SCALE + 1, SCALE)]
                     for y in range(oy, H - SCALE + 1, SCALE)])


def split_layers(idx, pal):
    """idx: art-pixel colour indices (0 = sky). Returns (back, front) index arrays."""
    H, W = idx.shape
    lum = np.r_[999, pal @ np.array([0.299, 0.587, 0.114])]
    L, sky = lum[idx], idx == 0
    # local texture: how often a pixel differs from its neighbours (5x5 average)
    pad = np.pad(idx, 1, mode='edge')
    diff = sum(((pad[1 + dy:1 + dy + H, 1 + dx:1 + dx + W] != idx) &
                (pad[1 + dy:1 + dy + H, 1 + dx:1 + dx + W] != 0)).astype(float)
               for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0))) / 4
    p2 = np.pad(diff, 2, mode='wrap')
    tex = sum(p2[2 + dy:2 + dy + H, 2 + dx:2 + dx + W]
              for dy in range(-2, 3) for dx in range(-2, 3)) / 25
    trunk = idx == int(np.argmin(np.abs(pal - [92, 65, 20]).sum(1))) + 1   # brown trunks
    # vegetation = dark & busy (or very dark, or trunk), grown from trunks, distant
    # palm silhouettes and the bush strip
    cand = ((~sky) & (L < 80) & ((tex >= 0.3) | (L < 50))) | trunk
    anch = trunk | ((L < 40) & ~sky)
    anch[H - 9:, :] |= ~sky[H - 9:, :]
    front = anch.copy()
    q = deque(zip(*np.where(anch)))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < H and 0 <= xx < W and not front[yy, xx] and cand[yy, xx]:
                front[yy, xx] = True
                q.append((yy, xx))
    for _ in range(3):                                   # absorb leaf highlights, drop specks
        pf = np.pad(front.astype(int), 1, mode='edge')
        pn = np.pad((~sky).astype(int), 1, mode='edge')
        vf = sum(pf[1 + dy:1 + dy + H, 1 + dx:1 + dx + W] for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        vn = sum(pn[1 + dy:1 + dy + H, 1 + dx:1 + dx + W] for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        front = ((vf * 2 > vn) & ~sky) | trunk
        front[H - 9:, :] |= ~sky[H - 9:, :]
    seen = np.zeros_like(front)                          # drop tiny floating bits of leaf
    for y0, x0 in zip(*np.where(front)):
        if seen[y0, x0]:
            continue
        comp, q = [], deque([(y0, x0)])
        seen[y0, x0] = True
        while q:
            y, x = q.popleft()
            comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < H and 0 <= xx < W and front[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    q.append((yy, xx))
        if len(comp) < 4:
            for y, x in comp:
                front[y, x] = False
    back_vis = (~sky) & ~front
    # mountain ridge: visible ridge points, joined up across the parts the palms hide
    ridge = np.full(W, -1)
    for x in range(W):
        ys = np.where(back_vis[:, x])[0]
        if len(ys) and (ys.min() == 0 or sky[ys.min() - 1, x]):
            ridge[x] = ys.min()
    known = np.where(ridge >= 0)[0]
    rid = np.interp(np.arange(W), known, ridge[known]).round().astype(int)
    for x in range(W):
        ys = np.where(back_vis[:, x])[0]
        if len(ys):
            rid[x] = min(rid[x], ys.min())
    src = back_vis & (L >= 80)                          # fill only from real mountain colours
    sy, sx = np.where(src)
    back = np.zeros((H, W), int)
    for y in range(H):
        for x in range(W):
            if y < rid[x]:
                continue
            if back_vis[y, x]:
                back[y, x] = idx[y, x]
            else:
                d = (sy - y) ** 2 + ((sx - x) * 0.7) ** 2
                back[y, x] = idx[sy[d.argmin()], sx[d.argmin()]]
    return back, np.where(front, idx, 0)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'assets', 'jungle.jpg')
    nat = native(src)
    r, g, b = nat[..., 0], nat[..., 1], nat[..., 2]
    sky = ((r > 200) & (r - g > 25) & (b < 170)) | ((r > 225) & (g > 200))   # orange sky, cream clouds
    band = nat[TOP:BOTTOM + 1]
    sky = sky[TOP:BOTTOM + 1]
    H, W = sky.shape
    veg = Image.fromarray(band[~sky].astype(np.uint8).reshape(1, -1, 3))
    q = veg.quantize(colors=15, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = np.array(q.getpalette()[:45]).reshape(-1, 3).astype(int)
    idx = ((band[:, :, None, :] - pal[None, None]) ** 2).sum(-1).argmin(-1) + 1
    idx[sky] = 0
    hexpal = [''.join('%X' % min(15, round(c / 17)) for c in p) for p in pal]

    back, front = split_layers(idx, pal)

    def rows(layer, name, y):
        v = 0
        for x in range(W - 1, -1, -1):
            v = (v << 4) | int(layer[y, x])
        return f"\t\t\t6'd{y}: {name} = {4 * W}'h{v:0{W}X};"
    L = ['`timescale 1ns / 1ps',
         '// AUTO-GENERATED by tools/gen_jungle.py from ' + os.path.basename(src) + ' -- do not edit by hand.',
         f'// Panama jungle background: {W} x {H} art pixels per layer, drawn 4x4 on screen and',
         '// mirrored by the renderer into a seamless loop. 4-bit colour index, 0 = see-through.',
         '//   back  = mountains (rebuilt behind the palms)',
         '//   front = big palms, distant palm silhouettes, bushes',
         'module jungle_rom(',
         f'\tinput  [5:0] row,          // 0..{H - 1}',
         f'\tinput  [7:0] col_back,     // 0..{W - 1}',
         f'\tinput  [7:0] col_front,    // 0..{W - 1}',
         '\toutput        back_op,',
         '\toutput [11:0] back_color,',
         '\toutput        front_op,',
         '\toutput [11:0] front_color',
         '\t);',
         f'\treg [{4 * W - 1}:0] back_row, front_row;',
         '\talways @(*) begin',
         '\t\tcase (row)']
    L += [rows(back, 'back_row', y) for y in range(H)]
    L += [f"\t\t\tdefault: back_row = {4 * W}'d0;", '\t\tendcase', '\tend',
          '\talways @(*) begin', '\t\tcase (row)']
    L += [rows(front, 'front_row', y) for y in range(H)]
    L += [f"\t\t\tdefault: front_row = {4 * W}'d0;", '\t\tendcase', '\tend',
          '\twire [3:0] ib = back_row[col_back * 4 +: 4];',
          '\twire [3:0] i_f = front_row[col_front * 4 +: 4];',
          "\tassign back_op  = (ib  != 4'd0);",
          "\tassign front_op = (i_f != 4'd0);",
          '\tassign back_color  = pal(ib);',
          '\tassign front_color = pal(i_f);',
          '\tfunction [11:0] pal(input [3:0] i);',
          '\t\tcase (i)']
    for k, hx in enumerate(hexpal, 1):
        L.append(f"\t\t\t4'd{k}: pal = 12'h{hx};")
    L += ["\t\t\tdefault: pal = 12'h000;", '\t\tendcase', '\tendfunction', 'endmodule', '']
    open(os.path.join(ROOT, 'src', 'jungle_rom.v'), 'w').write('\n'.join(L))

    # preview: back, front, together, and slid apart by 22 and 55 art pixels
    def rgb(ix):
        im = np.zeros(ix.shape + (3,), np.uint8)
        im[:] = (255, 176, 80)
        for k, hx in enumerate(hexpal, 1):
            im[ix == k] = [int(c, 16) * 17 for c in hx]
        return im

    def comp(sh):
        f = np.roll(front, sh, 1)
        return np.where((f > 0)[..., None], rgb(f), rgb(back))
    gap = np.zeros((2, W, 3), np.uint8)
    prev = np.concatenate([rgb(back), gap, rgb(front), gap, comp(0), gap, comp(22), gap, comp(55)])
    Image.fromarray(prev).resize((W * SCALE, prev.shape[0] * SCALE), Image.NEAREST).save(
        os.path.join(ROOT, 'docs', 'jungle_layers.png'))
    print(f'wrote src/jungle_rom.v: 2 layers of {W} x {H} art pixels ({W * SCALE} x {H * SCALE} on screen), palette {hexpal}')


if __name__ == '__main__':
    main()
