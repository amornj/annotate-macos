#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist

# Build with Xcode automatic signing (team 47Y5Z32ZK3 = Apple Development cert)
# This produces stable designated requirements so macOS TCC remembers screen recording permission.
xcodebuild -project AnnotateMac.xcodeproj -scheme AnnotateMac -configuration Release \
  DEVELOPMENT_TEAM=47Y5Z32ZK3 \
  CODE_SIGN_STYLE=Automatic \
  "CODE_SIGN_IDENTITY=Apple Development" \
  PROVISIONING_PROFILE_SPECIFIER="" build

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Release/AnnotateMac.app' | tail -1)
if [[ -z "${APP_PATH:-}" ]]; then
  echo "Release app not found" >&2
  exit 1
fi

rm -rf dist/AnnotateMac.app
cp -R "$APP_PATH" dist/AnnotateMac.app

# Strip quarantine so macOS doesn't treat each copy as a new download
xattr -cr dist/AnnotateMac.app

echo "Built and signed: dist/AnnotateMac.app"
