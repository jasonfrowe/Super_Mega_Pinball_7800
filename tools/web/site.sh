#!/bin/sh
# Put together the web player: web/ (the page), build/pinball.a78 and the
# js7800_astrocart emulator bundle, in OUT (default build/site).
#   tools/web/site.sh [OUT]
# JS7800 names the js7800_astrocart checkout (default
# ~/Software/FPGA/js7800_astrocart); its bundle is built when missing or older
# than its sources (npm install first in a fresh checkout).
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:-$ROOT/build/site}
JS7800=${JS7800:-$HOME/Software/FPGA/js7800_astrocart}
BUNDLE="$JS7800/dist/js7800.min.js"

[ -s "$ROOT/build/pinball.a78" ] || { echo "no build/pinball.a78: run tools/build.sh"; exit 1; }
[ -d "$JS7800/src/js" ] || { echo "no js7800 checkout at $JS7800 (set JS7800)"; exit 1; }

if [ ! -s "$BUNDLE" ] || [ -n "$(find "$JS7800/src/js" -newer "$BUNDLE" -name '*.js' | head -1)" ]; then
    echo "building the js7800 bundle"
    (cd "$JS7800" &&
     node db/convert.js db/ProSystem.dat > src/js/prosystem/ProSystemDat.js &&
     NODE_OPTIONS=--openssl-legacy-provider npx webpack --mode=production > /dev/null)
fi

rm -rf "$OUT"
mkdir -p "$OUT/js"
cp "$ROOT/web/index.html" "$ROOT/web/play.js" "$ROOT/web/style.css" "$OUT/"
cp "$ROOT/build/pinball.a78" "$OUT/"
cp "$BUNDLE" "$OUT/js/"
cp "$JS7800/LICENSE" "$OUT/js/js7800-LICENSE.txt"
touch "$OUT/.nojekyll"
# Cloudflare caches .js and .css: name this build in their URLs
V=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date +%s)$(git -C "$ROOT" diff --quiet 2>/dev/null || echo "-$(date +%s)")
sed -i.bak -e "s|js/js7800.min.js\"|js/js7800.min.js?v=$V\"|" -e "s|play.js\"|play.js?v=$V\"|" -e "s|style.css\"|style.css?v=$V\"|" "$OUT/index.html"
rm -f "$OUT/index.html.bak"
find "$OUT" -type d -exec chmod 755 {} + && find "$OUT" -type f -exec chmod 644 {} +
echo "site in $OUT"
