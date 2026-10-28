#if !SAPPHIRE_FULL_BUILD
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum PublicTextRecognition {
    enum Failure: Error { case unreadable, lockedDocument, cancelled }

    static func canRead(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let knownFormats: Set<String> = ["pdf", "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp", "avif"]
        if knownFormats.contains(url.pathExtension.lowercased()) { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    static func text(at url: URL) throws -> String {
        guard canRead(url) else { throw Failure.unreadable }
        if url.pathExtension.lowercased() == "pdf" { return try pdfText(at: url) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { throw Failure.unreadable }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { throw Failure.unreadable }
        return try recognize(image)
    }

    private static func recognize(_ image: CGImage) throws -> String {
        if Task.isCancelled { throw Failure.cancelled }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        if Task.isCancelled { throw Failure.cancelled }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func pdfText(at url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        guard !document.isLocked else { throw Failure.lockedDocument }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if Task.isCancelled { throw Failure.cancelled }
            let text: String = try autoreleasepool {
                guard let page = document.page(at: index) else { throw Failure.unreadable }
                if let selectable = page.string, !selectable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return selectable
                }
                let bounds = page.bounds(for: .mediaBox)
                guard bounds.width > 0, bounds.height > 0 else { return "" }
                let scale = min(3, 3072 / max(bounds.width, bounds.height))
                let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Failure.unreadable }
                return try recognize(bitmap)
            }
            pages.append(text)
        }
        return pages.joined(separator: "\n\n")
    }
}
#endif
