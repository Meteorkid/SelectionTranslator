#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

xcodebuild \
  -project SelectionTranslator.xcodeproj \
  -scheme SelectionProbe \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build

"$ROOT/build/DerivedData/Build/Products/Debug/selection-probe"
