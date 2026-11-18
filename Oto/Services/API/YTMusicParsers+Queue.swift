import Foundation
import OtoCore

/// Phân tích hàng đợi (Up Next / Radio) và kết quả tìm kiếm từ Innertube.
extension YTMusicParsers {
    // MARK: - Search

    public static func parseSongs(from data: Data) throws -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        guard let contents = json["contents"] as? [String: Any] else {
            throw YTMusicError.parsingError
        }

        var results: [Song] = []
        let sectionLists = extractSectionLists(from: contents)
        guard !sectionLists.isEmpty else {
            throw YTMusicError.parsingError
        }
        for section in sectionLists {
            guard let shelfContents = section["contents"] as? [[String: Any]] else { continue }
            for container in shelfContents {
                guard let musicShelf = container["musicShelfRenderer"] as? [String: Any],
                      let items = musicShelf["contents"] as? [[String: Any]] else {
                    continue
                }

                for item in items {
                    guard let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
                          let song = parseResponsiveListItem(renderer) else {
                        continue
                    }
                    results.append(song)
                }
            }
        }
        return results
    }

    // MARK: - Up Next / Radio Queue

    /// Phân tích danh sách hàng đợi phát tiếp theo (Up Next / Radio) từ YouTube Music.
    public static func parseUpNextQueue(from data: Data) throws -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        let renderers = collectRenderers(named: "playlistPanelVideoRenderer", in: json)
        guard !renderers.isEmpty else {
            return []
        }

        var results: [Song] = []
        for renderer in renderers {
            guard let videoId = renderer["videoId"] as? String, !videoId.isEmpty else {
                continue
            }

            let titleObj = renderer["title"] as? [String: Any]
            let titleRuns = titleObj?["runs"] as? [[String: Any]]
            let title = titleRuns?.first?["text"] as? String ?? ""
            guard !title.isEmpty else { continue }

            var artist = "Nhiều nghệ sĩ"
            var artists: [ArtistReference] = []
            var album: String?
            let byline = (renderer["longBylineText"] as? [String: Any])
                ?? (renderer["shortBylineText"] as? [String: Any])
            if let runs = byline?["runs"] as? [[String: Any]], !runs.isEmpty {
                artist = runs[0]["text"] as? String ?? "Nhiều nghệ sĩ"
                artists = extractArtists(from: byline)
                if runs.count >= 3 {
                    album = runs[2]["text"] as? String
                }
            }

            var duration: TimeInterval = 0
            if let lengthObj = renderer["lengthText"] as? [String: Any],
               let lengthRuns = lengthObj["runs"] as? [[String: Any]],
               let timeStr = lengthRuns.first?["text"] as? String {
                duration = parseDurationString(timeStr)
            }

            let song = Song(
                id: videoId,
                title: title,
                artist: artist,
                artists: artists,
                album: album,
                duration: duration,
                artworkURL: extractThumbnailURL(from: renderer["thumbnail"] as? [String: Any])
            )
            results.append(song)
        }
        return results
    }

    // MARK: - Two-Row Item

    public static func parseTwoRowItem(_ renderer: [String: Any]) -> Song? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let watch = nav?["watchEndpoint"] as? [String: Any]
        guard let videoId = watch?["videoId"] as? String, !videoId.isEmpty else {
            return nil
        }

        let titleRuns = (renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = titleRuns?.first?["text"] as? String
            ?? (renderer["title"] as? [String: Any])?["simpleText"] as? String
            ?? ""
        guard !title.isEmpty else { return nil }

        let subtitle = renderer["subtitle"] as? [String: Any]
        let artist = extractArtist(from: subtitle, fallback: "Nhiều nghệ sĩ")
        let artists = extractArtists(from: subtitle)

        let thumb = (renderer["thumbnailRenderer"] as? [String: Any]) ?? (renderer["thumbnail"] as? [String: Any])
        return Song(
            id: videoId, title: title, artist: artist, artists: artists, album: nil, duration: 0,
            artworkURL: extractThumbnailURL(from: thumb)
        )
    }

    // MARK: - Internal Section List Helpers

    static func extractSectionLists(from contents: [String: Any]) -> [[String: Any]] {
        if let direct = contents["sectionListRenderer"] as? [String: Any] { return [direct] }
        if let tabbed = contents["tabbedSearchResultsRenderer"] as? [String: Any],
           let tabs = tabbed["tabs"] as? [[String: Any]],
           let tabRenderer = tabs.first?["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionList = tabContent["sectionListRenderer"] as? [String: Any] {
            return [sectionList]
        }
        return []
    }
}
