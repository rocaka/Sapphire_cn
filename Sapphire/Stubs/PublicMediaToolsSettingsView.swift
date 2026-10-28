#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaOptimizerSettingsView: View {
    @EditingSettings var settings: SettingsEditingSession
    @ObservedObject private var screenOCR = OCRScreenshotMonitor.shared
    @ObservedObject private var shortcutRecorder = GlobalShortcutRecorder.shared
    @State private var text = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Media Tools").font(.title2.bold())
            Text("Extract text from images and PDFs on this Mac. Scanned PDF pages use local OCR; files are not uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show media tools on the file shelf", isOn: $settings.settings.mediaToolsShowShelfActions)
            Text("Optimization creates a new copy. The original stays unchanged; unsupported formats and copies without size savings are reported.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Image Quality").frame(width: 150, alignment: .leading)
                Slider(value: qualityBinding, in: 0.1...1)
            }
            HStack {
                Text("Maximum Image Dimension").frame(width: 150, alignment: .leading)
                Slider(value: dimensionBinding, in: 256...8192, step: 256)
                Text(Int(dimensionBinding.wrappedValue).description).monospacedDigit().frame(width: 50)
            }
            screenCaptureControls
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
            .onChange(of: screenOCR.lastText) { _, value in text = value }
    }

    private var screenCaptureControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable screen OCR shortcut", isOn: $settings.settings.mediaToolsOCRShortcutEnabled)
            HStack {
                Text(KeyboardShortcutHelper.description(for: settings.settings.mediaToolsOCRShortcut.modifiers) + settings.settings.mediaToolsOCRShortcut.key)
                    .font(.caption.monospaced())
                Button(shortcutRecorder.isRecording && shortcutRecorder.recordingIdentifier == "mediaToolsOCRShortcut" ? "Cancel" : "Record…") {
                    if shortcutRecorder.isRecording && shortcutRecorder.recordingIdentifier == "mediaToolsOCRShortcut" {
                        shortcutRecorder.stopRecording()
                    } else {
                        shortcutRecorder.startRecording(identifier: "mediaToolsOCRShortcut") { key, modifiers in
                            settings.settings.mediaToolsOCRShortcut = KeyboardShortcut(key: key, modifiers: modifiers)
                        }
                    }
                }.disabled(!settings.settings.mediaToolsOCRShortcutEnabled)
                Spacer()
                Button(screenOCR.isCapturing ? "Cancel Capture" : "Capture Screen Text") { screenOCR.capture() }
            }
            if screenOCR.shortcutUnavailable {
                Text("This shortcut conflicts with another action. Record a different shortcut.").font(.caption).foregroundStyle(.orange)
            }
            if let status = screenOCR.status { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var qualityBinding: Binding<Double> {
        Binding(get: { MediaOptimizer.Configuration(quality: settings.settings.mediaToolsImageQuality, maximumDimension: settings.settings.mediaToolsMaxImageDimension).quality },
                set: { settings.settings.mediaToolsImageQuality = $0.isFinite ? min(1, max(0.1, $0)) : 0.75 })
    }
    private var dimensionBinding: Binding<Double> {
        Binding(get: { Double(MediaOptimizer.Configuration(quality: settings.settings.mediaToolsImageQuality, maximumDimension: settings.settings.mediaToolsMaxImageDimension).maximumDimension) },
                set: { settings.settings.mediaToolsMaxImageDimension = $0.isFinite ? min(8192, max(256, $0)) : 2048 })
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
