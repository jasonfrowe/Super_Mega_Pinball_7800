#!/bin/sh
# Publish the web player to kona (jasonrowe.org/Atari7800/pinball/): builds
# build/site with tools/web/site.sh, then copies it over ssh. Only pinball/
# and the Atari7800 landing page are replaced; other games there are left alone.
#   tools/web/deploy.sh            (HOST=kona DEST=/var/www/html/Atari7800 by default)
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOST=${HOST:-kona}
DEST=${DEST:-/var/www/html/Atari7800}

"$ROOT/tools/web/site.sh" "$ROOT/build/site"
rsync -rlpt --delete "$ROOT/build/site/" "$HOST:$DEST/pinball/"
rsync -rlpt "$ROOT/web/atari7800/index.html" "$HOST:$DEST/index.html"
echo "published to $HOST:$DEST/pinball/"
