import Foundation

@main struct MusicPlayerAppearanceProbe {
    static func main() throws {
        let decoder = JSONDecoder()
        let defaults = MusicPlayerAppearance()
        let missing = try decoder.decode(MusicPlayerAppearance.self, from: Data("{}".utf8))
        precondition(missing == defaults)
        let partial = try decoder.decode(MusicPlayerAppearance.self, from: Data(#"{"width":480,"showArtist":false,"accentMode":"future","artworkSize":"invalid"}"#.utf8))
        precondition(partial.width == 480 && !partial.showArtist && partial.accentMode == .artwork && partial.artworkSize == 56)
        precondition(partial.neteaseUseIndependentButtons == false)
        let permissive = JSONDecoder()
        permissive.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let importedNonfinite = try permissive.decode(MusicPlayerAppearance.self, from: Data(#"{"width":"NaN","artworkSize":"Infinity","controlsScale":"-Infinity"}"#.utf8))
        precondition(importedNonfinite.width == 400 && importedNonfinite.artworkSize == 56 && importedNonfinite.controlsScale == 1)
        let encoded = try JSONEncoder().encode(MusicPlayerAppearancePreset.largeText.appearance)
        let roundTrip = try decoder.decode(MusicPlayerAppearance.self, from: encoded)
        precondition(roundTrip == MusicPlayerAppearancePreset.largeText.appearance)

        var extreme = defaults
        extreme.width = .infinity; extreme.artworkSize = .nan; extreme.artworkCornerRadius = 1e30
        extreme.titleFontSize = -.infinity; extreme.artistFontSize = -50; extreme.lyricsFontSize = 1e30
        extreme.controlsScale = .nan; extreme.customHex = "javascript:alert(1)"
        let clean = MusicPlayerAppearancePolicy.resolve(extreme)
        precondition(clean.width == 400 && clean.artworkSize == 56 && clean.artworkCornerRadius == 28)
        precondition(clean.titleFontSize == 15 && clean.artistFontSize == 10 && clean.lyricsFontSize == 22 && clean.controlsScale == 1)
        precondition(clean.customHex == defaults.customHex)
        _ = try JSONEncoder().encode(clean)
        for width in [1.0, 200, 280, 320, 400, 560, 10_000] {
            let value = MusicPlayerAppearancePolicy.resolve(extreme, maximumContentWidth: width)
            precondition(value.width <= width && value.width > 0)
            precondition(value.artworkSize <= value.width * 0.3 && value.artworkCornerRadius <= value.artworkSize / 2)
            precondition(value.controlsScale * 320 <= value.width)
        }
        precondition(MusicPlayerAppearancePolicy.resolve(defaults, maximumContentWidth: .nan).width == 400)
        precondition(MusicPlayerAppearancePolicy.rgbHexValue(" #f80 ") == 0xFF8800)
        precondition(MusicPlayerAppearancePolicy.rgbHexValue("#zzzzzz") == nil)
        precondition(MusicPlayerAppearancePolicy.rgbHexValue("#FF8800AA") == nil)

        var buttons = defaults
        buttons.neteaseButtonOrder = ["unknown", "repeat", "like", "repeat"]
        buttons.neteaseHiddenButtons = ["like", "unknown", "like"]
        precondition(NeteasePlayerButtonPolicy.visibleButtons(in: buttons) == nil, "Default must preserve existing recommended behavior")
        buttons.neteaseUseIndependentButtons = true
        precondition(NeteasePlayerButtonPolicy.visibleButtons(in: buttons) == ["repeat", "playlists", "shuffle", "devices"])
        buttons.neteaseHiddenButtons = NeteasePlayerButtonPolicy.defaultOrder
        precondition(NeteasePlayerButtonPolicy.visibleButtons(in: buttons) == [])
        precondition(NeteasePlayerButtonPolicy.normalizedOrder([]) == ["like", "playlists", "shuffle", "repeat", "devices"])
        print("Music player appearance: tolerant Codable, finite clamps, narrow display bounds, presets, colors and independent NetEase controls passed")
    }
}
