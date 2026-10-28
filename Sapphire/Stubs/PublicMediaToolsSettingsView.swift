#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaOptimizerSettingsView: View {
    @EditingSettings var settings: SettingsEditingSession
    @State private var text = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Local Text Recognition").font(.title2.bold())
            Text("Extract text from images and PDFs on this Mac. Scanned PDF pages use local OCR; files are not uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show text recognition on the file shelf", isOn: $settings.settings.mediaToolsShowShelfActions)
            HStack {
                Button("Choose Image or PDF…", action: chooseFile).disabled(isWorking)
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Copy Text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }.disabled(text.isEmpty || isWorking)
            }
            if let error { Text(error).foregroundStyle(.secondary) }
            TextEditor(text: $text).font(.body).frame(minHeight: 240)
        }.padding(25)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isWorking = true
            error = nil
            Task { @MainActor in
                let result = await MediaOptimizerManager.shared.recognizeText(in: url)
                isWorking = false
                if let result, !result.isEmpty { text = result }
                else { error = L10n.string("No readable text was found. Check the file and any PDF password protection.") }
            }
        }
    }
}
#endif
