import SwiftUI

/// Static sample content: deliberately does not observe MusicManager or invoke
/// controls, networking, artwork loading, audio capture or permission APIs.
struct MusicPlayerAppearancePreview: View {
    let appearance: MusicPlayerAppearance
    var maximumContentWidth: Double = 520

    private var resolved: MusicPlayerAppearance {
        MusicPlayerAppearancePolicy.resolve(appearance, maximumContentWidth: maximumContentWidth)
    }

    private var accent: Color {
        switch resolved.accentMode {
        case .artwork: return .orange
        case .white: return .white
        case .system: return .accentColor
        case .custom:
            let hex = MusicPlayerAppearancePolicy.rgbHexValue(resolved.customHex) ?? 0xFF9F0A
            return Color(red: Double((hex >> 16) & 255) / 255,
                         green: Double((hex >> 8) & 255) / 255,
                         blue: Double(hex & 255) / 255)
        }
    }

    var body: some View {
        let value = resolved
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                if value.showArtwork {
                    RoundedRectangle(cornerRadius: value.artworkCornerRadius)
                        .fill(LinearGradient(colors: [accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Image(systemName: "music.note").font(.system(size: value.artworkSize * 0.4)).foregroundStyle(.white))
                        .frame(width: value.artworkSize, height: value.artworkSize)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("A favorite song"))
                        .font(.system(size: value.titleFontSize, weight: .semibold, design: .rounded)).lineLimit(1)
                    if value.showArtist {
                        Text(L10n.string("Your artist"))
                            .font(.system(size: value.artistFontSize, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if value.showProgress {
                HStack(spacing: 8) {
                    Text("0:42").font(.caption.monospacedDigit())
                    Capsule().fill(accent.opacity(0.25)).frame(height: 4)
                        .overlay(alignment: .leading) { Capsule().fill(accent).frame(width: value.width * 0.3, height: 4) }
                    Text("−2:18").font(.caption.monospacedDigit())
                }.foregroundStyle(.secondary)
            }
            if value.showLyrics {
                Text(L10n.string("Your lyrics appear here"))
                    .font(.system(size: value.lyricsFontSize, weight: .medium))
                    .foregroundStyle(accent).lineLimit(2)
            }
            HStack {
                ForEach(["heart", "backward.end.fill", "pause.fill", "forward.end.fill", "list.bullet"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.system(size: 18 * value.controlsScale))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: value.width)
        .padding(14)
        .background(.black, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.string("Static appearance preview")))
    }
}
