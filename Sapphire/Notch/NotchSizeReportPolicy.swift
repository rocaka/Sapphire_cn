import Foundation
import CoreGraphics

/// Keeps geometry feedback bounded: only the latest valid measurement from a
/// layout turn is delivered back into the state which sizes that same layout.
struct NotchSizeReportPolicy {
    private(set) var pending: CGSize?
    private(set) var reported: CGSize?
    private var generation = 0

    // Far above any usable display/content size; rejects finite overflow before
    // AppKit or CALayer converts it into invalid render geometry.
    static let maximumDimension: CGFloat = 1_000_000

    static func isUsable(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
            && size.width >= 0 && size.height >= 0
            && size.width <= maximumDimension && size.height <= maximumDimension
    }

    static func validated(_ size: CGSize, fallback: CGSize = .zero) -> CGSize {
        isUsable(size) ? size : (isUsable(fallback) ? fallback : .zero)
    }

    static func equivalent(_ first: CGSize, _ second: CGSize, epsilon: CGFloat) -> Bool {
        guard isUsable(first), isUsable(second) else { return false }
        let tolerance = epsilon.isFinite ? max(0, epsilon) : 0.5
        return abs(first.width - second.width) <= tolerance
            && abs(first.height - second.height) <= tolerance
    }

    mutating func record(_ size: CGSize, epsilon: CGFloat, generation: Int) {
        if self.generation != generation {
            self.generation = generation
            reported = nil
            pending = nil
        }
        guard Self.isUsable(size) else { return }
        // Once a report is scheduled, retain the actual final measurement even
        // if the last two measurements differ by less than the tolerance.
        if pending == nil, let reported, Self.equivalent(reported, size, epsilon: epsilon) { return }
        pending = size
    }

    mutating func consume(epsilon: CGFloat) -> CGSize? {
        guard let latest = pending else { return nil }
        pending = nil
        if let reported, Self.equivalent(reported, latest, epsilon: epsilon) { return nil }
        reported = latest
        return latest
    }
}
