#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import CoreGraphics

@MainActor
final class OCRScreenshotMonitor: ObservableObject {
    static let shared = OCRScreenshotMonitor()
    @Published private(set) var isCapturing = false
    @Published private(set) var shortcutUnavailable = false
    @Published private(set) var lastText = ""
    @Published private(set) var status: String?
    private var configuration: AnyCancellable?
    private var captureTask: Task<Void, Never>?
    private var stopped = false

    private struct Configuration: Equatable {
        let enabled: Bool
        let shortcut: KeyboardShortcut
        init(_ settings: Settings) {
            enabled = settings.mediaToolsOCRShortcutEnabled
            shortcut = settings.mediaToolsOCRShortcut
        }
    }

    private init() {}

    func start() {
        stopped = false
        guard configuration == nil else { return }
        configuration = SettingsModel.shared.changes(of: Configuration.init)
            .prepend(Configuration(SettingsModel.shared.current))
            .sink { [weak self] _ in self?.registerShortcut() }
    }

    private func registerShortcut() {
        KeyboardShortcutManager.shared.registerExternalShortcutProvider(.init(shortcuts: { [weak self] settings in
            guard self?.stopped == false, settings.mediaToolsOCRShortcutEnabled else { return [] }
            return [.init(identifier: ShortcutIdentifier.ocrScreenshot, shortcut: settings.mediaToolsOCRShortcut,
                          perform: { [weak self] in self?.capture() })]
        }, reportUnavailable: { [weak self] identifiers in
            self?.shortcutUnavailable = identifiers.contains(ShortcutIdentifier.ocrScreenshot)
        }), named: "community.screenOCR")
    }

    func capture() {
        if isCapturing { captureTask?.cancel(); return }
        guard CGPreflightScreenCaptureAccess() else {
            status = L10n.string("Allow Screen Recording in System Settings, then try capturing again.")
            PermissionsManager.shared.requestPermission(.screenRecording)
            return
        }
        isCapturing = true
        status = L10n.string("Select a screen region. Press Escape to cancel.")
        captureTask = Task {
            defer { isCapturing = false; captureTask = nil }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-ocr-" + UUID().uuidString)
            let file = directory.appendingPathComponent("capture.png")
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let code = try await selectRegion(to: file)
                try Task.checkCancellation()
                guard code == 0, FileManager.default.fileExists(atPath: file.path) else {
                    status = L10n.string("Cancelled")
                    return
                }
                status = L10n.string("Recognizing text…")
                let text = await MediaOptimizerManager.shared.recognizeText(in: file)
                try Task.checkCancellation()
                guard let text, !text.isEmpty else { status = L10n.string("No readable text was found."); return }
                lastText = text
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                status = L10n.string("Text copied to the clipboard.")
            } catch is CancellationError {
                status = L10n.string("Cancelled")
            } catch { status = error.localizedDescription }
        }
    }

    private func selectRegion(to file: URL) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", file.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                do {
                    try Task.checkCancellation()
                    try process.run()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: deadline)
                } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            DispatchQueue.main.async { if process.isRunning { process.terminate() } }
        }
    }

    func stop() {
        stopped = true
        configuration?.cancel()
        configuration = nil
        captureTask?.cancel()
        registerShortcut()
    }
}
#endif
