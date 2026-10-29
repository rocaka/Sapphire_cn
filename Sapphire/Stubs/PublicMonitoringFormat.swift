#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Display only measured, finite values. Missing sensor values must never be
/// replaced with the zero-valued entries used to describe the sensor catalog.
enum PublicMonitoringFormat {
    static func fraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    static func percent(_ value: Double?) -> String? {
        guard let value = fraction(value) else { return nil }
        return String(format: "%.0f%%", value * 100)
    }

    static func bytes(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0, value < Double(Int64.max) else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func measurement(_ value: Double?, unit: String, minimum: Double = 0) -> String? {
        guard let value, value.isFinite, value >= minimum else { return nil }
        return value.formatted(.number.precision(.fractionLength(0...2))) + " " + unit
    }

    static func bounded(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
    }

    /// A bounded page is also the exact set of sensor keys to request. This
    /// keeps a large SMC catalog from becoming a high-cost background poll.
    static func pageBounds(count: Int, requestedPage: Int, pageSize: Int = 12) -> Range<Int> {
        guard count > 0, pageSize > 0 else { return 0..<0 }
        let lastPage = (count - 1) / pageSize
        let page = min(lastPage, max(0, requestedPage))
        let start = page * pageSize
        return start..<(start + min(pageSize, count - start))
    }
}
#endif
