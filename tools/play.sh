#!/bin/sh
# Run Super Mega Pinball 7800 in the a7800 emulator fork
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
EMU="${A7800:-$HOME/Software/a7800/mame64}"
ROM="$ROOT/build/pinball.a78"

if [ ! -f "$ROM" ]; then
    "$ROOT/tools/build.sh"
fi

exec "$EMU" a7800 -cart "$ROM" -nomouse "$@"
