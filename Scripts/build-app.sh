#!/bin/bash
#
# Builds Quack.app from the SwiftPM executable and assembles a proper macOS
# agent app bundle (LSUIElement). Works with Command Line Tools only — no full
# Xcode required.
#
# Usage:
#   Scripts/build-app.sh                 # debug build, ad-hoc signed
#   CONFIG=release Scripts/build-app.sh  # release build
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" Scripts/build-app.sh
#
# With a Developer ID, the result is hardened-runtime signed and ready for
# `notarytool` + `stapler` (see README for the full notarization recipe).

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
APP_NAME="Quack"
BUNDLE_ID="com.quack.menubar"
BUILD_DIR=".build/${CONFIG}"
APP_DIR="build/${APP_NAME}.app"
# Prefer the stable local self-signed identity (so TCC grants persist across
# rebuilds). Falls back to ad-hoc. Override with SIGN_ID=... for a Developer ID.
if [ -z "${SIGN_ID:-}" ]; then
    if security find-certificate -c "Quack Local Signing" >/dev/null 2>&1; then
        SIGN_ID="Quack Local Signing"
    else
        SIGN_ID="-"
    fi
fi

echo "▸ Building Quack (${CONFIG})…"
swift build -c "${CONFIG}" --product "${APP_NAME}"

echo "▸ Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Vendored MediaRemoteAdapter: copy its dynamic lib + resource bundle so the
# perl adapter can locate run.pl (Bundle.module) and the dylib
# (Bundle(for:).executablePath) at runtime.
FW_DIR="${APP_DIR}/Contents/Frameworks"
mkdir -p "${FW_DIR}"
# The SwiftPM build products live in ${BUILD_DIR}; names may be
# libMediaRemoteAdapter.dylib and MediaRemoteAdapter_MediaRemoteAdapter.bundle.
for artifact in "${BUILD_DIR}"/libMediaRemoteAdapter.dylib \
                "${BUILD_DIR}"/MediaRemoteAdapter_MediaRemoteAdapter.bundle \
                "${BUILD_DIR}"/*MediaRemoteAdapter*.bundle; do
    [ -e "$artifact" ] && cp -R "$artifact" "${FW_DIR}/" 2>/dev/null || true
done
echo "▸ Bundled MediaRemoteAdapter artifacts into ${FW_DIR}"

cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
    echo "⚠︎ Resources/AppIcon.icns missing — run Scripts/make-icon.sh"
fi
[ -f "Resources/quack.mp3" ] && cp "Resources/quack.mp3" "${APP_DIR}/Contents/Resources/quack.mp3"

echo "▸ Signing (identity: ${SIGN_ID})…"
if [ "${SIGN_ID}" = "-" ]; then
    # Ad-hoc: runs locally but identity changes every build (TCC grants reset).
    codesign --force --deep --sign - \
        --entitlements "Resources/Quack.entitlements" \
        "${APP_DIR}"
elif [ "${SIGN_ID}" = "Quack Local Signing" ]; then
    # Stable local identity: no hardened runtime / timestamp (those are for
    # Developer ID and would restrict the event taps). Grants persist.
    # The dedicated signing keychain re-locks / drops from the search list after
    # a reboot, which makes codesign fail with errSecInternalComponent — so
    # unlock and re-arm it first.
    KC="$HOME/Library/Keychains/quack-signing.keychain-db"
    if [ -f "$KC" ]; then
        security unlock-keychain -p quack "$KC" 2>/dev/null || true
        EXISTING="$(security list-keychains -d user | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//')"
        echo "$EXISTING" | grep -q quack-signing || security list-keychains -d user -s "$KC" $EXISTING
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k quack "$KC" >/dev/null 2>&1 || true
    fi
    codesign --force --sign "${SIGN_ID}" \
        --entitlements "Resources/Quack.entitlements" \
        "${APP_DIR}"
else
    # Developer ID for distribution.
    codesign --force --options runtime --timestamp \
        --entitlements "Resources/Quack.entitlements" \
        --sign "${SIGN_ID}" \
        "${APP_DIR}"
fi

echo "✓ Built ${APP_DIR}"
echo "  Run with: open ${APP_DIR}"
