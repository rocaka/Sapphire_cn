#if !SAPPHIRE_FULL_BUILD
import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum MediaOptimizeKind: String { case image, pdf, video, audio
    var actionTitle: String { L10n.string("Optimize Copy") }
    var systemImage: String {
        switch self { case .image: "photo"; case .pdf: "doc"; case .video: "video"; case .audio: "waveform" }
    }
}

struct MediaOptimizeResult: Equatable {
    let sourceURL: URL
    let outputURL: URL
    let kind: MediaOptimizeKind
    let originalBytes: Int64
    let optimizedBytes: Int64
    var savedBytes: Int64 { max(0, originalBytes - optimizedBytes) }
    var savedPercent: Int { originalBytes > 0 ? Int(min(100, max(0, Double(savedBytes) / Double(originalBytes) * 100))) : 0 }
}

enum MediaOptimizeError: LocalizedError, Equatable {
    case premiumRequired, unsupported, unreadable, protectedPDF, noSavings, busy, cancelled
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .premiumRequired: return premiumDefaultMessage(for: .mediaTools)
        case .unsupported: return L10n.string("This file format cannot be optimized by this build.")
        case .unreadable: return L10n.string("The source file could not be read.")
        case .protectedPDF: return L10n.string("Unlock this PDF and allow copying before processing it.")
        case .noSavings: return L10n.string("The optimized copy was not smaller. The original file was kept.")
        case .busy: return L10n.string("Another optimization is running. Please wait for it to finish.")
        case .cancelled: return L10n.string("Cancelled")
        case .failed(let detail): return detail
        }
    }
}

enum MediaOptimizer {
    static func kind(for url: URL) -> MediaOptimizeKind? {
        guard url.isFileURL else { return nil }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp": return .image
        case "pdf": return .pdf
        case "mp4", "mov", "m4v": return .video
        case "m4a", "mp3", "wav", "aif", "aiff", "caf", "flac": return .audio
        default: return nil
        }
    }
    static func canOCR(_ url: URL) -> Bool { PublicTextRecognition.canRead(url) }

    struct Configuration: Sendable {
        let quality: Double
        let maximumDimension: Int
        init(quality: Double, maximumDimension: Double) {
            self.quality = quality.isFinite ? min(1, max(0.1, quality)) : 0.75
            self.maximumDimension = maximumDimension.isFinite ? Int(min(8192, max(256, maximumDimension))) : 2048
        }
    }

    static func optimize(_ source: URL, in directory: URL, configuration: Configuration) async throws -> MediaOptimizeResult {
        try Task.checkCancellation()
        guard let kind = kind(for: source) else { throw MediaOptimizeError.unsupported }
        let originalBytes = try size(source)
        guard originalBytes > 0 else { throw MediaOptimizeError.unreadable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent + "-optimized"
        let output: URL
        switch kind {
        case .image:
            output = try image(source, base: base, directory: directory, configuration: configuration)
        case .pdf:
            output = try newOutput(base: base, suffix: "pdf", directory: directory)
            guard let document = PDFDocument(url: source) else { throw MediaOptimizeError.unreadable }
            guard !document.isLocked, document.allowsCopying else { throw MediaOptimizeError.protectedPDF }
            guard document.write(to: output, withOptions: [.optimizeImagesForScreenOption: true]) else { throw MediaOptimizeError.unreadable }
        case .video, .audio:
            let type: AVFileType = kind == .video ? .mp4 : .m4a
            output = try newOutput(base: base, suffix: kind == .video ? "mp4" : "m4a", directory: directory)
            try await export(source, to: output, type: type, preset: kind == .video ? AVAssetExportPresetMediumQuality : AVAssetExportPresetAppleM4A)
        }
        if Task.isCancelled { throw MediaOptimizeError.cancelled }
        let optimizedBytes = try size(output)
        guard optimizedBytes > 0 else { throw MediaOptimizeError.unreadable }
        guard optimizedBytes < originalBytes else {
            try? FileManager.default.removeItem(at: output)
            throw MediaOptimizeError.noSavings
        }
        return MediaOptimizeResult(sourceURL: source, outputURL: output, kind: kind, originalBytes: originalBytes, optimizedBytes: optimizedBytes)
    }

    private static func image(_ source: URL, base: String, directory: URL, configuration: Configuration) throws -> URL {
        guard let data = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(data) == 1 else { throw MediaOptimizeError.unsupported }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: configuration.maximumDimension]
        guard let image = CGImageSourceCreateThumbnailAtIndex(data, 0, options as CFDictionary) else { throw MediaOptimizeError.unreadable }
        try Task.checkCancellation()
        let alpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = alpha ? UTType.png : UTType.jpeg
        let output = try newOutput(base: base, suffix: alpha ? "png" : "jpg", directory: directory)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else { throw MediaOptimizeError.unreadable }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: configuration.quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MediaOptimizeError.unreadable }
        return output
    }

    private static func export(_ source: URL, to destination: URL, type: AVFileType, preset: String) async throws {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset), exporter.supportedFileTypes.contains(type) else { throw MediaOptimizeError.unsupported }
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: destination, as: type)
    }

    private static func newOutput(base: String, suffix: String, directory: URL) throws -> URL {
        let output = directory.appendingPathComponent(base).appendingPathExtension(suffix)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw MediaOptimizeError.failed(L10n.string("The output file already exists. Choose a different destination."))
        }
        return output
    }

    private static func size(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let number = attributes[.size] as? NSNumber else { throw MediaOptimizeError.unreadable }
        return number.int64Value
    }
}

#endif
