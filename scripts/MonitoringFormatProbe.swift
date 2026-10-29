import Foundation

@main
struct MonitoringFormatProbe {
    static func main() {
        precondition(PublicMonitoringFormat.percent(nil) == nil)
        for invalid in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            precondition(PublicMonitoringFormat.percent(invalid) == nil)
        }
        precondition(PublicMonitoringFormat.percent(0) == "0%")
        precondition(PublicMonitoringFormat.percent(1) == "100%")
        precondition(PublicMonitoringFormat.bytes(0) != nil)
        for invalid in [Double.nan, .infinity, -1, Double(Int64.max)] {
            precondition(PublicMonitoringFormat.bytes(invalid) == nil)
        }
        precondition(PublicMonitoringFormat.measurement(nil, unit: "°C") == nil)
        precondition(PublicMonitoringFormat.measurement(0, unit: "°C", minimum: 10) == nil)
        precondition(PublicMonitoringFormat.measurement(42, unit: "°C", minimum: 10)?.contains("42") == true)
        precondition(PublicMonitoringFormat.measurement(0, unit: "W") != nil)
        precondition(PublicMonitoringFormat.measurement(.nan, unit: "W") == nil)
        precondition(PublicMonitoringFormat.bounded(.nan, in: 50...100, fallback: 90) == 90)
        precondition(PublicMonitoringFormat.bounded(-10, in: 50...100, fallback: 90) == 50)
        precondition(PublicMonitoringFormat.bounded(200, in: 50...100, fallback: 90) == 100)
        precondition(PublicMonitoringFormat.pageBounds(count: 0, requestedPage: 0).isEmpty)
        precondition(PublicMonitoringFormat.pageBounds(count: 30, requestedPage: -1) == 0..<12)
        precondition(PublicMonitoringFormat.pageBounds(count: 30, requestedPage: 1) == 12..<24)
        precondition(PublicMonitoringFormat.pageBounds(count: 30, requestedPage: Int.max) == 24..<30)
        precondition(PublicMonitoringFormat.pageBounds(count: 30, requestedPage: 0, pageSize: 0).isEmpty)
        let last = PublicMonitoringFormat.pageBounds(count: Int.max, requestedPage: Int.max)
        precondition(last.upperBound == Int.max && last.count <= 12)
        print("Monitoring formatting: missing/invalid measurements, finite thresholds and bounded sensor pages passed")
    }
}
