#!/bin/bash
# Derive an Apple Silicon package from an already verified community build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${1:?Usage: package-arm64-cn.sh /path/Sapphire.app /path/new-output-directory}"
OUTPUT_DIR="${2:?Specify a new output directory}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
python3 - "$SOURCE_APP" "$OUTPUT_DIR" <<'PY'
import plistlib, subprocess, sys
from pathlib import Path
source, output = map(lambda p: Path(p).resolve(), sys.argv[1:])
info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
if source.suffix != '.app' or info.get('CFBundleIdentifier') != 'com.rocaka.sapphirecn':
    raise SystemExit('Expected a Sapphire CN application bundle')
if source == output or source in output.parents or output in source.parents:
    raise SystemExit('Output must be separate from the source bundle')
architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(source / 'Contents/MacOS/Sapphire')], text=True).split()
if not {'arm64', 'x86_64'}.issubset(architectures):
    raise SystemExit('Expected a universal source executable')
if output.exists() and any(output.iterdir()):
    raise SystemExit('Output directory must be empty; refusing to replace existing files')
PY
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"
mkdir -p "$OUTPUT_DIR"
APP="$OUTPUT_DIR/Sapphire.app"
/usr/bin/ditto "$SOURCE_APP" "$APP"
/usr/bin/lipo "$APP/Contents/MacOS/Sapphire" -thin arm64 -output "$OUTPUT_DIR/Sapphire.arm64"
chmod 755 "$OUTPUT_DIR/Sapphire.arm64"
mv "$OUTPUT_DIR/Sapphire.arm64" "$APP/Contents/MacOS/Sapphire"
python3 "$ROOT/scripts/sign-cn.py" "$APP" "$SIGNING_IDENTITY"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
python3 - "$SOURCE_APP" "$APP" <<'PY'
import plistlib, subprocess, sys
from pathlib import Path
source, app = map(Path, sys.argv[1:])
assert (source/'Contents/Info.plist').read_bytes() == (app/'Contents/Info.plist').read_bytes(), 'Release metadata changed'
architectures = subprocess.check_output(['/usr/bin/lipo','-archs',str(app/'Contents/MacOS/Sapphire')],text=True).split()
assert architectures == ['arm64'], architectures
# Keep the ARM slice UUID, so the original build's dSYM still matches.
source_uuid = subprocess.check_output(['/usr/bin/dwarfdump','--uuid',str(source/'Contents/MacOS/Sapphire')],text=True)
arm_uuid = subprocess.check_output(['/usr/bin/dwarfdump','--uuid',str(app/'Contents/MacOS/Sapphire')],text=True).split()[1]
assert arm_uuid in source_uuid, 'ARM debug UUID changed'
print('Apple Silicon architecture, original release metadata and debug UUID verified')
PY
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_DIR/Sapphire-CN-arm64.zip"
(cd "$OUTPUT_DIR" && shasum -a 256 Sapphire-CN-arm64.zip > Sapphire-CN-arm64.zip.sha256)
echo "Apple Silicon package ready: $OUTPUT_DIR/Sapphire-CN-arm64.zip"
