#!/bin/bash
set -euo pipefail

# Build a signed appcast for an existing dist archive.
# Usage:
#   SPARKLE_ED_KEY_FILE=~/path/to/ed25519.key ./scripts/appcast.sh 0.4.1
# If SPARKLE_ED_KEY_FILE is unset, the script looks for
# ~/Library/Application Support/SelectionTranslator/Sparkle/ed25519.key,
# then falls back to the Keychain account `selectiontranslator`.
#
# The private key must never be committed. Generate/export it with Sparkle's
# `generate_keys` tool and keep it in Keychain or a 0600 file.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?Usage: scripts/appcast.sh <version>}"
TAG="${TAG:-v$VERSION}"
ZIP="$ROOT/dist/SelectionTranslator-$VERSION.zip"
NOTES="$ROOT/docs/release-notes-$VERSION.md"
KEY="${SPARKLE_ED_KEY_FILE:-$HOME/Library/Application Support/SelectionTranslator/Sparkle/ed25519.key}"

if [ ! -f "$ZIP" ]; then
  echo "Missing $ZIP. Run ./scripts/package.sh first."
  exit 1
fi

WORK="$(mktemp -d /tmp/st-appcast.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
cp "$ZIP" "$WORK/"
[ -f "$NOTES" ] && cp "$NOTES" "$WORK/SelectionTranslator-$VERSION.md"
[ -f "$ROOT/appcast.xml" ] && cp "$ROOT/appcast.xml" "$WORK/"

SIGN_ARGS=()
if [ -f "$KEY" ]; then
  SIGN_ARGS=(--ed-key-file "$KEY")
else
  echo "Private key file not found; using Keychain account selectiontranslator."
  echo "Set SPARKLE_ED_KEY_FILE to the exported key file for reproducible signing."
  SIGN_ARGS=(--account selectiontranslator)
fi

SPARKLE_BIN="${SPARKLE_BIN:-/tmp/sparkle-tools/bin}"
if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "Sparkle tools not found at $SPARKLE_BIN; set SPARKLE_BIN." >&2
  exit 1
fi

"$SPARKLE_BIN/generate_appcast" \
  "${SIGN_ARGS[@]}" \
  --download-url-prefix "https://github.com/Meteorkid/SelectionTranslator/releases/download/$TAG/" \
  "$WORK"

# generate_appcast may not sign when the archived app predates SUPublicEDKey.
# Always sign the enclosure explicitly and inject it if missing.
SIG_LINE="$("$SPARKLE_BIN/sign_update" "${SIGN_ARGS[@]}" "$ZIP" 2>/dev/null || true)"
if [ -n "$SIG_LINE" ]; then
  python3 - "$WORK/appcast.xml" "$VERSION" "$SIG_LINE" <<'PY'
import re, sys
from pathlib import Path
path, version, sig_line = sys.argv[1], sys.argv[2], sys.argv[3]
text = Path(path).read_text()
signature = re.search(r'edSignature="([^"]+)"', sig_line)
length = re.search(r'length="(\d+)"', sig_line)
if not signature or not length:
    raise SystemExit("sign_update did not return a signature")
ref = f"SelectionTranslator-{version}.zip"
# Add the signature only to the enclosure for this version.
pattern = re.compile(r'(<enclosure[^>]*url="[^"]*' + re.escape(ref) + r'"[^>]*?)(\s*/>)')
def add_sig(match):
    head = match.group(1)
    if 'sparkle:edSignature=' in head:
        return match.group(0)
    if 'length="' not in head:
        head += f' length="{length.group(1)}"'
    return head + f' sparkle:edSignature="{signature.group(1)}"' + match.group(2)
text, count = pattern.subn(add_sig, text)
if count == 0:
    raise SystemExit(f"no enclosure found for {ref}")
Path(path).write_text(text)
PY
fi

# Rewrite relative release-note links to the release asset URL.
python3 - "$WORK/appcast.xml" "$VERSION" "$TAG" <<'PY'
import sys
from pathlib import Path
path, version, tag = sys.argv[1], sys.argv[2], sys.argv[3]
text = Path(path).read_text()
text = text.replace(
    f">SelectionTranslator-{version}.md<",
    f">https://github.com/Meteorkid/SelectionTranslator/releases/download/{tag}/SelectionTranslator-{version}.md<",
)
Path(path).write_text(text)
PY

# Sign the feed itself so Sparkle can reject a modified appcast.
"$SPARKLE_BIN/sign_update" "${SIGN_ARGS[@]}" "$WORK/appcast.xml" >/dev/null
"$SPARKLE_BIN/sign_update" "${SIGN_ARGS[@]}" --verify "$WORK/appcast.xml"
cp "$WORK/appcast.xml" "$ROOT/appcast.xml"

echo "Signed appcast written to $ROOT/appcast.xml"
echo "Upload it with:"
echo "  gh release upload $TAG appcast.xml --clobber"
echo "  cp docs/release-notes-$VERSION.md /tmp/SelectionTranslator-$VERSION.md"
echo "  gh release upload $TAG /tmp/SelectionTranslator-$VERSION.md --clobber"
echo "Note: GitHub asset names cannot be renamed with #; upload a copy named SelectionTranslator-$VERSION.md."
