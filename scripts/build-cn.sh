#!/bin/bash
# Build the public checkout and sign nested code from the inside out.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-cn}"
CONFIGURATION="${CONFIGURATION:-Release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
cd "$ROOT"
mkdir -p "$BUILD_DIR"
# Keep Release optimizations while compiling files in parallel. Whole-module
# optimization on this large public target made feedback cycles excessively long.
XCODE_ARGS=(CODE_SIGNING_ALLOWED=NO SWIFT_COMPILATION_MODE=singlefile)
if [[ -n "${BUILD_ARCHS:-}" ]]; then
  XCODE_ARGS+=("ARCHS=$BUILD_ARCHS")
fi
if [[ "$CONFIGURATION" == 'Debug' ]]; then
  XCODE_ARGS+=(SWIFT_OPTIMIZATION_LEVEL=-Onone SWIFT_COMPILATION_MODE=singlefile)
fi
xcodebuild -project Sapphire.xcodeproj -scheme Sapphire \
  -configuration "$CONFIGURATION" -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  "${XCODE_ARGS[@]}" build
APP="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/Sapphire.app"
test -f "$APP/Contents/Resources/zh-Hans.lproj/Localizable.strings"
test -f "$APP/Contents/Resources/en.lproj/Localizable.strings"
/usr/bin/lipo -archs "$APP/Contents/MacOS/Sapphire"
python3 "$ROOT/scripts/sign-cn.py" "$APP" "$SIGNING_IDENTITY"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/Sapphire-CN.zip"
(cd "$BUILD_DIR" && shasum -a 256 Sapphire-CN.zip > Sapphire-CN.zip.sha256)
echo "Build ready: $BUILD_DIR/Sapphire-CN.zip"
if [[ "$SIGNING_IDENTITY" == '-' ]]; then
  echo 'Ad-hoc signed: no Apple notarization; the privileged root helper remains unavailable.'
fi
