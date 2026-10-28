#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-netease.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Services/Music/NeteaseMusicPolicy.swift" \
  "$ROOT/scripts/NeteasePolicyProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
xcrun swiftc -typecheck -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Services/Music/NeteaseMusicPolicy.swift" \
  "$ROOT/Sapphire/Services/Music/NeteaseMusicBridge.swift"
