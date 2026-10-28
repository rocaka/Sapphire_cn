#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-features.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Stubs/PublicFeatureAvailability.swift" \
  "$ROOT/scripts/PublicFeaturesProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
