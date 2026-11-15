#!/bin/bash
# Prepare a signed Sparkle archive/feed. Does not publish anything.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_DIR:?Set RELEASE_DIR to the notarized release directory}"
SPARKLE_BIN="${SPARKLE_BIN:-$PWD/build/ReleaseDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}"
ACCOUNT='com.quentinlesceller.nwcviewer.sparkle'
APP="$RELEASE_DIR/NWC Viewer.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
EXPECTED=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")
ACTUAL=$("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p)
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo 'The local Sparkle signing key does not match this app.' >&2; exit 1
fi
mkdir -p "$RELEASE_DIR/updates"
UPDATE="$RELEASE_DIR/updates/NWCViewer-$VERSION-update.zip"
ditto --norsrc --noextattr -c -k --keepParent "$APP" "$UPDATE"
if [[ -f Updates/appcast.xml ]]; then cp Updates/appcast.xml "$RELEASE_DIR/updates/appcast.xml"; fi
"$SPARKLE_BIN/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/quentinlesceller/NWCViewer/releases/download/v$VERSION/" \
  --link 'https://github.com/quentinlesceller/NWCViewer/releases' "$RELEASE_DIR/updates"
python3 Tools/check-update.py "$RELEASE_DIR/updates" --info-plist "$APP/Contents/Info.plist"
printf 'Signed update and feed: %s/updates\n' "$RELEASE_DIR"
