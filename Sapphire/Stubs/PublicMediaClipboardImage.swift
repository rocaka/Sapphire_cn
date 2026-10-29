#if !SAPPHIRE_FULL_BUILD
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum PublicMediaClipboardImage {
    static let marker = NSPasteboard.PasteboardType(PublicPasteboardRepresentations.optimizedImageMarker)
    static let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    static let source = NSPasteboard.PasteboardType(PublicPasteboardRepresentations.sourceType)

    static func eligible(_ types: Set<String>) -> Bool {
        PublicPasteboardRepresentations.isImageOnly(types)
    }

    @MainActor static func replace(on pasteboard: NSPasteboard, expectedChangeCount: Int, data: Data, type: NSPasteboard.PasteboardType) -> Int? {
        guard pasteboard.changeCount == expectedChangeCount, pasteboard.pasteboardItems?.count == 1,
              eligible(Set((pasteboard.types ?? []).map(\.rawValue))),
              [NSPasteboard.PasteboardType.png, jpeg].contains(type),
              let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) == 1,
              (CGImageSourceGetType(image) as String?) == type.rawValue else { return nil }
        let sourceData = pasteboard.data(forType: source)
        let item = NSPasteboardItem()
        guard item.setData(data, forType: type), item.setData(Data([1]), forType: marker) else { return nil }
        if let sourceData { item.setData(sourceData, forType: source) }
        guard pasteboard.changeCount == expectedChangeCount else { return nil }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return nil }
        return pasteboard.changeCount
    }
}
#endif
