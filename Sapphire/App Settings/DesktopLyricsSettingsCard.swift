import SwiftUI

struct DesktopLyricsSettingsCard: View {
    @EditingSettings private var settings: SettingsEditingSession

    private var appearance: DesktopLyricsAppearance {
        DesktopLyricsAppearancePolicy.resolve(settings.settings.desktopLyricsAppearance)
    }

    var body: some View {
        SettingsCard(title: "Desktop Lyrics Below the Notch", description: "Show the current lyric below the notch, even when the music player is closed.") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(L10n.string("Enable Desktop Lyrics"), isOn: binding(\.enabled))
                Text(L10n.string("Lyrics follow the display with Sapphire's notch. They do not capture mouse clicks and hide while the notch is expanded, the Mac is locked, or the display sleeps."))
                    .font(.caption).foregroundStyle(.secondary)
                DesktopLyricsPreview(appearance: appearance)
                Text(L10n.string("Static preview. Desktop lyrics use the existing song and lyric source; songs without lyrics show no overlay."))
                    .font(.caption).foregroundStyle(.secondary)
                numberRow("Lyrics Width", \.width, 240...1000)
                numberRow("Desktop Lyrics Font Size", \.fontSize, 12...48)
                numberRow("Gap Below the Notch", \.verticalOffset, 0...240)
                numberRow("Lyrics Background Opacity", \.backgroundOpacity, 0...1, step: 0.01)
                TextField(L10n.string("Lyrics Color (Hex)"), text: Binding(
                    get: { settings.settings.desktopLyricsAppearance.customHex },
                    set: { settings.settings.desktopLyricsAppearance.customHex = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                Text(L10n.string("Enter a color such as #FF9F0A. Invalid colors use the default."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.string("Show Translation as a Second Line"), isOn: binding(\.showTranslation))
                Text(L10n.string("Uses an available translation from the existing lyrics settings; this switch does not start a translation request."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.string("Hide Desktop Lyrics When Paused"), isOn: binding(\.hideWhenPaused))
                HStack {
                    Spacer()
                    Button(L10n.string("Restore Defaults")) { settings.settings.desktopLyricsAppearance = DesktopLyricsAppearance() }
                }
            }.padding()
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<DesktopLyricsAppearance, Value>) -> Binding<Value> {
        Binding(get: { appearance[keyPath: key] }, set: { value in
            var next = settings.settings.desktopLyricsAppearance
            next[keyPath: key] = value
            settings.settings.desktopLyricsAppearance = DesktopLyricsAppearancePolicy.resolve(next)
        })
    }

    private func numberRow(_ title: String, _ key: WritableKeyPath<DesktopLyricsAppearance, Double>, _ range: ClosedRange<Double>, step: Double = 1) -> some View {
        HStack {
            Text(L10n.string(title)).frame(width: 170, alignment: .leading)
            Slider(value: binding(key), in: range, step: step)
            Text(appearance[keyPath: key], format: .number.precision(.fractionLength(step < 1 ? 2 : 0)))
                .monospacedDigit().frame(width: 45, alignment: .trailing)
        }
    }
}

struct DesktopLyricsPreview: View {
    let appearance: DesktopLyricsAppearance

    var body: some View {
        VStack(spacing: 4) {
            Text(L10n.string("Your favorite songs, with you through the day"))
                .font(.system(size: appearance.fontSize, weight: .semibold, design: .rounded))
            if appearance.showTranslation {
                Text(L10n.string("A second line can show an available translation"))
                    .font(.system(size: appearance.fontSize * 0.8, weight: .medium, design: .rounded))
            }
        }
        .lineLimit(1).minimumScaleFactor(0.6)
        .foregroundStyle(lyricColor)
        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: appearance.width)
        .background(.black.opacity(appearance.backgroundOpacity), in: RoundedRectangle(cornerRadius: 12))
        .clipped()
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private var lyricColor: Color {
        let rgb = MusicPlayerAppearancePolicy.rgbHexValue(appearance.customHex) ?? 0xFFFFFF
        return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
}
