#!/bin/bash
# Sign from the innermost code outwards, including Sparkle's embedded services.
set -euo pipefail
: "${SIGN_IDENTITY:?Set the Developer ID identity}"
APP="$1"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for code in \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE/Versions/B/Autoupdate" \
  "$SPARKLE/Versions/B/Updater.app" \
  "$SPARKLE" \
  "$APP/Contents/Helpers/nwc2xml" \
  "$APP"; do
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$code"
done
codesign --verify --deep --strict --verbose=2 "$APP"
