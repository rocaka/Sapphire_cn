import Foundation
import CoreGraphics

@main struct NotchSizingProbe {
    static func main() {
        var policy = NotchSizeReportPolicy()
        let first = CGSize(width: 420, height: 240)
        let middle = CGSize(width: 420, height: 300)
        let final = CGSize(width: 420, height: 280)
        policy.record(first, epsilon: 0.5, generation: 0)
        policy.record(middle, epsilon: 0.5, generation: 0)
        policy.record(final, epsilon: 0.5, generation: 0)
        precondition(policy.consume(epsilon: 0.5) == final, "One layout turn should deliver its latest size only")
        precondition(policy.consume(epsilon: 0.5) == nil)
        policy.record(middle, epsilon: 0.5, generation: 0)
        policy.record(final, epsilon: 0.5, generation: 0)
        precondition(policy.consume(epsilon: 0.5) == nil, "A→B→A must not feed the stale B back into layout")
        policy.record(CGSize(width: 420.6, height: 280), epsilon: 0.5, generation: 0)
        policy.record(CGSize(width: 420.3, height: 280), epsilon: 0.5, generation: 0)
        precondition(policy.consume(epsilon: 0.5) == nil, "A final measurement within tolerance must suppress an intermediate resize")
        for index in 0..<10_000 {
            policy.record(CGSize(width: 420 + CGFloat(index % 3) * 0.1, height: 280), epsilon: 0.5, generation: 0)
        }
        precondition(policy.consume(epsilon: 0.5) == nil, "Subpixel churn must not schedule resize transactions")
        for invalid in [CGSize(width: CGFloat.infinity, height: 20), CGSize(width: 100, height: CGFloat.nan), CGSize(width: -1, height: 20), CGSize(width: CGFloat.greatestFiniteMagnitude, height: 10)] {
            policy.record(invalid, epsilon: 0.5, generation: 0)
            precondition(policy.consume(epsilon: 0.5) == nil)
            precondition(NotchSizeReportPolicy.validated(invalid, fallback: final) == final)
        }
        policy.record(middle, epsilon: 0.5, generation: 0)
        policy.record(CGSize(width: CGFloat.nan, height: 1), epsilon: 0.5, generation: 1)
        precondition(policy.consume(epsilon: 0.5) == nil, "A new presentation must discard old pending measurements")
        policy.record(final, epsilon: 0.5, generation: 1)
        precondition(policy.consume(epsilon: 0.5) == final, "A new presentation still receives its initial valid size")
        precondition(!NotchSizeReportPolicy.equivalent(final, CGSize(width: CGFloat.nan, height: 20), epsilon: 0.5))
        print("Notch sizing: latest-value coalescing, no stale resize feedback, subpixel suppression and invalid geometry checks passed")
    }
}
