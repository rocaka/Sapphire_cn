import Foundation
import CoreGraphics

// API fixtures isolate the real controller method's effect scheduling. There
// are no windows, event taps, file transfers, or application instances here.
enum LiveActivityType { case capsLock, music, weather, calendar, reminders, timers, battery, eyeBreak, desktop, focus, fileShelf, fileProgress, stats, microphone, devActivity, sports, finance }
enum ResizeAnimation {
    case shape, removal, blur
    enum Timing { case easeIn }
    static func notchMorphTiming(_ timing: Timing, duration: Double) -> Self { .blur }
}
func withAnimation(_ animation: ResizeAnimation, _ body: () -> Void) { body() }
enum NotchDisplayMetrics {
    static func snappedSize(atLeast size: CGSize, scale: CGFloat) -> CGSize { size }
}
enum NotchSizing {
    static func expandedContentSize(contentSize: CGSize, minimumSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(contentSize.width, minimumSize.width), height: max(contentSize.height, minimumSize.height))
    }
}
enum ResizeState { case initial, autoExpanded, hoverExpanded }
struct ResizeConfiguration {
    var initialSize = CGSize(width: 180, height: 32)
    var displayScale: CGFloat = 2
    var activityBlurUpdateDelay = 0.1
    var autoContentRenderDelay = 0.35
    var activityToActivityAnimation = ResizeAnimation.shape
    var blurRemovalAnimation = ResizeAnimation.removal
}
@MainActor final class ResizeEffects {
    struct Values { var activityBlurRadius: CGFloat = 0 }
    var values = Values()
    var appliedRadii: [CGFloat] = []
    func update(_ animation: ResizeAnimation? = nil, _ change: (inout Values) -> Void) {
        change(&values)
        appliedRadii.append(values.activityBlurRadius)
    }
}

@main struct NotchProgressResizeProbe {
    @MainActor static func require(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: " + message); exit(1) }
    }

    @MainActor static func main() async {
        // The recording shows an approximately 0.4 s clear/blur cycle as speed
        // changes. Replay sustained size updates through the actual method.
        let progress = ResizeHarness()
        progress.liveActivityManager.currentActivity = .fileProgress
        for index in 0..<32 {
            progress.measuredAutoContentSize = CGSize(width: index.isMultiple(of: 2) ? 553 : 539, height: 32)
            progress.updateAutoContentSize()
            require(progress.effects.values.activityBlurRadius == 0,
                "download sample \(index) blurred the complete card during a progress resize")
            require(progress.scratch.blurRemovalTask == nil, "download resize created a delayed blur task")
            require(progress.animatedWidth == progress.measuredAutoContentSize.width,
                "progress resize must still update the notch outline")
        }
        require(progress.effects.appliedRadii.allSatisfy { $0 == 0 }, "the card must remain sharp for the entire progress sequence")

        for activity in [ActivityType.music, .systemHUD] {
            let existing = ResizeHarness()
            existing.liveActivityManager.currentActivity = activity
            existing.updateAutoContentSize()
            require(existing.effects.values.activityBlurRadius == 0 && existing.scratch.blurRemovalTask == nil,
                "existing music/HUD behavior changed")
        }

        let normal = ResizeHarness()
        normal.liveActivityManager.currentActivity = .notification
        normal.updateAutoContentSize()
        require(normal.effects.values.activityBlurRadius == 15 && normal.scratch.blurRemovalTask != nil,
            "ordinary activity size changes must retain their original blur animation")
        normal.scratch.blurRemovalTask?.cancel()

        let reduced = ResizeHarness()
        reduced.reduceMotion = true
        reduced.updateAutoContentSize()
        require(reduced.effects.values.activityBlurRadius == 0 && reduced.scratch.blurRemovalTask == nil,
            "Reduce Motion must continue to suppress blur")

        let switching = ResizeHarness()
        switching.scratch.activitySwitchBlurWindowEnd = .distantFuture
        switching.updateAutoContentSize()
        require(switching.effects.values.activityBlurRadius == 0 && switching.scratch.blurRemovalTask == nil,
            "activity-switch grace period must be preserved")

        // A progress card must also clear a blur inherited from a preceding
        // resize, rather than waiting for an obsolete completion to fire.
        let inherited = ResizeHarness()
        inherited.effects.values.activityBlurRadius = 15
        inherited.scratch.blurRemovalTask = Task { try? await Task.sleep(for: .seconds(10)) }
        inherited.liveActivityManager.currentActivity = .fileProgress
        inherited.updateAutoContentSize()
        require(inherited.effects.values.activityBlurRadius == 0 && inherited.scratch.blurRemovalTask == nil,
            "progress resize must clear and cancel any inherited delayed blur")
        print("Real notch resize method: 32 continuous download updates stay sharp; shape resizing, existing activity animations, Reduce Motion and pending-blur cleanup passed")
    }
}
