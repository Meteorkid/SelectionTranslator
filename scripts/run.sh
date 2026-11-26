#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"
open "$ROOT/build/DerivedData/Build/Products/Debug/SelectionTranslator.app"
