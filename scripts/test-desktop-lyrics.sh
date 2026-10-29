#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-desktop-lyrics.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
# Use the real lyric value models without initializing application services.
python3 - "$ROOT" "$TEMP_DIR/LyricModels.swift" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / 'Sapphire/Models/AppModels.swift').read_text()
models = source.split('struct LyricWord:', 1)[1].split('enum LyricsTimeline', 1)[0]
Path(sys.argv[2]).write_text('import Foundation\nstruct LyricWord:' + models)
PY
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Models/MusicPlayerAppearance.swift" \
  "$ROOT/Sapphire/Models/DesktopLyricsAppearance.swift" \
  "$ROOT/Sapphire/Services/Music/DesktopLyricsVisibilityPolicy.swift" \
  "$TEMP_DIR/LyricModels.swift" \
  "$ROOT/Sapphire/Services/Music/LyricsDisplayPolicy.swift" \
  "$ROOT/scripts/DesktopLyricsProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
