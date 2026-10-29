import Foundation
import CoreGraphics

@main struct DesktopLyricsProbe {
    static func main() throws {
        let defaults = DesktopLyricsAppearance()
        precondition(!defaults.enabled)
        let missing = try JSONDecoder().decode(DesktopLyricsAppearance.self, from: Data("{}".utf8))
        precondition(missing == defaults)
        let migrated = try JSONDecoder().decode(DesktopLyricsAppearance.self, from: Data(#"{"fontSize":32,"showTranslation":true,"width":"bad"}"#.utf8))
        precondition(!migrated.enabled && migrated.width == 620 && migrated.fontSize == 32 && migrated.showTranslation)
        let roundTrip = try JSONDecoder().decode(DesktopLyricsAppearance.self, from: JSONEncoder().encode(migrated))
        precondition(roundTrip == migrated)
        var invalid = defaults
        invalid.width = .infinity; invalid.fontSize = .nan; invalid.verticalOffset = -100
        invalid.backgroundOpacity = 10; invalid.customHex = "#z00"
        let clean = DesktopLyricsAppearancePolicy.resolve(invalid)
        precondition(clean.width == 620 && clean.fontSize == 22 && clean.verticalOffset == 0 && clean.backgroundOpacity == 1 && clean.customHex == "#FFFFFF")
        invalid.customHex = "#f80"
        precondition(DesktopLyricsAppearancePolicy.resolve(invalid).customHex == "#FF8800")
        let permissive = JSONDecoder()
        permissive.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let imported = try permissive.decode(DesktopLyricsAppearance.self, from: Data(#"{"width":"Infinity","fontSize":"NaN","backgroundOpacity":"-Infinity"}"#.utf8))
        precondition(imported == defaults)

        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                       CGRect(x: 300, y: 900, width: 100, height: 400), CGRect(x: 0, y: 0, width: 1, height: 1)] {
            for offset in [0.0, 12, 240] {
                for count in [-1, 1, 2, 100] {
                    var value = defaults
                    value.width = 1000; value.fontSize = 48; value.verticalOffset = offset
                    let anchor = CGRect(x: screen.midX - 100, y: screen.maxY - 40, width: 200, height: 40)
                    let frame = DesktopLyricsAppearancePolicy.frame(screenFrame: screen, anchorFrame: anchor, appearance: value, lineCount: count)
                    precondition(frame.width > 0 && frame.height > 0)
                    precondition(frame.minX >= screen.minX && frame.maxX <= screen.maxX && frame.minY >= screen.minY && frame.maxY <= screen.maxY)
                }
            }
        }
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let island = CGRect(x: 620, y: 820, width: 200, height: 32)
        let underIsland = DesktopLyricsAppearancePolicy.frame(screenFrame: screen, anchorFrame: island, appearance: defaults, lineCount: 1)
        precondition(underIsland.midX == island.midX && underIsland.maxY == island.minY - defaults.verticalOffset)
        precondition(DesktopLyricsAppearancePolicy.frame(screenFrame: .zero, anchorFrame: island, appearance: defaults, lineCount: 1) == .zero)
        precondition(DesktopLyricsAppearancePolicy.frame(screenFrame: CGRect(x: Double.infinity, y: 0, width: 1440, height: 900), anchorFrame: island, appearance: defaults, lineCount: 1) == .zero)
        precondition(DesktopLyricsAppearancePolicy.frame(screenFrame: CGRect(x: Double.greatestFiniteMagnitude, y: 0, width: Double.greatestFiniteMagnitude, height: 900), anchorFrame: island, appearance: defaults, lineCount: 1) == .zero)

        var tick = MusicPlaybackTickPolicy.Inputs(isPlaying: true, isDetailPlayerOpen: false, isLyricsDetailOpen: false,
            isDetachedLyricsOpen: false, isMusicLiveActivityActive: false, musicLiveActivityEnabled: false,
            showLyricsInLiveActivity: false, lyricsAllowedForActiveApp: true, hasLyrics: true,
            showNextSong: true, upNextSourceSupported: true)
        precondition(MusicPlaybackTickPolicy.interval(for: tick) == nil, "Disabled desktop lyrics must add no timer")
        tick.desktopLyricsActive = true
        precondition(MusicPlaybackTickPolicy.interval(for: tick) == 0.5)
        let lines = [LyricLine(text: "one", timestamp: 1, endTimestamp: 2), LyricLine(text: "two", timestamp: 3, endTimestamp: 4)]
        let delay = MusicPlaybackTickPolicy.nextLiveActivityEventDelay(for: tick, elapsed: 1.25, lyricsElapsed: 1.25, lyrics: lines, duration: 100)
        precondition(delay == 0.75, "Desktop lyrics must use the next line boundary, even with live activity off")
        let noUpNext = MusicPlaybackTickPolicy.nextLiveActivityEventDelay(for: tick, elapsed: 80, lyricsElapsed: 80, lyrics: lines, duration: 100)
        precondition(noUpNext == 20, "Desktop lyrics must not activate the independent up-next feature")
        tick.isPlaying = false
        precondition(MusicPlaybackTickPolicy.interval(for: tick) == nil)
        precondition(MusicPlaybackTickPolicy.nextLiveActivityEventDelay(for: tick, elapsed: 1, lyricsElapsed: 1, lyrics: lines, duration: 100) == nil)
        tick.isPlaying = true; tick.hasLyrics = false
        precondition(MusicPlaybackTickPolicy.interval(for: tick) == nil, "No lyric polling when the source has no lyrics")

        var visibility = DesktopLyricsVisibilityPolicy.Inputs(enabled: true, locked: false, sleeping: false,
            appAllowed: true, hasAnchor: true, notchExpanded: false, isPlaying: true,
            hideWhenPaused: true, hasCurrentLyric: false)
        precondition(DesktopLyricsVisibilityPolicy.needsLyrics(visibility), "Initial lyric demand must not depend on already having a lyric")
        precondition(!DesktopLyricsVisibilityPolicy.shouldDisplay(visibility))
        visibility.hasCurrentLyric = true
        precondition(DesktopLyricsVisibilityPolicy.shouldDisplay(visibility))
        visibility.isPlaying = false
        precondition(!DesktopLyricsVisibilityPolicy.shouldDisplay(visibility))
        visibility.hideWhenPaused = false
        precondition(DesktopLyricsVisibilityPolicy.shouldDisplay(visibility))
        for key in [\DesktopLyricsVisibilityPolicy.Inputs.locked, \.sleeping, \.notchExpanded, \.fullScreenHidden] {
            var hidden = visibility
            hidden[keyPath: key] = true
            precondition(!DesktopLyricsVisibilityPolicy.needsLyrics(hidden) && !DesktopLyricsVisibilityPolicy.shouldDisplay(hidden))
        }
        for key in [\DesktopLyricsVisibilityPolicy.Inputs.enabled, \.hasAnchor, \.appAllowed] {
            var hidden = visibility
            hidden[keyPath: key] = false
            precondition(!DesktopLyricsVisibilityPolicy.needsLyrics(hidden) && !DesktopLyricsVisibilityPolicy.shouldDisplay(hidden))
        }
        print("Desktop lyrics: opt-in migration, finite preferences, screen/island geometry, and shared event-driven lyric timer passed")
    }
}
