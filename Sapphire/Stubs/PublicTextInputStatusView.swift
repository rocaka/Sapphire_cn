#if !SAPPHIRE_FULL_BUILD
import SwiftUI

@MainActor
struct PublicTextInputStatusView: View {
    enum Kind { case finder, snippets }
    let kind: Kind
    @ObservedObject private var finder = FinderCutPasteManager.shared
    @ObservedObject private var snippets = SnippetManager.shared

    var body: some View {
        let message = kind == .finder ? finder.status : snippets.status
        let active = kind == .finder ? finder.isActive : snippets.isActive
        Group {
            if let message {
                Text(L10n.string(message))
            } else if active {
                Label(L10n.string(kind == .finder ? "Finder cut and paste is active." : "Text snippet expansion is active."), systemImage: "checkmark.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
#endif
