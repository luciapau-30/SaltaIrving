"""Shared writer for two-layer background ROMs (skyline_rom.v, jungle_rom.v)."""


def emit_layer_rom(name, back, front, bpp_back, bpp_front, header_lines):
    """back/front: 2-D int arrays (rows x W) of colour indices, 0 = transparent.
    Every row is stored as one wide constant; the pixel is picked with a part-select.
    Outputs are always 3 bits wide so the renderer can treat every theme the same."""
    H, W = back.shape

    def rowhex(layer, y, bpp):
        v = 0
        for x in range(W - 1, -1, -1):
            v = (v << bpp) | int(layer[y, x])
        return f"{bpp * W}'h{v:0{(bpp * W + 3) // 4}X}"

    L = ['`timescale 1ns / 1ps'] + ['// ' + h for h in header_lines] + [
        f'module {name}(',
        '\tinput  [7:0] row,          // 0 = top of the band',
        '\tinput  [9:0] col_back,     // 0..W-1, already wrapped',
        '\tinput  [9:0] col_front,',
        '\toutput [2:0] back,',
        '\toutput [2:0] front',
        '\t);',
        f'\treg [{bpp_back * W - 1}:0] back_row;',
        f'\treg [{bpp_front * W - 1}:0] front_row;',
        '\talways @(*) begin',
        '\t\tcase (row)']
    for y in range(H):
        if back[y].any():
            L.append(f"\t\t\t8'd{y}: back_row = {rowhex(back, y, bpp_back)};")
    L += [f"\t\t\tdefault: back_row = {bpp_back * W}'d0;", '\t\tendcase', '\tend',
          '\talways @(*) begin', '\t\tcase (row)']
    for y in range(H):
        if front[y].any():
            L.append(f"\t\t\t8'd{y}: front_row = {rowhex(front, y, bpp_front)};")
    L += [f"\t\t\tdefault: front_row = {bpp_front * W}'d0;", '\t\tendcase', '\tend']

    def sel(layer, bpp):
        idx = f"{{col_{layer}, 1'b0}}" if bpp == 2 else f"col_{layer} * {bpp}"
        return f"{layer}_row[{idx} +: {bpp}]"
    for layer, bpp in (('back', bpp_back), ('front', bpp_front)):
        pad = 3 - bpp
        rhs = sel(layer, bpp) if pad == 0 else f"{{{pad}'b0, {sel(layer, bpp)}}}"
        L.append(f'\tassign {layer} = {rhs};')
    L += ['endmodule', '']
    return '\n'.join(L)
