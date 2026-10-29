import Foundation

@main
struct NeteasePolicyProbe {
    static func main() throws {
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        expect(NeteaseMusicPolicy.isSource("com.netease.163music"), "Native bundle")
        expect(!NeteaseMusicPolicy.isSource("com.netease.163music.fake"), "Reject another bundle")
        expect(!NeteaseMusicPolicy.isSource("com.spotify.client"), "Source isolation")
        expect(NeteaseMusicPolicy.canUseSystemTransport(activeBundleID: NeteaseMusicPolicy.bundleID), "Active NetEase uses system playback without AX")
        for other in [nil, "unknown", "com.spotify.client", "com.apple.Music", "com.netease.163music.fake"] as [String?] {
            expect(!NeteaseMusicPolicy.canUseSystemTransport(activeBundleID: other), "Never send a NetEase action to another active player")
        }
        for value in ["https://music.163.com/song?id=209226", "https://music.163.com/#/song?id=209226", "orpheus://song/209226"] {
            expect(NeteaseMusicPolicy.songID(value) == 209226, "Song URL: \(value)")
        }
        for value in ["209226", "https://evil.example/song?id=209226", "https://music.163.com/playlist?id=209226", "https://music.163.com/song?id=-1", "https://music.163.com/song?id=0", "https://music.163.com/song?id=99999999999999999999999", "688480E0-AF8B-4790-8EB7-80F71B31F438"] {
            expect(NeteaseMusicPolicy.songID(value) == nil, "Reject non-song identifier: \(value)")
        }
        let fixture = #"[{"id":209226,"name":"Day & Night","duration":252800,"artists":[{"name":"蔡健雅"}],"album":{"name":"I Do Believe"}},{"id":209091,"name":"Day And Night","duration":245960,"artists":[{"name":"蔡健雅"}],"album":{"name":"Jupiter"}}]"#
        let songs = try JSONDecoder().decode([NeteaseMusicPolicy.Song].self, from: Data(fixture.utf8))
        func match(_ songs: [NeteaseMusicPolicy.Song], artist: String = "蔡健雅", album: String? = "I Do Believe", duration: Double? = 252.865) -> Int64? {
            NeteaseMusicPolicy.matchingSong(songs, title: "Day & Night", artist: artist, album: album, duration: duration)
        }
        expect(match(songs) == 209226, "Match exact recording from real public response")
        expect(match(songs, artist: "Cover Artist") == nil, "Reject cover")
        expect(match(songs, album: "Live") == nil, "Reject different album")
        expect(match(songs, duration: 245) == nil, "Reject different duration")
        expect(match(songs, duration: nil) == nil, "No speculative lookup without duration")
        expect(match(songs, duration: .nan) == nil, "Reject invalid timing")
        let ambiguous = try JSONDecoder().decode([NeteaseMusicPolicy.Song].self, from: Data(fixture.replacingOccurrences(of: "209226", with: "209227").utf8))
        expect(match(songs + ambiguous) == nil, "Reject ambiguous recordings")
        let defaults = ["playlists", "devices", "like", "shuffle", "repeat"]
        let legacyEnabled: Set<String> = ["playlists", "devices"]
        let netease = MusicPlayerControlsPolicy.buttons(bundleID: NeteaseMusicPolicy.bundleID, isPhone: false, order: defaults, enabled: legacyEnabled, neteaseControlsEnabled: true)
        expect(netease == ["like", "playlists", "shuffle", "repeat", "devices"], "NetEase controls survive legacy disabled defaults; favorite and list occupy the main row")
        expect(MusicPlayerControlsPolicy.buttons(bundleID: NeteaseMusicPolicy.bundleID, isPhone: true, order: defaults, enabled: legacyEnabled, neteaseControlsEnabled: true).isEmpty, "Phone controls remain separate")
        expect(MusicPlayerControlsPolicy.buttons(bundleID: NeteaseMusicPolicy.bundleID, isPhone: false, order: [], enabled: [], neteaseControlsEnabled: true) == ["like", "playlists", "shuffle", "repeat"], "NetEase actions survive an old empty order")
        expect(MusicPlayerControlsPolicy.buttons(bundleID: NeteaseMusicPolicy.bundleID, isPhone: false, order: defaults, enabled: legacyEnabled, neteaseControlsEnabled: false) == ["devices"], "Explicit NetEase preference is respected")
        for bundle in ["com.spotify.client", "com.apple.Music", "com.apple.Safari"] {
            expect(MusicPlayerControlsPolicy.buttons(bundleID: bundle, isPhone: false, order: defaults, enabled: legacyEnabled, neteaseControlsEnabled: true) == ["playlists", "devices"], "Other services retain existing preferences")
        }
        expect(MusicPlayerControlsPolicy.supportsTrackActions(bundleID: NeteaseMusicPolicy.bundleID), "NetEase artwork double-tap supports favorite")
        print("NetEase identity, song URL, recording matching and ambiguity checks passed")
    }
}
