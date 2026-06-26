#!/bin/bash
#
# Packages build/Quack.app into a drag-to-Applications DMG.
# Run Scripts/build-app.sh (or install.sh) first to produce build/Quack.app.
#
# For sharing with others without Gatekeeper warnings, sign with a Developer ID
# (SIGN_ID in build-app.sh) and notarize — see README.

set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Quack.app"
DMG="build/Quack.dmg"
STAGE="build/dmg-stage"

[ -d "$APP" ] || { echo "Missing $APP — run Scripts/build-app.sh first."; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Quack" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "✓ Built $DMG"
