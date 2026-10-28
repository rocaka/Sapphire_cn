import Foundation

/// Public song/lyric data only. Does not access the client's cookies, login or history.
struct NeteaseLyricsProvider {
    private struct SearchResponse: Decodable {
        let code: Int
        let result: Result?
        struct Result: Decodable { let songs: [NeteaseMusicPolicy.Song]? }
    }
    private struct Response: Decodable {
        let code: Int
        let lrc: Text?
        let tlyric: Text?
        struct Text: Decodable { let lyric: String? }
    }

    func lyrics(identifiers: [String?], title: String, artist: String, album: String?, duration: Double?) async -> [LyricLine]? {
        do {
            var id = identifiers.compactMap { NeteaseMusicPolicy.songID($0) }.first
            if id == nil {
                var search = URLComponents(string: "https://music.163.com/api/search/get")!
                search.queryItems = [URLQueryItem(name: "s", value: title + " " + artist), URLQueryItem(name: "type", value: "1"), URLQueryItem(name: "limit", value: "10")]
                let response = try JSONDecoder().decode(SearchResponse.self, from: await data(search.url!))
                guard response.code == 200 else { return nil }
                id = NeteaseMusicPolicy.matchingSong(response.result?.songs ?? [], title: title, artist: artist, album: album, duration: duration)
            }
            guard let id, !Task.isCancelled else { return nil }
            let url = URL(string: "https://music.163.com/api/song/lyric?id=\(id)&lv=-1&tv=-1")!
            let response = try JSONDecoder().decode(Response.self, from: await data(url))
            guard response.code == 200, let lrc = response.lrc?.lyric,
                  var lines = LyricsParser.parseLRC(lrc), !lines.isEmpty else { return nil }
            if let text = response.tlyric?.lyric, let translated = LyricsParser.parseLRC(text) {
                // Linear merge; translations belong only to the same timestamp.
                var index = 0
                for i in lines.indices {
                    while index < translated.count, translated[index].timestamp < lines[i].timestamp - 0.05 { index += 1 }
                    if index < translated.count, abs(translated[index].timestamp - lines[i].timestamp) <= 0.05 {
                        lines[i].translatedText = translated[index].text
                    }
                }
            }
            return lines
        } catch { return nil } // Existing providers remain available offline / on API changes.
    }

    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        // Ephemeral session deliberately excludes any saved NetEase account cookies.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              bytes.count <= 4_194_304 else { throw URLError(.badServerResponse) }
        return bytes
    }
}
