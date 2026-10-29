import SwiftUI

struct DesktopLyricsOverlayView: View {
    let text: String
    let translation: String?
    let appearance: DesktopLyricsAppearance

    private var textColor: Color {
        let rgb = MusicPlayerAppearancePolicy.rgbHexValue(appearance.customHex) ?? 0xFFFFFF
        return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255, opacity: 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(.system(size: appearance.fontSize, weight: .semibold, design: .rounded))
            if let translation {
                Text(translation)
                    .font(.system(size: appearance.fontSize * 0.76, weight: .medium, design: .rounded))
                    .opacity(0.88)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(.center)
        .foregroundStyle(textColor)
        .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(appearance.backgroundOpacity), in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }
}
