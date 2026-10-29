import SwiftUI

enum MusicPlayerAppearanceColor {
    static func override(for appearance: MusicPlayerAppearance) -> Color? {
        switch appearance.accentMode {
        case .artwork: return nil
        case .white: return .white
        case .system: return .accentColor
        case .custom:
            let rgb = MusicPlayerAppearancePolicy.rgbHexValue(appearance.customHex) ?? 0xFF9F0A
            return Color(.sRGB, red: Double((rgb >> 16) & 0xff) / 255,
                         green: Double((rgb >> 8) & 0xff) / 255,
                         blue: Double(rgb & 0xff) / 255, opacity: 1)
        }
    }
}
