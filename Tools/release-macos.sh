#!/bin/bash
# Build, sign, notarize and package on the developer's Mac. No credentials in source.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This release script requires a Mac with Xcode.' >&2
  exit 1
fi
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool Keychain profile name}"
: "${BUNDLE_ID:?Set BUNDLE_ID to a stable reverse-DNS identifier you control}"
case "$SIGN_IDENTITY" in
  'Developer ID Application: '*) ;;
  *) echo 'Use a Developer ID Application identity (not Apple Development).' >&2; exit 1 ;;
esac
for tool in xcodebuild xcrun codesign ditto lipo spctl python3; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done

# Stop before packaging if native tests fail. No untested release is produced.
Tools/test-macos.sh
xcodebuild -project NWCViewer.xcodeproj -scheme NWCViewer \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/ReleaseDerivedData \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build

mkdir -p dist
RELEASE_DIR="$(mktemp -d "$ROOT/dist/NWCViewer-XXXXXX")"
SIGNING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/NWCViewer-signing.XXXXXX")"
trap 'rm -rf "$SIGNING_DIR"' EXIT
APP="$SIGNING_DIR/NWC Viewer.app"
ditto 'build/ReleaseDerivedData/Build/Products/Release/NWC Viewer.app' "$APP"
HELPER="$APP/Contents/Helpers/nwc2xml"
lipo "$APP/Contents/MacOS/NWC Viewer" -verify_arch arm64
lipo "$APP/Contents/MacOS/NWC Viewer" -verify_arch x86_64
lipo "$HELPER" -verify_arch arm64
lipo "$HELPER" -verify_arch x86_64
# Sign nested code first; do not use --deep as a substitute for signing each item.
# iCloud Drive may attach Finder metadata after Xcode archives the bundle.
# Remove only metadata disallowed by codesign; preserve other attributes.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
bash Tools/sign-app.sh "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

UPLOAD="$RELEASE_DIR/notarization-upload.zip"
ditto -c -k --keepParent "$APP" "$UPLOAD"
xcrun notarytool submit "$UPLOAD" --keychain-profile "$NOTARY_PROFILE" \
  --wait --output-format json > "$RELEASE_DIR/notarization.json"
python3 - "$RELEASE_DIR/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept this submission. See notarization.json; do not share this build.')
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
rm "$UPLOAD"

ditto --norsrc --noextattr "$APP" "$RELEASE_DIR/NWC Viewer.app"
RELEASE_DIR="$RELEASE_DIR" bash Tools/package-release.sh
