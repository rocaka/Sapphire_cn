#if !SAPPHIRE_FULL_BUILD
import Foundation

@MainActor
final class MediaOptimizerManager {
    static let shared = MediaOptimizerManager()
    private var optimizing = false
    var isOptimizing: Bool { optimizing }
    private init() {}
    func start() { PublicClipboardImageOptimizer.shared.start() }
    func stop() { PublicClipboardImageOptimizer.shared.stop() }

    func optimizeFile(_ url: URL) async -> Result<MediaOptimizeResult, MediaOptimizeError> {
        guard !optimizing else { return .failure(.busy) }
        PublicClipboardImageOptimizer.shared.pause()
        optimizing = true
        defer { optimizing = false; PublicClipboardImageOptimizer.shared.resumeCurrent() }
        let settings = SettingsModel.shared.current
        let configuration = MediaOptimizer.Configuration(quality: settings.mediaToolsImageQuality, maximumDimension: settings.mediaToolsMaxImageDimension)
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directory = cache.appendingPathComponent("com.rocaka.sapphirecn/MediaExports").appendingPathComponent(UUID().uuidString)
        let task = Task.detached(priority: .userInitiated) { try await MediaOptimizer.optimize(url, in: directory, configuration: configuration) }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            return .success(result)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            if error is CancellationError { return .failure(.cancelled) }
            return .failure((error as? MediaOptimizeError) ?? .failed(error.localizedDescription))
        }
    }

    func recognizeText(in url: URL) async -> String? {
        let task = Task.detached(priority: .userInitiated) { try? PublicTextRecognition.text(at: url) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
#endif
