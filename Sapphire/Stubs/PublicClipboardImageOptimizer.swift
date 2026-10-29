#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine

@MainActor
final class PublicClipboardImageOptimizer: ObservableObject {
    static let shared = PublicClipboardImageOptimizer()
    @Published private(set) var status: String?
    private var configuration: AnyCancellable?
    private var subscription: PasteboardChangeMonitor.Token?
    private var work: Task<Void, Never>?
    private var pendingChangeCount: Int?
    private var generation = UUID()

    private struct Configuration: Equatable {
        let enabled: Bool
        let quality: Double
        let maximumDimension: Int
        init(_ settings: Settings) {
            enabled = settings.mediaToolsAutoOptimizeClipboard
            let values = MediaOptimizer.Configuration(quality: settings.mediaToolsImageQuality, maximumDimension: settings.mediaToolsMaxImageDimension)
            quality = values.quality
            maximumDimension = values.maximumDimension
        }
    }

    private init() {}
    func start() {
        guard configuration == nil else { return }
        configuration = SettingsModel.shared.changes(of: Configuration.init)
            .prepend(Configuration(SettingsModel.shared.current))
            .sink { [weak self] config in
                guard let self else { return }
                self.pause()
                if config.enabled {
                    if self.subscription == nil {
                        self.subscription = PasteboardChangeMonitor.shared.subscribe(interval: 1, priority: 50) { [weak self] count in self?.optimize(changeCount: count) }
                    }
                    self.resumeCurrent()
                } else {
                    if let subscription = self.subscription { PasteboardChangeMonitor.shared.unsubscribe(subscription); self.subscription = nil }
                    self.status = nil
                }
            }
    }

    func pause() {
        generation = UUID()
        pendingChangeCount = nil
        if work != nil { status = nil }
        work?.cancel()
        // ImageIO is synchronous: retain the task until it exits before starting
        // another decoder, rather than piling up cancelled detached workers.
    }

    func resumeCurrent() { optimize(changeCount: NSPasteboard.general.changeCount) }

    private func optimize(changeCount: Int) {
        generation = UUID()
        pendingChangeCount = changeCount
        if work != nil {
            status = nil
            work?.cancel()
            return
        }
        beginLatest()
    }

    private func beginLatest() {
        guard let changeCount = pendingChangeCount else { return }
        pendingChangeCount = nil
        if status != nil { status = nil }
        let settings = SettingsModel.shared.current
        guard settings.mediaToolsAutoOptimizeClipboard, !MediaOptimizerManager.shared.isOptimizing else { return }
        let pasteboard = NSPasteboard.general
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard pasteboard.changeCount == changeCount, pasteboard.pasteboardItems?.count == 1,
              PublicMediaClipboardImage.eligible(types),
              !ClipboardCaptureFilter.shouldIgnore(types: types,
                  sourceBundleID: pasteboard.string(forType: PublicMediaClipboardImage.source),
                  frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  ignoredBundleIDs: Set(settings.clipboardIgnoredAppBundleIDs), ignoreMarkedItems: true) else { return }
        guard let representation = PublicPasteboardRepresentations.imageFormat(in: types) else { return }
        let sourceType = NSPasteboard.PasteboardType(representation.rawValue)
        let suffix = representation.fileExtension
        guard let data = pasteboard.data(forType: sourceType), !data.isEmpty, pasteboard.changeCount == changeCount else { return }
        guard data.count <= 32 * 1024 * 1024 else { status = L10n.string("This copied image is too large for automatic optimization."); return }
        let config = MediaOptimizer.Configuration(quality: settings.mediaToolsImageQuality, maximumDimension: settings.mediaToolsMaxImageDimension)
        let token = generation
        status = L10n.string("Optimizing the copied image…")
        work = Task { [weak self] in
            guard let self else { return }
            defer {
                work = nil
                if pendingChangeCount != nil { beginLatest() }
            }
            let task = Task.detached(priority: .utility) { () async throws -> (Data, String) in
                try Task.checkCancellation()
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-clipboard-image-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let source = directory.appendingPathComponent("clipboard." + suffix)
                try data.write(to: source, options: .atomic)
                let result = try await MediaOptimizer.optimize(source, in: directory.appendingPathComponent("output"), configuration: config)
                return (try Data(contentsOf: result.outputURL), result.outputURL.pathExtension)
            }
            do {
                let (optimized, suffix) = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                let currentSettings = SettingsModel.shared.current
                let currentTypes = Set((pasteboard.types ?? []).map(\.rawValue))
                guard !Task.isCancelled, generation == token else { return }
                guard currentSettings.mediaToolsAutoOptimizeClipboard,
                      !ClipboardCaptureFilter.shouldIgnore(types: currentTypes,
                          sourceBundleID: pasteboard.string(forType: PublicMediaClipboardImage.source),
                          frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                          ignoredBundleIDs: Set(currentSettings.clipboardIgnoredAppBundleIDs), ignoreMarkedItems: true) else { status = nil; return }
                let type: NSPasteboard.PasteboardType = suffix == "png" ? .png : PublicMediaClipboardImage.jpeg
                if PublicMediaClipboardImage.replace(on: pasteboard, expectedChangeCount: changeCount, data: optimized, type: type) != nil {
                    status = L10n.string("The copied image was optimized.")
                } else { status = nil }
            } catch is CancellationError { }
            catch MediaOptimizeError.noSavings {
                if generation == token {
                    status = pasteboard.changeCount == changeCount ? L10n.string("The original image was already compact. Clipboard unchanged.") : nil
                }
            } catch {
                if generation == token && !Task.isCancelled { status = pasteboard.changeCount == changeCount ? error.localizedDescription : nil }
            }
        }
    }

    func stop() {
        pause()
        configuration?.cancel(); configuration = nil
        if let subscription { PasteboardChangeMonitor.shared.unsubscribe(subscription); self.subscription = nil }
    }
}
#endif
