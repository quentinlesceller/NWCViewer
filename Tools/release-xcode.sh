#!/bin/bash
# Use the account already signed in to Xcode. Signing secrets stay in Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${SIGN_IDENTITY:?Set your Developer ID Application identity}"
: "${TEAM_ID:?Set your Apple developer team ID}"
export BUNDLE_ID="${BUNDLE_ID:-com.quentinlesceller.nwcviewer}"
bash Tools/test-macos.sh
mkdir -p dist
RELEASE_DIR="$(mktemp -d "$ROOT/dist/NWCViewer-XXXXXX")"
# Keep signing operations outside cloud-synced folders.
ARCHIVE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/NWCViewer-archive.XXXXXX")"
ARCHIVE="$ARCHIVE_DIR/NWCViewer.xcarchive"
printf 'Archive: %s\n' "$ARCHIVE"
xcodebuild -project NWCViewer.xcodeproj -scheme NWCViewer -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  -derivedDataPath build/ReleaseDerivedData ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" archive
APP="$ARCHIVE/Products/Applications/NWC Viewer.app"
lipo "$APP/Contents/MacOS/NWC Viewer" -verify_arch arm64
lipo "$APP/Contents/MacOS/NWC Viewer" -verify_arch x86_64
lipo "$APP/Contents/Helpers/nwc2xml" -verify_arch arm64
lipo "$APP/Contents/Helpers/nwc2xml" -verify_arch x86_64
# iCloud Drive may attach Finder metadata after Xcode archives the bundle.
# Remove only metadata disallowed by codesign; preserve other attributes.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
bash Tools/sign-app.sh "$APP"
python3 - "$RELEASE_DIR/export-options.plist" "$TEAM_ID" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump(dict(method='developer-id',destination='upload',signingStyle='manual',signingCertificate='Developer ID Application',teamID=sys.argv[2]),f)
PY
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$RELEASE_DIR/export-options.plist" -exportPath "$RELEASE_DIR/upload" -allowProvisioningUpdates
# Apple may still be processing. Every failed check is retained for diagnosis.
for attempt in $(seq 1 60); do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$RELEASE_DIR/notarized" > "$RELEASE_DIR/export-notarized.log" 2>&1; then
    ditto "$RELEASE_DIR/notarized/NWC Viewer.app" "$RELEASE_DIR/NWC Viewer.app"
    xcrun stapler staple "$RELEASE_DIR/NWC Viewer.app"
    RELEASE_DIR="$RELEASE_DIR" bash Tools/package-release.sh
    exit 0
  fi
  echo "Waiting for notarization (check $attempt of 60)."
  sleep 20
done
cat "$RELEASE_DIR/export-notarized.log" >&2
exit 1
