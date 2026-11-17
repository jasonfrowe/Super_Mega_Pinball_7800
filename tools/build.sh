#!/bin/sh
# Build Super Mega Pinball 7800 with 7800basic and mark with AstroCart math unit header
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASDIR="$ROOT/tools/7800basic"
WORK="$ROOT/build/work"

# 1. Generate 160A graphics, tilemaps, and assembly tables
python3 "$ROOT/tools/mkgfx.py"

# 2. Setup build directory (flatten asm and gen files for 7800basic inline)
rm -rf "$WORK"
mkdir -p "$WORK" "$ROOT/build"
cp -R "$ROOT/src/." "$WORK/"
cp "$ROOT/src/asm/"*.asm "$WORK/" 2>/dev/null || true
cp "$ROOT/src/gen/"*.asm "$WORK/" 2>/dev/null || true

# 3. Compile with 7800basic
cd "$WORK"
rm -f pinball.bas.bin pinball.bas.a78
bas7800dir="$BASDIR" PATH="$BASDIR:$PATH" sh "$BASDIR/7800basic.sh" pinball.bas > build.log 2>&1 || true

if [ ! -f pinball.bas.a78 ] || grep -q -i -E "Fatal assembly error|Compilation failed" build.log; then
    grep -i -E -B2 -A2 "error|unresolved|failed" build.log | head -40
    echo "BUILD FAILED (see build/work/build.log)"
    exit 1
fi

# 4. Copy outputs and apply AstroCart MathUnit signature
cp pinball.bas.a78 "$ROOT/build/pinball.a78"
cp pinball.bas.bin "$ROOT/build/pinball.bin"
python3 "$ROOT/tools/a78math.py" "$ROOT/build/pinball.a78"

grep -E "bytes of ROM space left|used as zone memory|bytes left in the 7800basic reserved area" build.log || true
echo "SUCCESS: Built build/pinball.a78 (MathUnit enabled)"
