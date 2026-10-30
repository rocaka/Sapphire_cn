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
fixtures='''import AppKit
import SwiftUI
extension Notification.Name { static let sapphireSettingsWillClose = Notification.Name("SapphireSettingsWillClose") }
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
# Drive the actual editor in an offscreen host. Register the outer flush first
# so the regression does not depend on SwiftUI notification subscription order.
close_fixtures=fixtures.replace('var body:some View {EmptyView()}', 'var body:some View {Text("Appearance").onReceive(NotificationCenter.default.publisher(for: .probeEdit)) { _ in appearance.opacity=0.5 }}')
close_probe='''
extension Notification.Name { static let probeEdit=Notification.Name("ProbeAppearanceEdit") }
final class Values:ObservableObject {
 @Published var draft=NotchAppearanceSettings()
 var committed=NotchAppearanceSettings()
 func flush() { committed=draft }
}
struct Root:View {
 @ObservedObject var model:Values
 var body:some View {
  NotchAppearanceEditorView(appearance:Binding(get:{model.draft},set:{model.draft=$0}),title:"Probe",flushPendingSettings:{model.flush()})
 }
}
@main struct CloseProbe {
 @MainActor static func main() {
  _=NSApplication.shared
  let model=Values()
  let event:Notification.Name = CommandLine.arguments.contains("--termination") ? NSApplication.willTerminateNotification : .sapphireSettingsWillClose
  let outerFlush=NotificationCenter.default.publisher(for:event).sink { _ in model.flush() }
  let host=NSHostingView(rootView:Root(model:model))
  host.frame=NSRect(x:0,y:0,width:300,height:100)
  host.layoutSubtreeIfNeeded()
  RunLoop.main.run(until:Date(timeIntervalSinceNow:0.05))
  NotificationCenter.default.post(name:.probeEdit,object:nil)
  precondition(model.draft.opacity==1,"Edit must still be local before debounce")
  NotificationCenter.default.post(name:event,object:nil)
  precondition(model.committed.opacity==0.5,"Closing must save the latest local draft immediately")
  outerFlush.cancel()
  withExtendedLifetime(host) {}
  print("Actual appearance editor flush passed:",event.rawValue)
 }
}
'''
(temp/'Close.swift').write_text(close_fixtures+wrapper+close_probe)

PY
xcrun swiftc -parse-as-library -module-cache-path "$TEMP_DIR/cache" "$TEMP_DIR/Color.swift" -o "$TEMP_DIR/probe"
"$TEMP_DIR/probe"
xcrun swiftc -typecheck -module-cache-path "$TEMP_DIR/cache" "$TEMP_DIR/Editor.swift"
xcrun swiftc -O -parse-as-library -module-cache-path "$TEMP_DIR/cache" "$TEMP_DIR/Close.swift" -o "$TEMP_DIR/close-probe"
"$TEMP_DIR/close-probe"
"$TEMP_DIR/close-probe" --termination
