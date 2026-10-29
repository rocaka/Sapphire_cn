#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-music-appearance.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Models/MusicPlayerAppearance.swift" \
  "$ROOT/scripts/MusicPlayerAppearanceProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
# Typecheck and execute the real pure configuration from the lock-screen source
# without constructing login-window services or displaying any windows.
python3 - "$ROOT" "$TEMP_DIR/LockScreenConfiguration.swift" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / "Sapphire/Services/LockScreen/LockScreenManager.swift").read_text()
Path(sys.argv[2]).write_text(source.split("private final class UnfocusableWindow:", 1)[0])
PY
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Models/MusicPlayerAppearance.swift" \
  "$ROOT/Sapphire/Notch/NotchWidgetRow.swift" \
  "$TEMP_DIR/LockScreenConfiguration.swift" \
  "$ROOT/scripts/MusicPlayerLockScreenProbe.swift" -o "$TEMP_DIR/lockscreen-probe"
"$TEMP_DIR/lockscreen-probe"
