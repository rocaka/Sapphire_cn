#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-notch-sizing.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Notch/NotchSizeReportPolicy.swift" \
  "$ROOT/scripts/NotchSizingProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/Notch/WidgetLayoutPolicy.swift" \
  "$ROOT/Sapphire/Notch/NotchWidgetRow.swift" \
  "$ROOT/Sapphire/Widgets/Weather/WeatherWidgetView.swift" \
  "$ROOT/Sapphire/Widgets/MusicPlayer/MusicPlayerNotice.swift" \
  "$ROOT/scripts/WidgetLayoutRenderProbe.swift" -o "$TEMP_DIR/render-probe"
"$TEMP_DIR/render-probe" "${LAYOUT_RENDER_DIR:-$TEMP_DIR/renders}"
