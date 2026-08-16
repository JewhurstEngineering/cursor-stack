#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

CONFIGURATION="${1:-Release}"
DERIVED="$ROOT/build"

xcodebuild \
  -scheme CursorStack \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  build

APP="$DERIVED/Build/Products/$CONFIGURATION/CursorStack.app"
echo "Built $APP"
echo
echo "This app is unsandboxed on purpose (Accessibility window control)."
echo "To notarize with your Developer ID:"
echo "  1. codesign --deep --force --options runtime --sign \"Developer ID Application: James Jewhurst (6998422DKP)\" \"$APP\""
echo "  2. ditto -c -k --keepParent \"$APP\" /tmp/CursorStack.zip"
echo "  3. xcrun notarytool submit /tmp/CursorStack.zip --keychain-profile \"notary\" --wait"
echo "  4. xcrun stapler staple \"$APP\""
