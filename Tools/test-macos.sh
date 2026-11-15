#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Keep executable build products outside cloud-synced Documents.
TEST_DERIVED_DATA="${TEST_DERIVED_DATA:-${TMPDIR:-/tmp}/NWCViewer-TestDerivedData}"
python3 Tools/test_localizations.py
xcodebuild -project NWCViewer.xcodeproj -scheme NWCViewer \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$TEST_DERIVED_DATA" test
