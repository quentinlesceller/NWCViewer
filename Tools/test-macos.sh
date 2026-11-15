#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Tools/test_localizations.py
xcodebuild -project NWCViewer.xcodeproj -scheme NWCViewer \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData test
