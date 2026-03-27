#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
xcodebuild -project AnnotateMac.xcodeproj -scheme AnnotateMac -configuration Release build
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Release/AnnotateMac.app' | tail -1)
if [[ -z "${APP_PATH:-}" ]]; then
  echo "Release app not found" >&2
  exit 1
fi
rm -rf dist/AnnotateMac.app
cp -R "$APP_PATH" dist/AnnotateMac.app
echo "Built app copied to: dist/AnnotateMac.app"
