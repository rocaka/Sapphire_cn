import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

@main struct TextRecognitionProbe {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        precondition(!PublicTextRecognition.canRead(URL(string: "https://example.com/photo.png")!))
        precondition(!PublicTextRecognition.canRead(root.appendingPathComponent("data.exe")))
        let text = "Sapphire local text recognition"
        let context = CGContext(data: nil, width: 1400, height: 240, bitsPerComponent: 8, bytesPerRow: 5600,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1400, height: 240))
        let font = CTFontCreateWithName("Helvetica" as CFString, 52, nil)
        let attributed = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font,
                                                                       kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1)])
        context.textPosition = CGPoint(x: 40, y: 100)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        let image = context.makeImage()!
        let imageURL = root.appendingPathComponent("fixture.png")
        let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        fputs("Recognizing image fixture; supported=\(PublicTextRecognition.canRead(imageURL))\n", stderr)
        let recognized = try PublicTextRecognition.text(at: imageURL)
        precondition(recognized.localizedCaseInsensitiveContains("Sapphire"), "OCR missed fixture: \(recognized)")
        let pdfURL = root.appendingPathComponent("fixture.pdf")
        var bounds = CGRect(x: 0, y: 0, width: 1400, height: 240)
        let pdf = CGContext(pdfURL as CFURL, mediaBox: &bounds, nil)!
        pdf.beginPDFPage(nil)
        pdf.textPosition = CGPoint(x: 40, y: 100)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), pdf)
        pdf.endPDFPage()
        pdf.closePDF()
        fputs("Reading PDF fixture; supported=\(PublicTextRecognition.canRead(pdfURL))\n", stderr)
        let extractedPDF = try PublicTextRecognition.text(at: pdfURL)
        precondition(extractedPDF.contains("Sapphire"))
        let scannedURL = root.appendingPathComponent("scanned.pdf")
        let scanned = CGContext(scannedURL as CFURL, mediaBox: &bounds, nil)!
        scanned.beginPDFPage(nil)
        scanned.draw(image, in: bounds)
        scanned.endPDFPage()
        scanned.closePDF()
        let scannedText = try PublicTextRecognition.text(at: scannedURL)
        precondition(scannedText.localizedCaseInsensitiveContains("Sapphire"), "Scanned PDF OCR failed: \(scannedText)")
        print("Local image OCR, selectable/scanned PDF extraction and unsupported input checks passed")
    }
}
