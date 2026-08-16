#!/usr/bin/env bash
# Package the game as an itch.io-ready HTML5 zip.
set -euo pipefail
cd "$(dirname "$0")"
rm -f oaths-and-banners-itch.zip
zip -r oaths-and-banners-itch.zip index.html style.css js/ -x '*.DS_Store'
echo "Built oaths-and-banners-itch.zip — upload this to itch.io as an HTML project."
