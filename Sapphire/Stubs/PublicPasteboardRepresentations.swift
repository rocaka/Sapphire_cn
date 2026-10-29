#if !SAPPHIRE_FULL_BUILD
import Foundation

/// NSPasteboard advertises legacy compatibility names alongside modern UTIs.
/// Accept known aliases for the same payload without accepting rich/file content.
enum PublicPasteboardRepresentations {
    enum ImageFormat: String, CaseIterable, Hashable, Sendable {
        case png = "public.png", tiff = "public.tiff", jpeg = "public.jpeg"
        var fileExtension: String {
            switch self { case .png: "png"; case .tiff: "tiff"; case .jpeg: "jpg" }
        }
    }

    static let sourceType = "org.nspasteboard.source"
    static let optimizedImageMarker = "com.rocaka.sapphirecn.optimized-image"

    private static let imageAliases: [ImageFormat: Set<String>] = [
        .png: ["public.png", "Apple PNG pasteboard type"],
        .tiff: ["public.tiff", "NeXT TIFF v4.0 pasteboard type"],
        .jpeg: ["public.jpeg", "CorePasteboardFlavorType 0x4A504547"],
    ]
    private static let allImageTypes = imageAliases.values.reduce(into: Set<String>()) { $0.formUnion($1) }

    static func imageFormat(in types: Set<String>) -> ImageFormat? {
        // Cocoa may also offer a generated TIFF for PNG/JPEG. Prefer a
        // compressed original representation to avoid materializing that TIFF.
        [ImageFormat.png, .jpeg, .tiff].first { !(imageAliases[$0] ?? []).isDisjoint(with: types) }
    }

    static func isImageOnly(_ types: Set<String>) -> Bool {
        guard imageFormat(in: types) != nil else { return false }
        return types.isSubset(of: allImageTypes.union([sourceType]))
    }

    private static let urlTypes: Set<String> = [
        "public.url", "Apple URL pasteboard type", "CorePasteboardFlavorType 0x75726C20",
        // Cocoa's compatibility UTI for the legacy Apple URL pasteboard flavor.
        "dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu",
    ]
    private static let stringTypes: Set<String> = [
        "public.utf8-plain-text", "public.utf16-plain-text", "public.utf16-external-plain-text",
        "public.plain-text", "NSStringPboardType", "CorePasteboardFlavorType 0x54455854", "CorePasteboardFlavorType 0x75747874",
    ]
    static let urlMetadataGroups = [[sourceType], ["public.url-name", "CorePasteboardFlavorType 0x75726C6E", "Apple URL name pasteboard type"]]
    private static let urlMetadataTypes = Set(urlMetadataGroups.flatMap { $0 })

    static func hasURL(in types: Set<String>) -> Bool { !urlTypes.isDisjoint(with: types) }

    static func isTextURLOnly(_ types: Set<String>) -> Bool {
        let payload = urlTypes.union(stringTypes)
        guard !types.isDisjoint(with: payload) else { return false }
        return types.isSubset(of: payload.union(urlMetadataTypes))
    }
}
#endif
