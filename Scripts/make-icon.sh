#!/bin/bash
#
# Generates Resources/AppIcon.icns from Resources/AppIcon-source.png.
# Run this whenever the source artwork changes; the .icns is committed so a
# normal build doesn't need to regenerate it.

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Resources/AppIcon-source.png"
SET="build/AppIcon.iconset"
OUT="Resources/AppIcon.icns"

[ -f "$SRC" ] || { echo "Missing $SRC"; exit 1; }

rm -rf "$SET"; mkdir -p "$SET"

gen() { sips -z "$1" "$1" "$SRC" --out "$SET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns "$SET" -o "$OUT"
rm -rf "$SET"
echo "✓ Built $OUT"
