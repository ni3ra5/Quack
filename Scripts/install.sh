#!/bin/bash
#
# Builds Quack and installs it to /Applications as a proper, runnable app.
#
# Why this matters: macOS ties Accessibility / Calendar permissions to an app's
# bundle identifier *and* code-signature identity at a stable path. Running from
# the build folder, or re-signing ad-hoc on every rebuild, makes those grants
# stop working (macOS may still show Quack as "allowed" while it silently does
# nothing). Installing to a fixed /Applications path and resetting stale TCC
# entries on each install fixes that.
#
# Usage:
#   Scripts/install.sh
#   SIGN_ID="Developer ID Application: You (TEAMID)" Scripts/install.sh

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.quack.menubar"
DEST="/Applications/Quack.app"
FINGERPRINT_FILE="$HOME/Library/Keychains/.quack-signing-fingerprint"

echo "▸ Quitting any running Quack…"
osascript -e 'tell application "Quack" to quit' 2>/dev/null || true
killall Quack 2>/dev/null || true
# Wait for the process to actually exit before overwriting its binary —
# otherwise the running copy is killed with "Code Signature Invalid".
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "Quack.app/Contents/MacOS/Quack" >/dev/null || break
    sleep 0.3
done

echo "▸ Building release bundle…"
CONFIG=release ./Scripts/build-app.sh   # build-app.sh auto-picks the stable identity

echo "▸ Installing to ${DEST}…"
rm -rf "${DEST}"
cp -R "build/Quack.app" "${DEST}"

# TCC grants are keyed to the exact certificate that signed the app, not just
# "is there a stable cert". Ad-hoc signing changes identity every build, so
# those grants always go stale. The "Quack Local Signing" cert is meant to keep
# grants valid across rebuilds — but if that cert itself is ever regenerated
# (fresh keychain, migrated machine, deleted and recreated by
# create-signing-cert.sh), TCC's stored requirement no longer matches the new
# cert and every check silently fails ("Failed to match existing code
# requirement" in tccd's log) even though System Settings still shows the
# toggle on. So compare the cert actually used against the one from last
# install, instead of assuming "exists" means "unchanged".
CURRENT_FINGERPRINT="$(security find-certificate -c "Quack Local Signing" -Z 2>/dev/null | awk '/SHA-256 hash/{print $NF}')"
LAST_FINGERPRINT="$(cat "${FINGERPRINT_FILE}" 2>/dev/null || true)"

if [ -n "${CURRENT_FINGERPRINT}" ] && [ "${CURRENT_FINGERPRINT}" = "${LAST_FINGERPRINT}" ]; then
    echo "▸ Signing identity unchanged since last install — keeping existing permission grants."
else
    echo "▸ Signing identity changed (or first install) — clearing stale grants (you'll re-grant)."
    tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true
    tccutil reset Calendar "${BUNDLE_ID}" 2>/dev/null || true
    tccutil reset ListenEvent "${BUNDLE_ID}" 2>/dev/null || true
    tccutil reset ScreenCapture "${BUNDLE_ID}" 2>/dev/null || true
    [ -n "${CURRENT_FINGERPRINT}" ] && echo "${CURRENT_FINGERPRINT}" > "${FINGERPRINT_FILE}"
fi

echo "▸ Launching…"
open "${DEST}"

cat <<EOF

✓ Installed Quack to ${DEST}

Next steps (one-time, per install):
  1. Click the duck in the menu bar → Settings…
  2. Enable the features you want. When prompted, grant:
       • Calendar       — for meetings & reminders
       • Notifications  — for reminders
       • Accessibility  — for F1/F2 external brightness AND the two-finger swipe
     For Accessibility: System Settings → Privacy & Security → Accessibility,
     toggle "Quack" ON. Quack picks it up automatically (no relaunch needed).

  3. Verify it's working — stream the logs:
       log stream --predicate 'subsystem == "com.quack.menubar"' --level debug

EOF
