#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-appearance-policy.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
python3 - "$ROOT" "$TEMP_DIR" <<'PY'
from pathlib import Path
import sys
root,temp=map(Path,sys.argv[1:])
s=(root/'Sapphire/Models/ShortcutModels.swift').read_text().split('// MARK: - Codable Conformance',1)[0]
probe='''
@main struct Probe {static func main() {
 let a=CodableColor(color:.red); let b=CodableColor(cgColor:a.cgColor)
 precondition(a.id != b.id && a == b)
 precondition(a.hashValue == b.hashValue && Set([a,b]).count == 1)
 print("Color equality/hash contract passed across distinct view identities")
}}
'''
(temp/'Color.swift').write_text(s+probe)
s=(root/'Sapphire/App Settings/SettingsPanes.swift').read_text()
wrapper=s[s.index('struct NotchAppearanceEditorView:'):s.index('private struct NotchAppearanceControlsView:')]
fixtures='''import SwiftUI
struct NotchAppearanceSettings: Equatable { var opacity:Double=1 }
struct NotchAppearanceControlsView:View {
 @Binding var appearance:NotchAppearanceSettings
 let title:String
 var body:some View {EmptyView()}
}
'''
components=(root/'Sapphire/App Settings/SettingsComponents.swift').read_text()
sliders=components[components.index('struct CustomSliderRowView:'):components.index('struct SettingsContainerModifier:')]
(temp/'Editor.swift').write_text(fixtures+wrapper+sliders)
PY
xcrun swiftc -parse-as-library -module-cache-path "$TEMP_DIR/cache" "$TEMP_DIR/Color.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
xcrun swiftc -typecheck -module-cache-path "$TEMP_DIR/cache" "$TEMP_DIR/Editor.swift"
