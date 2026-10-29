import AppKit
import SwiftUI

@main struct MusicPlayerLockScreenProbe {
    static func main() {
        var requested = MusicPlayerAppearance()
        requested.width = 560
        requested.controlsScale = 1.25
        for screenWidth: CGFloat in [200, 320, 600, 1280, 2560] {
            let outerMaximum = LockScreenConfiguration.maximumMusicPlayerWidth(forScreenWidth: screenWidth)
            let contentMaximum = max(1, outerMaximum - 20)
            let appearance = MusicPlayerAppearancePolicy.resolve(requested, maximumContentWidth: Double(contentMaximum))
            let fullWidth = CGFloat(appearance.width) + 20 + 2 * LockScreenConfiguration.backgroundPadding
            precondition(fullWidth <= screenWidth - 48 + 0.001, "Lock-screen padding must fit its actual display")
            precondition(appearance.controlsScale * 320 <= appearance.width)
        }
        precondition(LockScreenConfiguration.maximumMusicPlayerWidth(forScreenWidth: .nan) == 1)
        precondition(LockScreenConfiguration.maximumMusicPlayerWidth(forScreenWidth: -.infinity) == 1)
        precondition(LockScreenConfiguration.maximumMusicPlayerWidth(forScreenWidth: -1) == 1)
        print("Lock-screen player: display-specific width includes background and internal padding; invalid bounds remain finite")
    }

    // Compile the same SwiftUI environment-injection shape used by displayView.
    @MainActor private static func injected<Content: View>(_ content: Content, width: CGFloat) -> some View {
        content.environment(\.notchWidgetMaximumWidth,
            LockScreenConfiguration.maximumMusicPlayerWidth(forScreenWidth: width))
    }
}
