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
python3 - "$APP/Contents/Info.plist" <<'PY'
import os, plistlib, re, subprocess, sys
from pathlib import Path
path = Path(sys.argv[1])
with path.open('rb') as stream:
    info = plistlib.load(stream)
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
if not re.fullmatch(r'[0-9a-f]{40,64}', revision):
    raise SystemExit('Invalid build source revision')
info['SapphireSourceRevision'] = revision
import datetime
version = os.environ.get('RELEASE_VERSION', '')
if not version:
    version = datetime.datetime.now(datetime.timezone.utc).strftime('%Y.%m%d') + '.' + os.environ.get('GITHUB_RUN_NUMBER', '1')
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){2}', version):
    raise SystemExit('Release version must be numeric: YYYY.MMDD.build')
info['CFBundleShortVersionString'] = version
info['SapphireReleaseVersion'] = version
run_number = os.environ.get('GITHUB_RUN_NUMBER', '')
if run_number.isascii() and run_number.isdigit():
    info['SapphireBuildNumber'] = run_number
with path.open('wb') as stream:
    plistlib.dump(info, stream)
# Embedded extensions must advertise the same marketing version as the host.
for extension in path.parent.parent.rglob('*.appex'):
    metadata = extension / 'Contents' / 'Info.plist'
    if not metadata.is_file():
        continue
    with metadata.open('rb') as stream:
        child = plistlib.load(stream)
    if str(child.get('CFBundleIdentifier', '')).startswith('com.rocaka.sapphirecn.'):
        child['CFBundleShortVersionString'] = version
        with metadata.open('wb') as stream:
            plistlib.dump(child, stream)
PY
test -f "$APP/Contents/Resources/zh-Hans.lproj/Localizable.strings"
test -f "$APP/Contents/Resources/en.lproj/Localizable.strings"
/usr/bin/lipo -archs "$APP/Contents/MacOS/Sapphire"
# Strip before signing. Keep exported symbols/runtime metadata and save dSYMs
# separately in CI, so smaller user packages remain diagnosable.
/usr/bin/strip -S -x "$APP/Contents/MacOS/Sapphire"
python3 "$ROOT/scripts/sign-cn.py" "$APP" "$SIGNING_IDENTITY"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/Sapphire-CN.zip"
(cd "$BUILD_DIR" && shasum -a 256 Sapphire-CN.zip > Sapphire-CN.zip.sha256)
echo "Build ready: $BUILD_DIR/Sapphire-CN.zip"
if [[ "$SIGNING_IDENTITY" == '-' ]]; then
  echo 'Ad-hoc signed: no Apple notarization; the privileged root helper remains unavailable.'
fi
