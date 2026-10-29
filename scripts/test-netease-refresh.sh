#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-netease-refresh.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Services/Music/NeteaseStateRefreshCoordinator.swift" \
  "$ROOT/scripts/NeteaseRefreshProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
