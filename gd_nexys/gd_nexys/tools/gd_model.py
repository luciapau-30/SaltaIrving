"""
Bit-exact Python model of the Geometry Dash game logic in src/game_sm.v.

Used for three things:
  1. Designing levels (the level strings below are the single source of truth).
  2. Proving every level is beatable: a solver searches for a jump schedule.
  3. Producing per-frame jump stimulus that sim/tb_game_sm.v replays through the
     RTL, so the hardware and this model are checked against each other.

Coordinates
  - The world scrolls left; `scroll` is the world x shown at screen x = 0.
  - The runner is a 32x32 square at fixed screen x = RX.
  - `h` is the height of the runner's bottom edge above the floor (pixels).
  - The world is a row of 32-px tiles, one character per tile.

Tile characters
  '.' empty        '^' floor spike        '#' block (32 tall)
  'H' block (64)   'A' block 32 with a spike on top
"""
import sys

# ---- constants (must match localparams in game_sm.v / vga_bitchange.v) ----
RX = 128            # runner screen x (left edge)
TILE = 32
V0 = 12             # jump take-off speed (px/frame)
G = 1               # gravity (px/frame^2)
VMAX = 12           # terminal fall speed
SNAP = 12           # how far below a block top you can be and still land on it
SPIKE_H = 16        # runner bottom must be >= base+SPIKE_H over a spike's core
FINISH_SCROLL = 7168  # level is cleared once scroll reaches this (bar = scroll>>4 = 448 px)
SPEED = {1: 4, 2: 5, 3: 6}   # px per frame for levels 1..3

EMPTY, SPIKE, B32, B64, SPB = 0, 1, 2, 3, 4
CHAR2KIND = {'.': EMPTY, '^': SPIKE, '#': B32, 'H': B64, 'A': SPB}


def _lvl(*parts):
    s = ''.join(parts)
    return s


# ---------------------------------------------------------------------------
# Levels. Tile index 0 is world x 0..31. The runner starts over tile 4.
# Keep content below tile ~222 (the finish line is at world x 7328 = tile 229).
# ---------------------------------------------------------------------------
LEVELS = {
    # Level 1 - speed 4: single/double spikes, blocks, a small staircase
    1: _lvl(
        '.' * 24,
        '^', '.' * 10,
        '^', '.' * 10,
        '#', '.' * 10,
        '^^', '.' * 10,
        '###', '.' * 9,
        '^', '.' * 6, '^', '.' * 9,
        '#H', '.' * 10,
        '^^', '.' * 8,
        '##..##', '.' * 9,
        '^', '.' * 5, '^^', '.' * 9,
        '###H###', '.' * 9,
        '#', '.' * 6, '^', '.' * 9,
        '^^', '.' * 7, '#', '.' * 8,
        '^', '.' * 4, '^', '.' * 4, '^',
    ),
    # Level 2 - speed 5: block runs with gaps, spikes on blocks, longer chains
    2: _lvl(
        '.' * 24,
        '^^', '.' * 9,
        '#.#.#', '.' * 8,
        '^', '.' * 5, '^^', '.' * 8,
        '####A####', '.' * 8,
        '#H', '.' * 3, 'H#', '.' * 8,
        '^^', '.' * 7, '^^', '.' * 8,
        '###^^###', '.' * 8,
        '#', '.' * 5, '^', '.' * 5, '#', '.' * 8,
        '###A####A###', '.' * 8,
        '^^', '.' * 6, '#H', '.' * 8,
        '^', '.' * 5, '^', '.' * 5, '^^', '.' * 6,
    ),
    # Level 3 - speed 6: triple spikes, tall stairs, spike-topped runs
    3: _lvl(
        '.' * 24,
        '^^^', '.' * 9,
        '#H#', '.' * 8,
        '^^', '.' * 5, '^^^', '.' * 8,
        '###A#####A###', '.' * 8,
        '#H', '.' * 6, '#H', '.' * 6, '#H', '.' * 7,
        '^^^', '.' * 7, '#', '.' * 6,
        '###^^####^^###', '.' * 8,
        'A', '.' * 7, 'A', '.' * 8,
        '^^', '.' * 6, '^^', '.' * 7, '^^^', '.' * 8,
        '###A###HH###A###', '.' * 7,
        '^^^',
    ),
}


def tiles_of(level):
    s = LEVELS[level]
    if len(s) > 222:
        raise ValueError(f'level {level} is {len(s)} tiles; keep it <= 222')
    return {i: CHAR2KIND[c] for i, c in enumerate(s) if CHAR2KIND[c] != EMPTY}


def block_top(k):
    return 32 if k in (B32, SPB) else 64 if k == B64 else 0


def sense(tiles, scroll, h):
    """Combinational 'sense' logic of game_sm.v: returns (hit, support)."""
    wx0 = (scroll + RX) & 0x1FFF
    wa = (wx0 + 2) & 0x1FFF
    wb = (wx0 + 29) & 0x1FFF
    hit = False
    support = 0
    for t in ((wa >> 5) & 0xFF, (wb >> 5) & 0xFF):
        k = tiles.get(t, EMPTY)
        if k in (B32, B64, SPB):
            tp = block_top(k)
            if h + SNAP >= tp:
                support = max(support, tp)
            else:
                hit = True              # ran into the side of a block
        if k in (SPIKE, SPB):
            sl = t * 32 + 10
            sr = t * 32 + 21
            if wx0 + 4 <= sr and wx0 + 27 >= sl:
                base = 0 if k == SPIKE else 32
                if h < base + SPIKE_H:
                    hit = True
    return hit, support


def step(tiles, speed, scroll, h, v, jump):
    """One PLAY tick. Returns ('crash'|'clear'|'run', scroll, h, v)."""
    hit, support = sense(tiles, scroll, h)
    if hit:
        return 'crash', scroll, h, v
    if scroll >= FINISH_SCROLL:
        return 'clear', scroll, h, v
    scroll = scroll + speed
    if h <= support:                    # on the ground / on a block
        if jump:
            h, v = support + V0, V0 - G
        else:
            h, v = support, 0
    else:                               # in the air
        ht = h + v
        if ht <= support:
            h, v = support, 0
        else:
            h, v = ht, max(v - G, -VMAX)
    return 'run', scroll, h, v


def grounded(tiles, scroll, h):
    return h <= sense(tiles, scroll, h)[1]


def solve(level):
    """Find a per-frame jump schedule that clears `level` (None if impossible)."""
    tiles = tiles_of(level)
    speed = SPEED[level]
    sys.setrecursionlimit(20000)
    memo = {}

    def win(frame, scroll, h, v):
        key = (frame, h, v)
        if key in memo:
            return memo[key]
        memo[key] = None
        on_ground = grounded(tiles, scroll, h)
        for j in ((0, 1) if on_ground else (0,)):
            r, s2, h2, v2 = step(tiles, speed, scroll, h, v, j)
            if r == 'clear':
                memo[key] = [j]
                return memo[key]
            if r == 'run':
                rest = win(frame + 1, s2, h2, v2)
                if rest is not None:
                    memo[key] = [j] + rest
                    return memo[key]
        return None

    return win(0, 0, 0, 0), memo


def windows(level, schedule):
    """For each jump in the schedule, how many take-off frames would also work."""
    tiles = tiles_of(level)
    speed = SPEED[level]
    _, memo = solve(level)
    # replay and, at every take-off, try shifting it earlier/later
    out = []
    scroll, h, v = 0, 0, 0
    frame = 0
    states = []
    for j in schedule:
        states.append((frame, scroll, h, v, j))
        _, scroll, h, v = step(tiles, speed, scroll, h, v, j)
        frame += 1
    for idx, (f, s, hh, vv, j) in enumerate(states):
        if not j:
            continue
        ok = 0
        for delta in range(-12, 13):
            g = idx + delta
            if g < 0 or g >= len(states):
                continue
            # rewind to frame g, hold off until the shifted take-off, then free play
            f2, s2, h2, v2, _ = states[g] if delta <= 0 else states[idx]
            if delta > 0:
                # delay: stay grounded for `delta` frames from the original take-off
                good = True
                for _ in range(delta):
                    if not grounded(tiles, s2, h2):
                        good = False
                        break
                    r, s2, h2, v2 = step(tiles, speed, s2, h2, v2, 0)
                    if r != 'run':
                        good = False
                        break
                if not good or not grounded(tiles, s2, h2):
                    continue
            else:
                if not grounded(tiles, s2, h2):
                    continue
            r, s3, h3, v3 = step(tiles, speed, s2, h2, v2, 1)
            if r != 'run':
                continue
            if _can_win(tiles, speed, s3, h3, v3):
                ok += 1
        out.append((f, s + RX, ok))
    return out


def _can_win(tiles, speed, scroll, h, v, _cache={}):
    key = (speed, frozenset(tiles.items()), scroll, h, v)
    if key in _cache:
        return _cache[key]
    _cache[key] = False
    on_ground = grounded(tiles, scroll, h)
    res = False
    for j in ((0, 1) if on_ground else (0,)):
        r, s2, h2, v2 = step(tiles, speed, scroll, h, v, j)
        if r == 'clear' or (r == 'run' and _can_win(tiles, speed, s2, h2, v2)):
            res = True
            break
    _cache[key] = res
    return res


if __name__ == '__main__':
    for lv in (1, 2, 3):
        sched, _ = solve(lv)
        if sched is None:
            print(f'level {lv}: NOT BEATABLE')
            continue
        w = windows(lv, sched)
        print(f'level {lv}: {len(LEVELS[lv])} tiles, cleared in {len(sched)} frames '
              f'({len(sched)/60:.1f} s), {sum(sched)} take-offs, '
              f'tightest timing window = {min(x[2] for x in w)} frames')
        tight = sorted(w, key=lambda x: x[2])[:4]
        print('   tightest jumps (frame, world_x, window):', tight)
