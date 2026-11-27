#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/build.sh

APP="$ROOT/build/DerivedData/Build/Products/Debug/SelectionTranslator.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DIST="$ROOT/dist"
mkdir -p "$DIST"

ditto -c -k --keepParent "$APP" "$DIST/SelectionTranslator-$VERSION.zip"
zip -qr "$DIST/SelectionTranslator-$VERSION-source.zip" \
  Sources Tests scripts Support project.yml README.md docs browser-extension \
  LICENSE PRIVACY.md appcast.xml \
  -x '*.DS_Store'
echo "Packaged:"
ls -lh "$DIST"
