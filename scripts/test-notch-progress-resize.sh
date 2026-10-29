#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-progress-resize.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
# Run the controller method itself, not a copied decision table. Synthetic
# geometry/effect adapters avoid displaying or controlling the user's desktop.
python3 - "$ROOT" "$TEMP_DIR/ResizeHarness.swift" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / 'Sapphire/Notch/NotchController.swift').read_text()
start = source.index('    private func updateAutoContentSize()')
end = source.index('\n    private func updateMouseEventHandling(', start)
method = source[start:end].replace('    private func ', '    func ', 1)
fixture = '''import Foundation
import CoreGraphics
@MainActor final class ResizeHarness {
    struct Manager { var currentActivity: ActivityType = .notification }
    final class Scratch {
        var activitySwitchBlurWindowEnd = Date.distantPast
        var blurRemovalTask: Task<Void, Never>?
    }
    var config: ResizeConfiguration? = ResizeConfiguration()
    var notchState = ResizeState.autoExpanded
    var isLiveActivityActive = true
    var activeScaleFactor: CGFloat = 1
    var measuredAutoContentSize = CGSize(width: 553, height: 32)
    var animatedWidth: CGFloat = 180
    var animatedHeight: CGFloat = 32
    var reduceMotion = false
    var liveActivityManager = Manager()
    let scratch = Scratch()
    let effects = ResizeEffects()
'''
Path(sys.argv[2]).write_text(fixture + method + '\n}\n')
PY
xcrun swiftc -module-cache-path "$TEMP_DIR/cache" \
  "$ROOT/Sapphire/LiveActivities/ActivityType.swift" \
  "$TEMP_DIR/ResizeHarness.swift" \
  "$ROOT/scripts/NotchProgressResizeProbe.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
