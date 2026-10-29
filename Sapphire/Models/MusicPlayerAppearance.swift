import Foundation

enum MusicPlayerAccentMode: String, Codable, CaseIterable, Identifiable {
    case artwork, white, system, custom
    var id: String { rawValue }
}

/// One version-tolerant settings value. It contains presentation preferences
/// only and never starts a player, account request or permission prompt.
struct MusicPlayerAppearance: Codable, Equatable {
    var width: Double = 400
    var artworkSize: Double = 56
    var artworkCornerRadius: Double = 12
    var titleFontSize: Double = 15
    var artistFontSize: Double = 12
    var controlsScale: Double = 1
    var lyricsFontSize: Double = 12
    var showArtwork = true
    var showArtist = true
    var showProgress = true
    var showLyrics = true
    var accentMode: MusicPlayerAccentMode = .artwork
    var customHex = "#FF9F0A"
    var neteaseUseIndependentButtons = false
    var neteaseButtonOrder = NeteasePlayerButtonPolicy.defaultOrder
    var neteaseHiddenButtons: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case width, artworkSize, artworkCornerRadius, titleFontSize, artistFontSize, controlsScale, lyricsFontSize
        case showArtwork, showArtist, showProgress, showLyrics, accentMode, customHex
        case neteaseUseIndependentButtons, neteaseButtonOrder, neteaseHiddenButtons
    }

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decode(T.self, forKey: key)) ?? fallback
        }
        width = value(.width, width)
        artworkSize = value(.artworkSize, artworkSize)
        artworkCornerRadius = value(.artworkCornerRadius, artworkCornerRadius)
        titleFontSize = value(.titleFontSize, titleFontSize)
        artistFontSize = value(.artistFontSize, artistFontSize)
        controlsScale = value(.controlsScale, controlsScale)
        lyricsFontSize = value(.lyricsFontSize, lyricsFontSize)
        showArtwork = value(.showArtwork, showArtwork)
        showArtist = value(.showArtist, showArtist)
        showProgress = value(.showProgress, showProgress)
        showLyrics = value(.showLyrics, showLyrics)
        accentMode = value(.accentMode, accentMode)
        customHex = value(.customHex, customHex)
        neteaseUseIndependentButtons = value(.neteaseUseIndependentButtons, neteaseUseIndependentButtons)
        neteaseButtonOrder = value(.neteaseButtonOrder, neteaseButtonOrder)
        neteaseHiddenButtons = value(.neteaseHiddenButtons, neteaseHiddenButtons)
        self = MusicPlayerAppearancePolicy.resolve(self)
    }
}

enum MusicPlayerAppearancePreset: String, CaseIterable, Identifiable {
    case standard, compact, largeText
    var id: String { rawValue }

    var appearance: MusicPlayerAppearance {
        var result = MusicPlayerAppearance()
        switch self {
        case .standard: break
        case .compact:
            result.width = 340
            result.artworkSize = 48
            result.artworkCornerRadius = 10
            result.titleFontSize = 14
            result.artistFontSize = 11
            result.controlsScale = 0.9
        case .largeText:
            result.width = 480
            result.artworkSize = 72
            result.titleFontSize = 20
            result.artistFontSize = 16
            result.lyricsFontSize = 18
            result.controlsScale = 1.15
        }
        return result
    }
}

enum NeteasePlayerButtonPolicy {
    static let defaultOrder = ["like", "playlists", "shuffle", "repeat", "devices"]
    private static let known = Set(defaultOrder)

    static func normalizedOrder(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return (Array(raw.prefix(128)) + defaultOrder).filter { known.contains($0) && seen.insert($0).inserted }
    }

    static func normalizedHidden(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.prefix(128).filter { known.contains($0) && seen.insert($0).inserted }
    }

    /// nil preserves the existing source-specific recommendation and settings.
    static func visibleButtons(in appearance: MusicPlayerAppearance) -> [String]? {
        guard appearance.neteaseUseIndependentButtons else { return nil }
        let hidden = Set(normalizedHidden(appearance.neteaseHiddenButtons))
        return normalizedOrder(appearance.neteaseButtonOrder).filter { !hidden.contains($0) }
    }
}

enum MusicPlayerAppearancePolicy {
    static func resolve(_ raw: MusicPlayerAppearance, maximumContentWidth: Double = 560) -> MusicPlayerAppearance {
        let defaults = MusicPlayerAppearance()
        func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        var result = raw
        let available = maximumContentWidth.isFinite && maximumContentWidth > 0 ? maximumContentWidth : 560
        result.width = min(available, clamp(raw.width, 320...560, fallback: defaults.width))
        result.artworkSize = min(result.width * 0.3, clamp(raw.artworkSize, 40...96, fallback: defaults.artworkSize))
        result.artworkCornerRadius = min(result.artworkSize / 2, clamp(raw.artworkCornerRadius, 0...32, fallback: defaults.artworkCornerRadius))
        result.titleFontSize = clamp(raw.titleFontSize, 12...28, fallback: defaults.titleFontSize)
        result.artistFontSize = clamp(raw.artistFontSize, 10...22, fallback: defaults.artistFontSize)
        result.lyricsFontSize = clamp(raw.lyricsFontSize, 12...22, fallback: defaults.lyricsFontSize)
        // The display bound outranks nominal minimums on unusually narrow screens.
        result.controlsScale = min(result.width / 320, clamp(raw.controlsScale, 0.8...1.25, fallback: defaults.controlsScale))
        result.customHex = rgbHexValue(raw.customHex).map { String(format: "#%06X", $0) } ?? defaults.customHex
        result.neteaseButtonOrder = NeteasePlayerButtonPolicy.normalizedOrder(raw.neteaseButtonOrder)
        result.neteaseHiddenButtons = NeteasePlayerButtonPolicy.normalizedHidden(raw.neteaseHiddenButtons)
        return result
    }

    static func rgbHexValue(_ raw: String) -> UInt32? {
        guard raw.utf8.count <= 16 else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value) }) else { return nil }
        return UInt32(text, radix: 16)
    }
}
