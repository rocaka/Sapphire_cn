#!/bin/bash
# Build the public checkout and sign nested code from the inside out.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-cn}"
CONFIGURATION="${CONFIGURATION:-Release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
cd "$ROOT"
mkdir -p "$BUILD_DIR"
xcodebuild -project Sapphire.xcodeproj -scheme Sapphire \
  -configuration "$CONFIGURATION" -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build
APP="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/Sapphire.app"
python3 "$ROOT/scripts/sign-cn.py" "$APP" "$SIGNING_IDENTITY"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/Sapphire-CN.zip"
shasum -a 256 "$BUILD_DIR/Sapphire-CN.zip" > "$BUILD_DIR/Sapphire-CN.zip.sha256"
echo "Build ready: $BUILD_DIR/Sapphire-CN.zip"
if [[ "$SIGNING_IDENTITY" == '-' ]]; then
  echo 'Ad-hoc signed: no Apple notarization; the privileged root helper remains unavailable.'
fi
