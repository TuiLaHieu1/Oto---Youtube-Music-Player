import Foundation
import OtoCore

/// Bộ phân tích dữ liệu JSON từ Innertube API của YouTube Music với kiểm tra schema chẩn đoán lỗi.
public enum YTMusicParsers {
    // MARK: - Internal Helpers

    /// Innertube thường thêm wrapper vào Home feed. Chỉ tìm renderer theo key cụ thể,
    /// không biến mọi shelf lạ thành nội dung cá nhân hóa.
    static func collectRenderers(named name: String, in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var results: [[String: Any]] = []
            if let renderer = dictionary[name] as? [String: Any] {
                results.append(renderer)
            }
            for child in dictionary.values {
                results.append(contentsOf: collectRenderers(named: name, in: child))
            }
            return results
        }

        if let array = value as? [Any] {
            return array.flatMap { collectRenderers(named: name, in: $0) }
        }

        return []
    }

    // MARK: - Playlists & Liked Songs

    public static func parsePlaylistOrShelfSongs(from data: Data) throws -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        let itemRenderers = collectRenderers(named: "musicResponsiveListItemRenderer", in: json)
        var results: [Song] = []
        for renderer in itemRenderers {
            if let song = parseResponsiveListItem(renderer) {
                results.append(song)
            }
        }

        guard !results.isEmpty else {
            throw YTMusicError.parsingError
        }
        return results
    }

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

    // MARK: - Item Renderers

    public static func parseResponsiveListItem(_ renderer: [String: Any]) -> Song? {
        guard let flexColumns = renderer["flexColumns"] as? [[String: Any]], !flexColumns.isEmpty else {
            return nil
        }

        var videoId: String?
        if let playlistItemData = renderer["playlistItemData"] as? [String: Any] {
            videoId = playlistItemData["videoId"] as? String
        }

        let col0 = flexColumns[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        let col0Runs = (col0?["text"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = col0Runs?.first?["text"] as? String ?? ""

        if videoId == nil, let runs = col0Runs, let firstRun = runs.first {
            let nav = firstRun["navigationEndpoint"] as? [String: Any]
            let watch = nav?["watchEndpoint"] as? [String: Any]
            videoId = watch?["videoId"] as? String
        }

        guard let id = videoId, !id.isEmpty, !title.isEmpty else { return nil }

        var artist = "Nhiều nghệ sĩ"
        var album: String?
        var duration: TimeInterval = 0

        if flexColumns.count > 1 {
            let col1 = flexColumns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
            let col1Runs = (col1?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []

            if !col1Runs.isEmpty {
                artist = col1Runs[0]["text"] as? String ?? "Nhiều nghệ sĩ"
            }
            if col1Runs.count >= 3 {
                album = col1Runs[2]["text"] as? String
            }
            if let lastText = col1Runs.last?["text"] as? String, lastText.contains(":") {
                duration = parseDurationString(lastText)
            }
        }

        return Song(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: extractThumbnailURL(from: renderer["thumbnail"] as? [String: Any])
        )
    }
}

// MARK: - Helper Parsers & Queue

extension YTMusicParsers {
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
            var album: String?
            let byline = (renderer["longBylineText"] as? [String: Any])
                ?? (renderer["shortBylineText"] as? [String: Any])
            if let runs = byline?["runs"] as? [[String: Any]], !runs.isEmpty {
                artist = runs[0]["text"] as? String ?? "Nhiều nghệ sĩ"
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
                album: album,
                duration: duration,
                artworkURL: extractThumbnailURL(from: renderer["thumbnail"] as? [String: Any])
            )
            results.append(song)
        }
        return results
    }

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

        let subRuns = (renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]
        let artist = subRuns?.first?["text"] as? String
            ?? (renderer["subtitle"] as? [String: Any])?["simpleText"] as? String
            ?? "Nhiều nghệ sĩ"

        let thumbContainer = (renderer["thumbnailRenderer"] as? [String: Any])
            ?? (renderer["thumbnail"] as? [String: Any])

        return Song(
            id: videoId,
            title: title,
            artist: artist,
            album: nil,
            duration: 0,
            artworkURL: extractThumbnailURL(from: thumbContainer)
        )
    }

    private static func extractSectionLists(from contents: [String: Any]) -> [[String: Any]] {
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

    public static func upgradeThumbnailURLString(_ urlStr: String) -> String {
        var result = urlStr
        if result.contains("i.ytimg.com/vi/") {
            if let sqpIndex = result.range(of: "?sqp=")?.lowerBound {
                result = String(result[..<sqpIndex])
            }
            result = result.replacingOccurrences(of: "/default.jpg", with: "/hqdefault.jpg")
                .replacingOccurrences(of: "/mqdefault.jpg", with: "/hqdefault.jpg")
            return result
        }
        let range = NSRange(location: 0, length: result.utf16.count)
        if result.contains("=w"), let regex = try? NSRegularExpression(pattern: "=w\\d+-h\\d+.*") {
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "=w800-h800-l90-rj")
        } else if result.contains("=s"), let regex = try? NSRegularExpression(pattern: "=s\\d+.*") {
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "=s800-c")
        }
        return result
    }

    static func extractThumbnailURL(from container: [String: Any]?) -> URL? {
        guard let container else { return nil }
        let musicThumb = container["musicThumbnailRenderer"] as? [String: Any]
        let thumbObj = (musicThumb?["thumbnail"] as? [String: Any])
            ?? (container["thumbnail"] as? [String: Any])
            ?? container
        let thumbs = (thumbObj["thumbnails"] as? [[String: Any]])
            ?? (container["thumbnails"] as? [[String: Any]])
        guard let lastThumb = thumbs?.last,
              let urlStr = lastThumb["url"] as? String else {
            return nil
        }
        return URL(string: upgradeThumbnailURLString(urlStr))
    }

    private static func parseDurationString(_ text: String) -> TimeInterval {
        let parts = text.components(separatedBy: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 { return (parts[0] * 60) + parts[1] }
        if parts.count == 3 { return (parts[0] * 3600) + (parts[1] * 60) + parts[2] }
        return 0
    }
}
