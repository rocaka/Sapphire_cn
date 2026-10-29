import Foundation

enum DesktopLyricsVisibilityPolicy {
    struct Inputs {
        var enabled: Bool
        var locked: Bool
        var sleeping: Bool
        var appAllowed: Bool
        var hasAnchor: Bool
        var notchExpanded: Bool
        var isPlaying: Bool
        var hideWhenPaused: Bool
        var hasCurrentLyric: Bool
        var fullScreenHidden: Bool = false
    }

    static func needsLyrics(_ inputs: Inputs) -> Bool {
        inputs.enabled && !inputs.locked && !inputs.sleeping && inputs.appAllowed
            && inputs.hasAnchor && !inputs.notchExpanded && !inputs.fullScreenHidden
    }

    static func shouldDisplay(_ inputs: Inputs) -> Bool {
        needsLyrics(inputs) && inputs.hasCurrentLyric && (!inputs.hideWhenPaused || inputs.isPlaying)
    }
}
