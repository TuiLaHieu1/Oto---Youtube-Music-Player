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

    private static let categoryLabels: Set<String> = [
        "album", "ep", "single", "đĩa đơn", "đĩa nhạc", "bài hát", "song", "danh sách phát", "playlist", "video",
        "various artists", "nhiều nghệ sĩ"
    ]
    private static let separatorSymbols: Set<String> = ["•", "·", "-", ","]

    static func isNonArtistLabel(_ name: String) -> Bool {
        categoryLabels.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Trích xuất chính xác tên nghệ sĩ từ đối tượng subtitle hoặc runs, lọc bỏ nhãn phân loại, dấu phân cách và năm.
    public static func extractArtist(from subtitleObj: [String: Any]?, fallback: String = "Nhiều nghệ sĩ") -> String {
        guard let subtitleObj else { return fallback }
        if let runs = subtitleObj["runs"] as? [[String: Any]] {
            for run in runs {
                let nav = run["navigationEndpoint"] as? [String: Any]
                let browse = nav?["browseEndpoint"] as? [String: Any]
                if let browseId = browse?["browseId"] as? String, browseId.hasPrefix("UC") {
                    let trimmed = (run["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            for run in runs {
                guard let text = run["text"] as? String else { continue }
                let navigation = run["navigationEndpoint"] as? [String: Any]
                if navigation?["browseEndpoint"] != nil { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if categoryLabels.contains(trimmed.lowercased()) || separatorSymbols.contains(trimmed) { continue }
                if trimmed.allSatisfy({ "•·-, ".contains($0) }) { continue }
                if trimmed.count == 4, let yr = Int(trimmed), (1900...2100).contains(yr) { continue }
                return trimmed
            }
        }
        if let simple = subtitleObj["simpleText"] as? String {
            let trimmed = simple.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !categoryLabels.contains(trimmed.lowercased())
                && !separatorSymbols.contains(trimmed) {
                return trimmed
            }
        }
        return fallback
    }

    /// Chỉ lấy nghệ sĩ có browse ID UC thật trong chính run tương ứng.
    /// Không tách chuỗi `artist` để đoán ID hoặc tên.
    public static func extractArtists(from subtitleObj: [String: Any]?) -> [ArtistReference] {
        guard let subtitleObj,
              let runs = subtitleObj["runs"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return runs.compactMap { run in
            guard let name = (run["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  !categoryLabels.contains(name.lowercased()),
                  !separatorSymbols.contains(name),
                  let navigation = run["navigationEndpoint"] as? [String: Any],
                  let browse = navigation["browseEndpoint"] as? [String: Any],
                  let browseId = browse["browseId"] as? String,
                  browseId.hasPrefix("UC"),
                  seen.insert(browseId).inserted else { return nil }
            return ArtistReference(browseId: browseId, name: name)
        }
    }

    public static func parsePlaylistOrShelfSongs(from data: Data) throws -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        let itemRenderers = collectRenderers(named: "musicResponsiveListItemRenderer", in: json)
        let results = itemRenderers.compactMap { parseResponsiveListItem($0) }
        guard !results.isEmpty else { throw YTMusicError.parsingError }
        return results
    }

    /// Phân tích danh sách phát cá nhân của người dùng từ phản hồi FEmusic_liked_playlists.
    public static func parseLibraryPlaylists(from data: Data) throws -> [Playlist] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        var results: [Playlist] = []
        for item in extractLibraryItems(from: json) {
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

    static func overlayPlaylistID(in renderer: [String: Any]) -> String? {
        // Một số thẻ cũ chỉ đặt playlist ID trong nút phát trên ảnh bìa.
        let overlay = renderer["thumbnailOverlay"] as? [String: Any]
        let wrapper = overlay?["musicItemThumbnailOverlayRenderer"] as? [String: Any]
        let content = wrapper?["content"] as? [String: Any]
        let button = content?["musicPlayButtonRenderer"] as? [String: Any]
        let playNav = button?["playNavigationEndpoint"] as? [String: Any]
        let playlist = playNav?["watchPlaylistEndpoint"] as? [String: Any]
        guard let id = playlist?["playlistId"] as? String, !id.isEmpty, id != "VL" else { return nil }
        return id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
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

        if videoId == nil {
            let titleNavigation = col0Runs?.first?["navigationEndpoint"] as? [String: Any]
            let rowNavigation = renderer["navigationEndpoint"] as? [String: Any]
            let titleWatch = titleNavigation?["watchEndpoint"] as? [String: Any]
            let rowWatch = rowNavigation?["watchEndpoint"] as? [String: Any]
            videoId = (titleWatch?["videoId"] as? String) ?? (rowWatch?["videoId"] as? String)
        }

        guard let id = videoId, !id.isEmpty, !title.isEmpty else { return nil }

        var artist = "Nhiều nghệ sĩ"
        var artists: [ArtistReference] = []
        var album: String?
        var duration: TimeInterval = 0

        if flexColumns.count > 1 {
            let col1 = flexColumns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
            let col1Runs = (col1?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []

            artist = extractArtist(from: col1?["text"] as? [String: Any], fallback: "Nhiều nghệ sĩ")
            artists = extractArtists(from: col1?["text"] as? [String: Any])
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
            artists: artists,
            album: album,
            duration: duration,
            artworkURL: extractThumbnailURL(from: renderer["thumbnail"] as? [String: Any])
        )
    }
}

// MARK: - Helper Parsers

extension YTMusicParsers {
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
        guard let lastThumb = thumbs?.last, let urlStr = lastThumb["url"] as? String else {
            return nil
        }
        return URL(string: upgradeThumbnailURLString(urlStr))
    }

    static func parseDurationString(_ text: String) -> TimeInterval {
        let parts = text.components(separatedBy: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 { return (parts[0] * 60) + parts[1] }
        if parts.count == 3 { return (parts[0] * 3600) + (parts[1] * 60) + parts[2] }
        return 0
    }
}
