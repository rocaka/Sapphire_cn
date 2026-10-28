import AVFoundation
import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

enum L10n { static func string(_ value: String) -> String { value } }
func premiumDefaultMessage(for feature: AppFeature) -> String { "Unavailable" }

@main struct MediaOptimizerProbe {
    static func main() async throws {
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
        }
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
        print("Media optimization: image bounds/alpha, unchanged originals, no overwrite, audio compression and video export passed")
    }
}
