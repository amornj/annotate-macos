#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh
mkdir -p dist
DMG_PATH="dist/AnnotateMac.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "AnnotateMac" -srcfolder dist/AnnotateMac.app -ov -format UDZO "$DMG_PATH"
echo "DMG created at: $DMG_PATH"
