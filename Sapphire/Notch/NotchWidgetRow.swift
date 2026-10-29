import SwiftUI

private struct NotchWidgetMaximumWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

extension EnvironmentValues {
    var notchWidgetMaximumWidth: CGFloat {
        get { self[NotchWidgetMaximumWidthKey.self] }
        set { self[NotchWidgetMaximumWidthKey.self] = newValue }
    }
}

/// Keeps the normal row's intrinsic size. Only an overflowing row scrolls, so
/// enabling extra widgets cannot move controls past the edge of the display.
struct NotchWidgetRow<Content: View>: View {
    let maximumWidth: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content().fixedSize()
            ScrollView(.horizontal) {
                content().fixedSize()
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: maximumWidth)
    }
}
