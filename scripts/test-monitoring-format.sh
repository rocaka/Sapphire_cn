#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-monitoring-format.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT
xcrun swiftc -module-cache-path "$PROBE_DIR/module-cache" \
    "$ROOT/Sapphire/Stubs/PublicMonitoringFormat.swift" \
    "$ROOT/scripts/MonitoringFormatProbe.swift" -o "$PROBE_DIR/monitoring-format-probe"
"$PROBE_DIR/monitoring-format-probe"
