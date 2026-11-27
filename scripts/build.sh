#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

xcodebuild \
  -project SelectionTranslator.xcodeproj \
  -scheme SelectionTranslator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  build

APP="$ROOT/build/DerivedData/Build/Products/Debug/SelectionTranslator.app"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "No Apple Development identity found; falling back to ad-hoc signing."
fi
codesign --force --deep --sign "$IDENTITY" "$APP"
echo "Built and signed: $APP"
echo "Identity: $IDENTITY"
