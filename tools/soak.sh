#!/bin/sh
# Autoplay soak test: tools/soak.sh [frames] [snap_every]
ROOT=$(cd "$(dirname "$0")/.." && pwd)
A7800=${A7800:-$HOME/Software/a7800/mame64}
OUT=$ROOT/build/soak
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$(dirname "$A7800")"
BOT_OUT="$OUT/bot.txt" BOT_FRAMES=${1:-6000} SNAP_EVERY=${2:-0} "$A7800" a7800 -cart "$ROOT/build/pinball.a78" \
  -video none -sound none -nothrottle -seconds_to_run 3000 -snapshot_directory "$OUT" \
  -autoboot_script "$ROOT/tools/emu/bot.lua" -skip_gameinfo -nomouse > "$OUT/emu.log" 2>&1
cat "$OUT/bot.txt"
