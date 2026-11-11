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

    /// Phân tích danh sách phát cá nhân của người dùng từ phản hồi FEmusic_liked_playlists.
    public static func parseLibraryPlaylists(from data: Data) throws -> [Playlist] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        var results: [Playlist] = []
        let rawItems = extractLibraryItems(from: json)

        for item in rawItems {
            if let renderer = item["musicTwoRowItemRenderer"] as? [String: Any],
               let playlist = parsePlaylistFromTwoRow(renderer) {
                results.append(playlist)
            } else if let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
                      let playlist = parsePlaylistFromResponsive(renderer) {
                results.append(playlist)
            }
        }

        return results
    }

    private static func extractLibraryItems(from json: [String: Any]) -> [[String: Any]] {
        if let contents = json["contents"] as? [String: Any],
           let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
           let sectionContents = sectionList["contents"] as? [[String: Any]] {
            var items: [[String: Any]] = []
            for section in sectionContents {
                if let grid = section["gridRenderer"] as? [String: Any],
                   let gridItems = grid["items"] as? [[String: Any]] {
                    items.append(contentsOf: gridItems)
                }
                if let shelf = section["musicShelfRenderer"] as? [String: Any],
                   let shelfItems = shelf["contents"] as? [[String: Any]] {
                    items.append(contentsOf: shelfItems)
                }
            }
            if !items.isEmpty { return items }
        }
        return collectRenderers(named: "musicTwoRowItemRenderer", in: json).map { ["musicTwoRowItemRenderer": $0] }
    }

    static func parsePlaylistFromTwoRow(_ renderer: [String: Any]) -> Playlist? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let browse = nav?["browseEndpoint"] as? [String: Any]
        let watchPlaylist = nav?["watchPlaylistEndpoint"] as? [String: Any]

        let overlay = renderer["thumbnailOverlay"] as? [String: Any]
        let overlayItem = overlay?["musicItemThumbnailOverlayRenderer"] as? [String: Any]
        let playBtn = (overlayItem?["content"] as? [String: Any])?["musicPlayButtonRenderer"] as? [String: Any]
        let playNav = playBtn?["playNavigationEndpoint"] as? [String: Any]
        let playWatchPlaylist = playNav?["watchPlaylistEndpoint"] as? [String: Any]

        let rawId = (browse?["browseId"] as? String)
            ?? (watchPlaylist?["playlistId"] as? String)
            ?? (playWatchPlaylist?["playlistId"] as? String)
        guard let rawId, !rawId.isEmpty else { return nil }

        let playlistId = rawId.starts(with: "VL") ? String(rawId.dropFirst(2)) : rawId

        let titleRuns = (renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = titleRuns?.first?["text"] as? String
            ?? (renderer["title"] as? [String: Any])?["simpleText"] as? String
            ?? ""
        guard !title.isEmpty else { return nil }

        let subRuns = (renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]
        let subtitle = subRuns?.compactMap { $0["text"] as? String }.joined(separator: " ")
            ?? "Danh sách phát"

        let thumbContainer = (renderer["thumbnailRenderer"] as? [String: Any])
            ?? (renderer["thumbnail"] as? [String: Any])

        return Playlist(
            id: playlistId,
            title: title,
            subtitle: subtitle,
            artworkURL: extractThumbnailURL(from: thumbContainer)
        )
    }

    static func parsePlaylistFromResponsive(_ renderer: [String: Any]) -> Playlist? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let browse = nav?["browseEndpoint"] as? [String: Any]
        let rawId = browse?["browseId"] as? String
        guard let rawId, !rawId.isEmpty else { return nil }
        let playlistId = rawId.starts(with: "VL") ? String(rawId.dropFirst(2)) : rawId

        let flexColumns = renderer["flexColumns"] as? [[String: Any]]
        let firstCol = flexColumns?.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        let titleRuns = (firstCol?["text"] as? [String: Any])?["runs"] as? [[String: Any]]
        let titleText = titleRuns?.first?["text"] as? String ?? ""
        guard !titleText.isEmpty else { return nil }

        let thumbContainer = renderer["thumbnail"] as? [String: Any]

        return Playlist(
            id: playlistId,
            title: titleText,
            subtitle: "Danh sách phát",
            artworkURL: extractThumbnailURL(from: thumbContainer)
        )
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
