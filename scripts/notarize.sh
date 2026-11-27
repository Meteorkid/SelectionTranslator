#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Debug/SelectionTranslator.app"
ENTITLEMENTS="$ROOT/Support/SelectionTranslator.entitlements"

if [ ! -d "$APP" ]; then
  echo "App not found. Run ./scripts/build.sh first."
  exit 1
fi
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

sign_runtime() {
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$1"
}

# Sparkle ships nested XPC services, Updater.app and Autoupdate. Sign them
# inside-out before re-signing the host app; otherwise notarization fails.
for item in \
  "$SPARKLE/XPCServices/Downloader.xpc" \
  "$SPARKLE/XPCServices/Installer.xpc" \
  "$SPARKLE/Autoupdate" \
  "$SPARKLE/Updater.app" \
  "$SPARKLE/Sparkle"; do
  if [ -e "$item" ]; then
    sign_runtime "$item"
  fi
done

codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEVELOPER_ID_APPLICATION" \
  --identifier com.meteor.SelectionTranslator \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

ZIP="$ROOT/build/SelectionTranslator-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP"
spctl -a -vv "$APP"
echo "Notarized and stapled: $APP"
