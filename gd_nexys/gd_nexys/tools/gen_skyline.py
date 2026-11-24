#!/usr/bin/env python3
"""
Turns a flat-colour skyline picture into src/skyline_rom.v: two parallax layers
plus a cloud sprite, all as combinational (LUT) ROMs, the same way the level and
font ROMs work.

    python3 tools/gen_skyline.py [assets/skyline.png]

What it does
  1. Snaps every pixel to the picture's flat colours (anti-aliased edges and faint
     watermarks are given to the neighbouring flat colour).
  2. Finds the repeat period of the picture and a seam column where the loop
     joins invisibly, then keeps exactly one period, so it can scroll forever.
  3. Splits it into two depth layers by colour:
        back  = the two lightest building colours (far towers)
        front = the two darkest colours (near towers, palms, ground, plane)
     Where a back building is hidden behind a front one, it is extended
     downwards ("drip fill") so nothing looks cut when the layers slide apart.
  4. Writes src/skyline_rom.v and a preview PNG in docs/.
"""
import os
import sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
LONG_GAP = 14     # px: back-coloured gaps under a front building longer than this get filled
ROOT = os.path.join(HERE, '..')


def palette_of(rgb, n=5, merge=14):
    """The n most common flat colours (similar shades merged)."""
    cols, counts = np.unique(rgb.reshape(-1, 3), axis=0, return_counts=True)
    order = np.argsort(-counts)
    pal = []
    for i in order:
        c = cols[i].astype(int)
        if all(np.abs(c - p).sum() > merge * 3 for p in pal):
            pal.append(c)
        if len(pal) == n:
            break
    return np.array(pal)


def classify(rgb, pal, pure=14):
    d = np.sqrt(((rgb[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(-1))
    lab = d.argmin(-1)
    ok = d.min(-1) < pure
    lab = np.where(ok, lab, -1)
    H, W = lab.shape
    for _ in range(12):                        # fill edge pixels from flat neighbours
        if (lab >= 0).all():
            break
        pad = np.pad(lab, 1, constant_values=-1)
        votes = np.zeros((H, W, len(pal)), int)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                nb = pad[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]
                for k in range(len(pal)):
                    votes[:, :, k] += (nb == k)
        fill = (lab < 0) & (votes.max(-1) > 0)
        lab = np.where(fill, votes.argmax(-1), lab)
    lab[lab < 0] = d.argmin(-1)[lab < 0]
    return lab


def find_loop(lab, sky):
    H, W = lab.shape
    best = None
    for p in range(W // 4, W - 40):
        m = (lab[:, :W - p] == lab[:, p:]).mean()
        if best is None or m > best[0]:
            best = (m, p)
    score, p = best
    if score < 0.6:
        return 0, W                              # no repeat: loop the whole picture
    eq = np.array([(lab[:, x] == lab[:, x + p]).mean() for x in range(W - p)])
    skyfrac = (lab == sky).mean(0)
    cands = [x for x in range(W - p) if eq[x] == 1.0]
    x0 = max(cands, key=lambda x: skyfrac[x]) if cands else int(eq.argmax())
    return x0, p


def build(path):
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(int)
    pal = palette_of(rgb)
    lum = pal @ np.array([0.299, 0.587, 0.114])
    order = np.argsort(-lum)                     # lightest first
    sky, back_ids, front_ids = order[0], list(order[1:3]), list(order[3:5])
    lab = classify(rgb, pal)
    x0, p = find_loop(lab, sky)
    tile = lab[:, x0:x0 + p]
    rows = np.where((tile != sky).any(1))[0]
    tile = tile[rows.min():rows.max() + 1]
    H, W = tile.shape

    back = np.zeros((H, W), int)                 # 0 none, 1/2 = back colours
    front = np.zeros((H, W), int)                # 0 none, 1/2 = front colours
    for x in range(W):
        cur_b = 0
        for y in range(H):
            v = tile[y, x]
            if v in back_ids:
                cur_b = 1 + back_ids.index(v)
                back[y, x] = cur_b
            elif v in front_ids:
                front[y, x] = 1 + front_ids.index(v)
                back[y, x] = cur_b               # drip fill behind front buildings
            else:
                cur_b = 0
        # A front building whose base is hidden by a (back-coloured) building would
        # float once the layers slide apart: extend it down through long back-coloured
        # gaps. Short gaps (e.g. the notches of the twisted tower) are kept.
        y = 0
        while y < H:
            if front[y, x] and y + 1 < H and front[y + 1, x] == 0 and tile[y + 1, x] in back_ids:
                y2 = y + 1
                while y2 < H and tile[y2, x] in back_ids:
                    y2 += 1
                if y2 - (y + 1) > LONG_GAP or y2 == H or tile[y2, x] == sky:
                    front[y + 1:y2, x] = front[y, x]
                y = y2
            else:
                y += 1
    back = despeckle(back)
    front = despeckle(front)
    cols = {'sky': pal[sky], 'back': [pal[i] for i in back_ids], 'front': [pal[i] for i in front_ids]}
    return back, front, cols, (x0, p)


def despeckle(layer, min_px=6):
    """Remove tiny islands (stray anti-aliasing / watermark specks)."""
    H, W = layer.shape
    seen = np.zeros_like(layer, bool)
    out = layer.copy()
    for y0 in range(H):
        for x0 in range(W):
            if layer[y0, x0] == 0 or seen[y0, x0]:
                continue
            stack, comp = [(y0, x0)], []
            seen[y0, x0] = True
            while stack:
                y, x = stack.pop()
                comp.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    yy, xx = y + dy, (x + dx) % W          # the tile wraps horizontally
                    if 0 <= yy < H and layer[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
            if len(comp) < min_px:
                for y, x in comp:
                    out[y, x] = 0
    return out


def to12(c):
    return ''.join('%X' % min(15, int(round(v / 17))) for v in c)


def cloud_shapes():
    """Two fluffy 64x24 cloud bitmaps: 1 = body, 2 = shaded underside."""
    out = []
    for blobs in ([(14, 15, 8), (26, 10, 10), (40, 12, 9), (51, 16, 7)],
                  [(12, 16, 7), (22, 12, 8), (33, 9, 9), (44, 13, 8), (54, 17, 6)]):
        m = np.zeros((24, 64), int)
        yy, xx = np.mgrid[0:24, 0:64]
        for cx, cy, r in blobs:
            m[(xx - cx) ** 2 + (yy - cy) ** 2 <= r * r] = 1
        m[(yy >= 16) & (yy <= 22) & (xx >= blobs[0][0]) & (xx <= blobs[-1][0])] = 1
        m[23, :] = 0
        shade = (m == 1) & (yy >= 19)
        m[shade] = 2
        out.append(m)
    return out


def verilog(back, front, cols, loop, src_name):
    from layer_rom import emit_layer_rom
    H, W = back.shape
    hdr = ['AUTO-GENERATED by tools/gen_skyline.py from ' + src_name + ' -- do not edit by hand.',
           f'Panama City skyline: one seamless period, {W} x {H} px (source columns {loop[0]}..{loop[0] + W - 1}).',
           'Two layers, 2 bits per pixel: 0 = transparent, 1/2 = the layer colours below.',
           f"  back  colours: 1 = 12'h{to12(cols['back'][0])}, 2 = 12'h{to12(cols['back'][1])}",
           f"  front colours: 1 = 12'h{to12(cols['front'][0])}, 2 = 12'h{to12(cols['front'][1])}"]
    txt = emit_layer_rom('skyline_rom', back, front, 2, 2, hdr)
    txt += '\n' + cloud_verilog()
    return txt, W, H


def cloud_verilog():
    L = ['// Two 64x24 cloud sprites: 0 = none, 1 = body, 2 = shaded underside.',
         'module cloud_rom(',
         '\tinput        shape,',
         '\tinput  [4:0] row,      // 0..23',
         '\tinput  [5:0] col,      // 0..63',
         '\toutput [1:0] px',
         '\t);',
         '\treg [127:0] bits;',
         '\talways @(*) begin',
         '\t\tcase ({shape, row})']
    for s, m in enumerate(cloud_shapes()):
        for y in range(24):
            v = 0
            for x in range(63, -1, -1):
                v = (v << 2) | int(m[y, x])
            if v:
                L.append(f"\t\t\t{{1'b{s}, 5'd{y}}}: bits = 128'h{v:032X};")
    L += ["\t\t\tdefault: bits = 128'd0;", '\t\tendcase', '\tend',
          "\tassign px = bits[{col, 1'b0} +: 2];", 'endmodule', '']
    return '\n'.join(L)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'assets', 'skyline.png')
    back, front, cols, loop = build(src)
    txt, W, H = verilog(back, front, cols, loop, os.path.basename(src))
    out = os.path.join(ROOT, 'src', 'skyline_rom.v')
    open(out, 'w').write(txt)
    # preview of the two layers (back on top, front below, composite at the bottom)
    sky = np.array(cols['sky']); bp = [sky] + cols['back']; fp = [sky] + cols['front']
    comp = np.where(front[..., None] > 0, np.array(fp)[front], np.array(bp)[back])
    prev = np.concatenate([np.array(bp)[back], np.array(fp)[front], comp]).astype(np.uint8)
    os.makedirs(os.path.join(ROOT, 'docs'), exist_ok=True)
    Image.fromarray(prev).resize((W * 2, prev.shape[0] * 2), Image.NEAREST).save(
        os.path.join(ROOT, 'docs', 'skyline_layers.png'))
    print(f'wrote src/skyline_rom.v: tile {W} x {H}, loop from source x={loop[0]}, '
          f"back={[to12(c) for c in cols['back']]} front={[to12(c) for c in cols['front']]} sky={to12(cols['sky'])}")


if __name__ == '__main__':
    main()
