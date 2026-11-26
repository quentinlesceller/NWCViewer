#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
: "${RELEASE_DIR:?Set RELEASE_DIR to the folder containing the notarized app}"
# Stage outside iCloud Drive, which can attach FinderInfo to app bundles.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/NWCViewer-share.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/NWC Viewer.app"
ditto --norsrc --noextattr "$RELEASE_DIR/NWC Viewer.app" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
# GPL corresponding source accompanies the binary. Allowlist project paths so
# developer secrets, Keychains, build products and .git are never packaged.
python3 - "$ROOT" "$RELEASE_DIR" <<'PY'
from pathlib import Path
import sys, zipfile
root, output = map(Path, sys.argv[1:])
allowed = ['iPad', 'Converter', 'App', 'Resources', 'Vendor', 'Tests', 'Tools', 'Updates', '.github',
           'NWCViewer.xcodeproj', 'README.md', 'RELEASE.md', 'LICENSE', '.gitignore']
with zipfile.ZipFile(output/'NWCViewer-Source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in allowed:
        path = root/name
        for file in sorted(path.rglob('*')) if path.is_dir() else [path]:
            if not file.is_file() or file.is_symlink(): continue
            if any(part in ('__pycache__', 'xcuserdata') for part in file.relative_to(root).parts): continue
            if file.suffix in ('.o', '.xcuserstate'): continue
            if file == root/'Converter/score-reader': continue
            archive.write(file, Path('NWCViewer')/file.relative_to(root))
PY
cat > "$RELEASE_DIR/Read Me.txt" <<'TEXT'
NWC Viewer — requires macOS 13 or later

Unzip this download. Drag NWC Viewer into Applications, then open it.
Click Open NWC File to choose a score. Use Print or Save PDF as needed. Use Fit Width to fit the score to your window.
Updates download automatically and install when you quit. Preferences are in NWC Viewer → Settings.
The interface follows your Mac’s language: English, French, Spanish, German, or Italian.

To change the app language, open System Settings → General → Language & Region → Applications.

Supports binary NWC versions 1.30–2.1 and 2.75. Some notation is unsupported; layout may differ.

NWCViewer-Source.zip contains the corresponding source code and licenses
under GNU GPL v2. Keep it with this distribution when sharing the app.
TEXT
# Include only the stapled app, instructions and source in the parents' download.
cp "$RELEASE_DIR/NWCViewer-Source.zip" "$RELEASE_DIR/Read Me.txt" "$STAGING/"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
SHARE="$RELEASE_DIR/NWCViewer-$VERSION-macOS.zip"
ditto --norsrc --noextattr -c -k "$STAGING" "$SHARE"
rm -rf "$STAGING"
printf '\nReady to share: %s\nTest the signed app on your Mac before sending it.\n' "$SHARE"

RELEASE_DIR="$RELEASE_DIR" bash Tools/prepare-update.sh
