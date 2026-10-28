#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-cn-signing.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT
APP="$PROBE_DIR/Sapphire.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.rocaka.sapphirecn</string><key>CFBundleExecutable</key><string>Sapphire</string><key>CFBundleName</key><string>Sapphire</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
printf '%s\n' 'int main(void) { return 0; }' > "$PROBE_DIR/main.c"
xcrun clang "$PROBE_DIR/main.c" -o "$APP/Contents/MacOS/Sapphire"
cp "$APP/Contents/MacOS/Sapphire" "$APP/Contents/MacOS/com.rocaka.sapphirecnHelper"
# Match Xcode's unsigned output; the helper must be signed before the host.
codesign --remove-signature "$APP/Contents/MacOS/Sapphire"
codesign --remove-signature "$APP/Contents/MacOS/com.rocaka.sapphirecnHelper"
mkdir -p "$APP/Contents/Resources/Probe.bundle/Contents"
printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.example.resources</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>' > "$APP/Contents/Resources/Probe.bundle/Contents/Info.plist"
python3 "$ROOT/scripts/sign-cn.py" "$APP" -
codesign --verify --deep --strict "$APP"
xcrun swiftc -module-cache-path "$PROBE_DIR/module-cache" "$ROOT/Sapphire/Stubs/AppSecurity.swift" "$ROOT/scripts/SigningProbe.swift" -o "$PROBE_DIR/signature-probe"
"$PROBE_DIR/signature-probe" "$APP"

xcrun swiftc -module-cache-path "$PROBE_DIR/module-cache" "$ROOT/Sapphire/Services/Archive/QuarantineAttribute.swift" "$ROOT/scripts/QuarantineProbe.swift" -o "$PROBE_DIR/quarantine-probe"
"$PROBE_DIR/quarantine-probe" "$PROBE_DIR"
