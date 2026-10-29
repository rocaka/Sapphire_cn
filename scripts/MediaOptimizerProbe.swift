import AVFoundation
import AppKit
import CoreText
import PDFKit
import Foundation
import Darwin
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

enum L10n { static func string(_ value: String) -> String { value } }
func premiumDefaultMessage(for feature: AppFeature) -> String { "Unavailable" }

@main struct MediaOptimizerProbe {
    @MainActor static func main() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        let sentinel = "sapphire-media-probe-service-check"
        guard board.setString(sentinel, forType: .string), board.string(forType: .string) == sentinel else {
            fputs("MediaOptimizerProbe: macOS pasteboard service is unavailable to this process. Run this integration test in a normal macOS user session without a restrictive process sandbox. This is a test failure, not a skipped assertion. The user general clipboard was not accessed.\n", stderr)
            exit(EXIT_FAILURE)
        }
        do { try await runIntegrationChecks() }
        catch {
            fputs("MediaOptimizerProbe failed: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    @MainActor private static func runIntegrationChecks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = MediaOptimizer.Configuration(quality: 0.65, maximumDimension: 512)
        let invalid = MediaOptimizer.Configuration(quality: .nan, maximumDimension: .infinity)
        precondition(invalid.quality == 0.75 && invalid.maximumDimension == 2048)
        precondition(MediaOptimizer.kind(for: URL(string: "https://example.com/input.jpg")!) == nil)
        precondition(MediaOptimizer.kind(for: root.appendingPathComponent("input.exe")) == nil)
        for alpha in [false, true] {
            let context = CGContext(data: nil, width: 2048, height: 1024, bitsPerComponent: 8, bytesPerRow: 8192,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.4, alpha: alpha ? 0.4 : 1))
            context.fill(CGRect(x: 0, y: 0, width: 2048, height: 1024))
            let image = context.makeImage()!
            let source = root.appendingPathComponent(alpha ? "transparent.tiff" : "opaque.tiff")
            let writer = CGImageDestinationCreateWithURL(source as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(writer, image, [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]] as CFDictionary)
            precondition(CGImageDestinationFinalize(writer))
            let original = try Data(contentsOf: source)
            let result = try await MediaOptimizer.optimize(source, in: root.appendingPathComponent(UUID().uuidString), configuration: config)
            let after = try Data(contentsOf: source)
            precondition(original == after, "Optimization must preserve the original")
            precondition(result.savedBytes > 0 && result.savedPercent > 0)
            let output = CGImageSourceCreateWithURL(result.outputURL as CFURL, nil)!
            let properties = CGImageSourceCopyPropertiesAtIndex(output, 0, nil)! as NSDictionary
            precondition((properties[kCGImagePropertyPixelWidth] as! NSNumber).intValue <= 512)
            if alpha { precondition(result.outputURL.pathExtension == "png", "Transparency must be retained") }
            let outputBefore = try Data(contentsOf: result.outputURL)
            do {
                _ = try await MediaOptimizer.optimize(source, in: result.outputURL.deletingLastPathComponent(), configuration: config)
                preconditionFailure("An existing output must not be overwritten")
            } catch MediaOptimizeError.failed { }
            let outputAfter = try Data(contentsOf: result.outputURL)
            precondition(outputBefore == outputAfter)
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let type: NSPasteboard.PasteboardType = alpha ? .png : PublicMediaClipboardImage.jpeg
            // Test the native aliases Cocoa actually publishes for TIFF and the
            // optimized PNG/JPEG representation, not a hand-built type list.
            for (input, inputType) in [(original, NSPasteboard.PasteboardType.tiff), (outputBefore, type)] {
                board.clearContents()
                board.setData(input, forType: inputType)
                board.setString("com.example.sapphire-test", forType: PublicMediaClipboardImage.source)
                let initialCount = board.changeCount
                let advertised = Set((board.types ?? []).map(\.rawValue))
                precondition(PublicMediaClipboardImage.eligible(advertised), "Known image aliases must be accepted: \(advertised)")
                let representation = PublicPasteboardRepresentations.imageFormat(in: advertised)!
                precondition(board.data(forType: NSPasteboard.PasteboardType(representation.rawValue)) != nil)
                let updated = PublicMediaClipboardImage.replace(on: board, expectedChangeCount: initialCount, data: outputBefore, type: type)
                precondition(updated != nil && NSImage.canInit(with: board), "Optimized clipboard image must remain usable")
                precondition(board.string(forType: PublicMediaClipboardImage.source) == "com.example.sapphire-test")
                precondition(!PublicMediaClipboardImage.eligible(Set((board.types ?? []).map(\.rawValue))), "Do not repeatedly recompress our own image")
                board.clearContents()
                board.setString("new copied text", forType: .string)
                precondition(PublicMediaClipboardImage.replace(on: board, expectedChangeCount: updated!, data: outputBefore, type: type) == nil)
                precondition(board.string(forType: .string) == "new copied text", "Old image work must not overwrite a new clipboard item")
            }
            board.clearContents()
            board.setData(original, forType: .tiff)
            let countBeforeMismatch = board.changeCount
            let wrongType: NSPasteboard.PasteboardType = alpha ? PublicMediaClipboardImage.jpeg : .png
            precondition(PublicMediaClipboardImage.replace(on: board, expectedChangeCount: countBeforeMismatch, data: outputBefore, type: wrongType) == nil)
            precondition(board.changeCount == countBeforeMismatch && board.data(forType: .tiff) == original)
            let first = NSPasteboardItem(), second = NSPasteboardItem()
            first.setData(outputBefore, forType: type)
            second.setData(outputBefore, forType: type)
            board.clearContents()
            precondition(board.writeObjects([first, second]))
            precondition(PublicMediaClipboardImage.replace(on: board, expectedChangeCount: board.changeCount, data: outputBefore, type: type) == nil)
            precondition(board.pasteboardItems?.count == 2, "Multiple copied items must not collapse into one")
        }
        let urlBoard = NSPasteboard.withUniqueName()
        defer { urlBoard.releaseGlobally() }
        for type in [NSPasteboard.PasteboardType.string, .URL] {
            urlBoard.clearContents()
            urlBoard.setString("https://example.com/?id=a%2Bb&utm_source=test", forType: type)
            urlBoard.setString("Fixture Title", forType: NSPasteboard.PasteboardType("public.url-name"))
            precondition(PublicPasteboardRepresentations.isTextURLOnly(Set((urlBoard.types ?? []).map(\.rawValue))), "Cocoa's URL/string aliases must remain usable")
            urlBoard.setData(Data("{\\rtf1 Rich text}".utf8), forType: .rtf)
            precondition(!PublicPasteboardRepresentations.isTextURLOnly(Set((urlBoard.types ?? []).map(\.rawValue))), "Do not rewrite rich text")
        }
        let cancelledOutput = root.appendingPathComponent("cancelled")
        let cancelled = Task { try await MediaOptimizer.optimize(root.appendingPathComponent("opaque.tiff"), in: cancelledOutput, configuration: config) }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled work should not export") }
        catch is CancellationError { }
        precondition(!FileManager.default.fileExists(atPath: cancelledOutput.path))
        let pdfURL = root.appendingPathComponent("document.pdf")
        var page = CGRect(x: 0, y: 0, width: 600, height: 800)
        let pdf = CGContext(pdfURL as CFURL, mediaBox: &page, nil)!
        pdf.beginPDFPage(nil)
        pdf.textPosition = CGPoint(x: 40, y: 700)
        let text = NSAttributedString(string: "Sapphire PDF preservation", attributes: [kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 24, nil)])
        CTLineDraw(CTLineCreateWithAttributedString(text), pdf)
        pdf.endPDFPage(); pdf.closePDF()
        let pdfBefore = try Data(contentsOf: pdfURL)
        do {
            let optimizedPDF = try await MediaOptimizer.optimize(pdfURL, in: root.appendingPathComponent("pdf-output"), configuration: config)
            precondition(PDFDocument(url: optimizedPDF.outputURL)?.string?.contains("Sapphire") == true)
        } catch MediaOptimizeError.noSavings { }
        let pdfAfter = try Data(contentsOf: pdfURL)
        precondition(pdfBefore == pdfAfter)
        let lockedURL = root.appendingPathComponent("locked.pdf")
        let locked = CGContext(lockedURL as CFURL, mediaBox: &page, [kCGPDFContextUserPassword: "test-password", kCGPDFContextOwnerPassword: "test-owner"] as CFDictionary)!
        locked.beginPDFPage(nil); locked.endPDFPage(); locked.closePDF()
        do {
            _ = try await MediaOptimizer.optimize(lockedURL, in: root.appendingPathComponent("locked-output"), configuration: config)
            preconditionFailure("Password protected PDF must stay protected")
        } catch MediaOptimizeError.protectedPDF { }
        let audioURL = root.appendingPathComponent("audio.wav")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
            var fileSettings = format.settings
            fileSettings[AVLinearPCMIsNonInterleaved] = false
            let file = try AVAudioFile(forWriting: audioURL, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
            buffer.frameLength = 44_100
            for channel in 0..<2 {
                for index in 0..<44_100 { buffer.floatChannelData![channel][index] = Float(sin(Double(index) * 440 * 2 * .pi / 44_100)) * 0.1 }
            }
            for _ in 0..<3 { try file.write(from: buffer) }
        }
        let audioBefore = try Data(contentsOf: audioURL)
        let audio = try await MediaOptimizer.optimize(audioURL, in: root.appendingPathComponent("audio-output"), configuration: config)
        let audioAfter = try Data(contentsOf: audioURL)
        precondition(audioBefore == audioAfter && audio.savedBytes > 0 && audio.kind == .audio)
        let videoURL = root.appendingPathComponent("video.mov")
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.jpeg, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240])
        precondition(writer.canAdd(input))
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess)
        let buffer = pixel!
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer)!, 255, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for index in 0..<60 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error! }
                try await Task.sleep(for: .milliseconds(10))
            }
            precondition(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        precondition(writer.status == .completed)
        let videoBefore = try Data(contentsOf: videoURL)
        do {
            let video = try await MediaOptimizer.optimize(videoURL, in: root.appendingPathComponent("video-output"), configuration: config)
            precondition(video.kind == .video && video.optimizedBytes > 0 && video.savedBytes > 0)
        } catch MediaOptimizeError.noSavings { } // Valid if the source is already smaller than the export.
        let videoAfter = try Data(contentsOf: videoURL)
        precondition(videoBefore == videoAfter)
        print("Media optimization: image/PDF/audio/video exports, clipboard stale-work/loop guards, cancellation and unchanged originals passed")
    }
}
