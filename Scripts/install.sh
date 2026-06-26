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

# Only reset grants when signing ad-hoc: ad-hoc identity changes every build, so
# old grants go stale. With the stable "Quack Local Signing" identity, grants
# persist across reinstalls — so we must NOT reset them.
if security find-certificate -c "Quack Local Signing" >/dev/null 2>&1; then
    echo "▸ Stable signing identity present — keeping existing permission grants."
else
    echo "▸ Ad-hoc build — clearing stale grants (you'll re-grant). Run Scripts/create-signing-cert.sh to stop this."
    tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true
    tccutil reset Calendar "${BUNDLE_ID}" 2>/dev/null || true
    tccutil reset ListenEvent "${BUNDLE_ID}" 2>/dev/null || true
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
