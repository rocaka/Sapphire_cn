#!/bin/bash
set -euo pipefail
# Integration checks need macOS pasteboard/media services in a normal user
# session. Clipboard fixtures use independent names, never the general board.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/test-pasteboard-representations.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-media.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Stubs/PublicFeatureAvailability.swift" \
  "$ROOT/Sapphire/Stubs/PublicTextRecognition.swift" \
  "$ROOT/Sapphire/Stubs/PublicMediaOptimizer.swift" \
  "$ROOT/Sapphire/Stubs/PublicPasteboardRepresentations.swift" \
  "$ROOT/Sapphire/Stubs/PublicMediaClipboardImage.swift" \
  "$ROOT/scripts/MediaOptimizerProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
