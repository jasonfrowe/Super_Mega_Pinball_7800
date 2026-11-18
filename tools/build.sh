#!/bin/sh
# Build Super Mega Pinball 7800: generate the table, sprites and music,
# assemble with dasm, sign, and wrap in an .a78 header (48K, POKEYs at
# $0450 and $0440, AstroCart math unit).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BAS="$ROOT/tools/7800basic"
mkdir -p "$ROOT/build"
rm -f "$ROOT/build/pinball.bin"
python3 "$ROOT/tools/sprites.py"
python3 "$ROOT/tools/table.py"
python3 "$ROOT/tools/music.py"
cd "$ROOT"
wasmtime run --dir=. "$BAS/dasm.wasm" src/main.asm -Isrc -f3 -obuild/pinball.bin -lbuild/pinball.lst -sbuild/pinball.sym > build/dasm.log 2>&1 || true
if ! [ -s build/pinball.bin ] || grep -q -i -E "error|unresolved|not found" build/dasm.log; then
    grep -v "^ *$" build/dasm.log | tail -30; echo "ASSEMBLY FAILED"; exit 1
fi
# dasm writes from the first ORG ($4000): 48K
SIZE=$(wc -c < "$ROOT/build/pinball.bin" | tr -d ' ')
[ "$SIZE" = 49152 ] || { echo "ROM is $SIZE bytes, expected 49152"; exit 1; }
(cd "$ROOT/build" && wasmtime run --dir=. "$BAS/7800sign.wasm" -w pinball.bin > /dev/null)
python3 "$ROOT/tools/a78header.py" "$ROOT/build/pinball.bin" "$ROOT/build/pinball.a78"
grep -E "^ *(code at|free)" "$ROOT/build/dasm.log" || true
python3 "$ROOT/tools/romfree.py" "$ROOT/build/pinball.sym" || true
