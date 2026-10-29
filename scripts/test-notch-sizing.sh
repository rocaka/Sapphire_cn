#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-notch-sizing.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Notch/NotchSizeReportPolicy.swift" \
  "$ROOT/scripts/NotchSizingProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
