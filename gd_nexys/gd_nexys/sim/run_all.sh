#!/usr/bin/env bash
# Full regression: lint, game-logic test vs. Python model, whole-chip test, frame renders.
# Needs: iverilog, verilator (optional), python3 + Pillow. Run from the project root:
#   bash sim/run_all.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p sim/out

echo "== regenerate ROMs + winning jump schedules"
python3 tools/gen_roms.py

if command -v verilator >/dev/null; then
  echo "== verilator lint"
  verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-BLKSEQ --top-module vga_top src/*.v \
    && echo "lint clean"
fi

echo "== tb_game_sm (FSM + physics, replays a winning run of all 3 levels)"
iverilog -g2005 -o sim/out/tb_game_sm.vvp sim/tb_game_sm.v src/game_sm.v src/level_rom.v
vvp -n sim/out/tb_game_sm.vvp | grep -E "PASS|FAIL|INFO"
python3 tools/check_trace.py

echo "== tb_top (whole chip: VGA timing, debouncers, tick, SSD, VGA capture) ~1 min"
iverilog -g2005 -o sim/out/tb_top.vvp sim/tb_top.v src/*.v
vvp -n sim/out/tb_top.vvp | grep -E "^ok|PASS|FAIL|SSD shows"

echo "== render frames for every screen ~40 s"
python3 tools/make_frames.py
