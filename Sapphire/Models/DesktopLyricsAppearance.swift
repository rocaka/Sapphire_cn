import Foundation
import CoreGraphics

/// Desktop lyrics are opt-in presentation preferences. Decoding older settings
/// cannot enable a new desktop window or request any system permission.
struct DesktopLyricsAppearance: Codable, Equatable {
    var enabled = false
    var width: Double = 620
    var fontSize: Double = 22
    var verticalOffset: Double = 12
    var customHex = "#FFFFFF"
    var backgroundOpacity: Double = 0.2
    var showTranslation = false
    var hideWhenPaused = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, width, fontSize, verticalOffset, customHex, backgroundOpacity, showTranslation, hideWhenPaused
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? values.decode(T.self, forKey: key)) ?? fallback
        }
        enabled = value(.enabled, enabled)
        width = value(.width, width)
        fontSize = value(.fontSize, fontSize)
        verticalOffset = value(.verticalOffset, verticalOffset)
        customHex = value(.customHex, customHex)
        backgroundOpacity = value(.backgroundOpacity, backgroundOpacity)
        showTranslation = value(.showTranslation, showTranslation)
        hideWhenPaused = value(.hideWhenPaused, hideWhenPaused)
        self = DesktopLyricsAppearancePolicy.resolve(self)
    }
}

enum DesktopLyricsAppearancePolicy {
    static func resolve(_ raw: DesktopLyricsAppearance) -> DesktopLyricsAppearance {
        let defaults = DesktopLyricsAppearance()
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        var result = raw
        result.width = clamp(raw.width, 240...1000, defaults.width)
        result.fontSize = clamp(raw.fontSize, 12...48, defaults.fontSize)
        result.verticalOffset = clamp(raw.verticalOffset, 0...240, defaults.verticalOffset)
        result.backgroundOpacity = clamp(raw.backgroundOpacity, 0...1, defaults.backgroundOpacity)
        result.customHex = MusicPlayerAppearancePolicy.rgbHexValue(raw.customHex)
            .map { String(format: "#%06X", $0) } ?? defaults.customHex
        return result
    }

    /// AppKit screen coordinates. The anchor is the actual rendered notch or
    /// island, so custom island offsets and displays with negative origins work.
    static func frame(screenFrame: CGRect, anchorFrame: CGRect, appearance raw: DesktopLyricsAppearance, lineCount: Int) -> CGRect {
        guard [screenFrame.minX, screenFrame.minY, screenFrame.width, screenFrame.height,
               screenFrame.maxX, screenFrame.maxY, anchorFrame.minX, anchorFrame.minY,
               anchorFrame.width, anchorFrame.height, anchorFrame.midX].allSatisfy(\.isFinite),
              screenFrame.width > 0, screenFrame.height > 0 else { return .zero }
        let appearance = resolve(raw)
        let inset = min(16, min(screenFrame.width, screenFrame.height) / 4)
        let availableWidth = screenFrame.width - inset * 2
        let availableHeight = screenFrame.height - inset * 2
        let lines = min(2, max(1, lineCount))
        let width = min(appearance.width, availableWidth)
        let height = min(20 + appearance.fontSize * 1.5 * Double(lines) + Double(lines - 1) * 4, availableHeight)
        let minX = screenFrame.minX + inset
        let maxX = max(minX, screenFrame.maxX - inset - width)
        let minY = screenFrame.minY + inset
        let maxY = max(minY, screenFrame.maxY - inset - height)
        return CGRect(x: min(maxX, max(minX, anchorFrame.midX - width / 2)),
                      y: min(maxY, max(minY, anchorFrame.minY - appearance.verticalOffset - height)),
                      width: width, height: height)
    }
}
