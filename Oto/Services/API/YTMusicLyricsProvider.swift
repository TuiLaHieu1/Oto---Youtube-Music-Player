import Foundation
import OtoCore

extension MultiSourceLyricsService {
    public static let otoShared = MultiSourceLyricsService(providers: [
        LRCLibProvider(),
        YTMusicLyricsProvider()
    ])
}

/// Nguồn lời YouTube Music dùng cùng phiên API catalog của Oto.
struct YTMusicLyricsProvider: LyricsProvider {
    let providerName = "YouTube Music"
    private let client: YTMusicClient

    init(client: YTMusicClient = .shared) {
        self.client = client
    }

    func fetchLyrics(for song: Song) async throws -> LyricsDocument? {
        let nextData = try await client.fetchLyricsNext(videoId: song.id)
        if let timed = YTMusicLyricsParser.parseTimed(from: nextData) {
            return timed
        }
        guard let browseID = YTMusicLyricsParser.lyricsBrowseID(from: nextData) else {
            return nil
        }
        let browseData = try await client.fetchLyricsBrowse(browseId: browseID)
        return YTMusicLyricsParser.parseTimed(from: browseData)
            ?? YTMusicLyricsParser.parsePlain(from: browseData)
    }
}

extension YTMusicClient {
    func fetchLyricsNext(videoId: String) async throws -> Data {
        let trimmed = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://music.youtube.com/youtubei/v1/next?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }
        var request = makeBaseRequest(url: url)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": clientContext,
            "videoId": trimmed,
            "isAudioOnly": true,
            "enablePersistentPlaylistPanel": true
        ])
        return try await perform(request, operation: "lyrics-next")
    }

    func fetchLyricsBrowse(browseId: String) async throws -> Data {
        guard browseId.hasPrefix("MPLYt"),
              let url = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }
        var request = makeBaseRequest(url: url)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": clientContext,
            "browseId": browseId
        ])
        return try await perform(request, operation: "lyrics-browse")
    }
}

enum YTMusicLyricsParser {
    static func lyricsBrowseID(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findLyricsBrowseID(in: root)
    }

    static func parseTimed(from data: Data) -> LyricsDocument? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let model = findRenderer(named: "timedLyricsModel", in: root),
              let lyricData = model["lyricsData"] as? [[String: Any]] else { return nil }

        let lines = lyricData.compactMap { entry -> LyricsLine? in
            guard let text = entry["lyricLine"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let start = milliseconds(entry["startTimeMs"]),
                  start >= 0 else { return nil }
            let duration = milliseconds(entry["durationMs"])
            return LyricsLine(
                startTime: Double(start) / 1_000,
                endTime: duration.map { Double(start + $0) / 1_000 },
                text: text
            )
        }.sorted { $0.startTime < $1.startTime }
        guard !lines.isEmpty else { return nil }
        return LyricsDocument(type: .synced, lines: lines, source: "YouTube Music")
    }

    static func parsePlain(from data: Data) -> LyricsDocument? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let shelf = findRenderer(named: "musicDescriptionShelfRenderer", in: root),
              let description = shelf["description"] as? [String: Any],
              let runs = description["runs"] as? [[String: Any]] else { return nil }
        let text = runs.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let footer = shelf["footer"] as? [String: Any]
        let footerRuns = footer?["runs"] as? [[String: Any]] ?? []
        let attribution = footerRuns.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = attribution.isEmpty ? "YouTube Music" : "YouTube Music · \(attribution)"
        return LyricsDocument(type: .plain, plainLyrics: text, source: source)
    }

    private static func milliseconds(_ value: Any?) -> Int? {
        if let text = value as? String { return Int(text) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func findLyricsBrowseID(in node: Any) -> String? {
        if let dictionary = node as? [String: Any] {
            if let endpoint = dictionary["browseEndpoint"] as? [String: Any],
               let browseID = endpoint["browseId"] as? String,
               browseID.hasPrefix("MPLYt") { return browseID }
            for child in dictionary.values {
                if let found = findLyricsBrowseID(in: child) { return found }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let found = findLyricsBrowseID(in: child) { return found }
            }
        }
        return nil
    }

    private static func findRenderer(named name: String, in node: Any) -> [String: Any]? {
        if let dictionary = node as? [String: Any] {
            if let renderer = dictionary[name] as? [String: Any] { return renderer }
            for child in dictionary.values {
                if let found = findRenderer(named: name, in: child) { return found }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let found = findRenderer(named: name, in: child) { return found }
            }
        }
        return nil
    }
}
