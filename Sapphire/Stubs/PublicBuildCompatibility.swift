#if !SAPPHIRE_FULL_BUILD
import Foundation
import CoreGraphics

/// Keeps the public storage scanner's data available without the private map UI.
struct StorageSpaceMapSnapshot {
    let entries: [StorageEntry]
    let used: Int64
    let total: Int64
    static func make(from entries: [StorageEntry], maximumItems: Int, used: Int64, total: Int64,
                     deepScanEnabled: Bool, entriesSortedBySize: Bool) -> Self {
        Self(entries: Array(entries.prefix(max(0, maximumItems))), used: used, total: total)
    }
}

enum OCRScreenTextSupport {
    static func indexOfScreen(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex(where: { $0.contains(point) }) ?? (frames.isEmpty ? nil : 0)
    }
}
#endif
