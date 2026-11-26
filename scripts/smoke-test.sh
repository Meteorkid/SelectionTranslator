#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Debug/SelectionTranslator.app"
cd "$ROOT"
./scripts/build.sh >/tmp/selectiontranslator-build.log 2>&1

test -d "$APP" || { echo "missing app"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
URL_SCHEME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$APP/Contents/Info.plist")
echo "app version: $VERSION"
echo "url scheme: $URL_SCHEME"
test "$URL_SCHEME" = "selectiontranslator"

grep -q 'document-context-' Sources/SelectionCore/DocumentContextRepository.swift
grep -q 'AnkiConnectService' Sources/SelectionCore/AnkiConnectService.swift
grep -q 'host_permissions' browser-extension/chrome/manifest.json

echo "smoke checks passed"
