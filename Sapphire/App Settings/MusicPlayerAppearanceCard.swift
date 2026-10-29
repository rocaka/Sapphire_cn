import SwiftUI

struct MusicPlayerAppearanceCard: View {
    @EditingSettings var settings: SettingsEditingSession

    private var appearance: MusicPlayerAppearance {
        MusicPlayerAppearancePolicy.resolve(settings.settings.musicPlayerAppearance)
    }

    var body: some View {
        SettingsCard(title: "Music Player Appearance", description: "Customize player size, artwork, text, colors and NetEase buttons.") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.string("Presets"))
                    ForEach(MusicPlayerAppearancePreset.allCases) { preset in
                        Button(L10n.string(presetTitle(preset))) { applyPreset(preset) }
                    }
                    Spacer()
                    Button(L10n.string("Restore Defaults")) { settings.settings.musicPlayerAppearance = MusicPlayerAppearance() }
                }
                MusicPlayerAppearancePreview(appearance: appearance)
                    .frame(maxWidth: .infinity)
                Text(L10n.string("Static preview. Your current song and playback are unchanged."))
                    .font(.caption).foregroundStyle(.secondary)
                numberRow("Player Width", \.width, 320...560)
                numberRow("Artwork Size", \.artworkSize, 40...96)
                numberRow("Artwork Corner Radius", \.artworkCornerRadius, 0...32)
                numberRow("Title Font Size", \.titleFontSize, 12...28)
                numberRow("Artist Font Size", \.artistFontSize, 10...22)
                numberRow("Control Size", \.controlsScale, 0.8...1.25, step: 0.01)
                numberRow("Lyrics Font Size", \.lyricsFontSize, 12...22)
                HStack {
                    Toggle(L10n.string("Show Artwork"), isOn: binding(\.showArtwork))
                    Toggle(L10n.string("Show Artist"), isOn: binding(\.showArtist))
                }
                HStack {
                    Toggle(L10n.string("Show Progress"), isOn: binding(\.showProgress))
                    Toggle(L10n.string("Show Lyrics"), isOn: binding(\.showLyrics))
                }
                Picker(L10n.string("Accent Color"), selection: binding(\.accentMode)) {
                    ForEach(MusicPlayerAccentMode.allCases) { mode in Text(L10n.string(accentTitle(mode))).tag(mode) }
                }
                if appearance.accentMode == .custom {
                    TextField(L10n.string("Hex Color"), text: Binding(
                        get: { settings.settings.musicPlayerAppearance.customHex },
                        set: { settings.settings.musicPlayerAppearance.customHex = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text(L10n.string("Enter a color such as #FF9F0A. Invalid colors use the default."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle(L10n.string("Customize NetEase Buttons Separately"), isOn: binding(\.neteaseUseIndependentButtons))
                Text(L10n.string("Off keeps the existing recommended controls. On lets you show, hide and reorder NetEase controls only."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(appearance.neteaseButtonOrder.enumerated()), id: \.element) { index, raw in
                    HStack {
                        Toggle(L10n.string(buttonTitle(raw)), isOn: buttonVisibility(raw))
                        Spacer()
                        Button { moveButton(at: index, by: -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0).help(L10n.string("Move Up"))
                        Button { moveButton(at: index, by: 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(index == appearance.neteaseButtonOrder.count - 1).help(L10n.string("Move Down"))
                    }
                    .disabled(!appearance.neteaseUseIndependentButtons)
                }
            }.padding()
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<MusicPlayerAppearance, Value>) -> Binding<Value> {
        Binding(get: { appearance[keyPath: key] }, set: { value in
            var next = settings.settings.musicPlayerAppearance
            next[keyPath: key] = value
            settings.settings.musicPlayerAppearance = MusicPlayerAppearancePolicy.resolve(next)
        })
    }

    private func numberRow(_ title: String, _ key: WritableKeyPath<MusicPlayerAppearance, Double>, _ range: ClosedRange<Double>, step: Double = 1) -> some View {
        HStack {
            Text(L10n.string(title)).frame(width: 155, alignment: .leading)
            Slider(value: binding(key), in: range, step: step)
            Text(appearance[keyPath: key], format: .number.precision(.fractionLength(step < 1 ? 2 : 0)))
                .monospacedDigit().frame(width: 45, alignment: .trailing)
        }
    }

    private func applyPreset(_ preset: MusicPlayerAppearancePreset) {
        var next = preset.appearance
        next.neteaseUseIndependentButtons = appearance.neteaseUseIndependentButtons
        next.neteaseButtonOrder = appearance.neteaseButtonOrder
        next.neteaseHiddenButtons = appearance.neteaseHiddenButtons
        settings.settings.musicPlayerAppearance = next
    }

    private func buttonVisibility(_ raw: String) -> Binding<Bool> {
        Binding(get: { !appearance.neteaseHiddenButtons.contains(raw) }, set: { visible in
            var next = appearance
            next.neteaseHiddenButtons.removeAll { $0 == raw }
            if !visible { next.neteaseHiddenButtons.append(raw) }
            settings.settings.musicPlayerAppearance = next
        })
    }

    private func moveButton(at index: Int, by offset: Int) {
        var next = appearance
        let destination = index + offset
        guard next.neteaseButtonOrder.indices.contains(index), next.neteaseButtonOrder.indices.contains(destination) else { return }
        next.neteaseButtonOrder.swapAt(index, destination)
        settings.settings.musicPlayerAppearance = next
    }

    private func presetTitle(_ preset: MusicPlayerAppearancePreset) -> String {
        switch preset { case .standard: "Default"; case .compact: "Compact"; case .largeText: "Large Text" }
    }
    private func accentTitle(_ mode: MusicPlayerAccentMode) -> String {
        switch mode { case .artwork: "Album Artwork"; case .white: "White"; case .system: "System Accent"; case .custom: "Custom Color" }
    }
    private func buttonTitle(_ raw: String) -> String {
        switch raw { case "like": "Like"; case "playlists": "Queue & Playlists"; case "shuffle": "Shuffle"; case "repeat": "Repeat"; case "devices": "Devices"; default: raw }
    }
}
