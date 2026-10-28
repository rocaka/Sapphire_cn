import Foundation

enum NeteaseMusicPolicy {
    static let bundleID = "com.netease.163music"

    static func isSource(_ key: String?) -> Bool {
        guard let key else { return false }
        return key == bundleID || key.hasPrefix(bundleID + ":")
    }

    /// Accept only song URLs belonging to NetEase, not an arbitrary numeric media ID.
    static func songID(_ value: String?) -> Int64? {
        guard let value, value.count < 2048, let url = URL(string: value) else { return nil }
        if url.scheme == "orpheus", url.host == "song" {
            return positiveID(url.lastPathComponent)
        }
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              ["music.163.com", "y.music.163.com"].contains(url.host?.lowercased() ?? "") else { return nil }
        let route = url.fragment.flatMap { URLComponents(string: "https://music.163.com" + ($0.hasPrefix("/") ? $0 : "/" + $0)) }
            ?? URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let route, route.path == "/song", let id = route.queryItems?.first(where: { $0.name == "id" })?.value else { return nil }
        return positiveID(id)
    }

    private static func positiveID(_ string: String) -> Int64? {
        guard !string.isEmpty, string.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int64(string), id > 0 else { return nil }
        return id
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace }
    }

    struct Song: Decodable {
        let id: Int64
        let name: String
        let duration: Double
        let artists: [Artist]
        let album: Album
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String }
    }

    /// Ambiguous matches are rejected rather than displaying another recording's lyrics.
    static func matchingSong(_ songs: [Song], title: String, artist: String, album: String?, duration: Double?) -> Int64? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        let matches = songs.filter { song in
            guard song.id > 0, normalized(song.name) == normalized(title),
                  abs(song.duration / 1000 - duration) <= 2 else { return false }
            let artistNames = song.artists.map { normalized($0.name) }
            let artistMatches = artistNames.contains(normalized(artist))
                || normalized(song.artists.map(\.name).joined(separator: "/")) == normalized(artist)
            guard artistMatches else { return false }
            if let album, !album.isEmpty { return normalized(song.album.name) == normalized(album) }
            return true
        }
        let ids = Set(matches.map(\.id))
        return ids.count == 1 ? ids.first : nil
    }
}
