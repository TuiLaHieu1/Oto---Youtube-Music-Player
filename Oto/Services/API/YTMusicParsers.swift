import Foundation
import OtoCore

/// Bộ phân tích dữ liệu JSON từ Innertube API của YouTube Music với kiểm tra schema chẩn đoán lỗi.
public enum YTMusicParsers {
    // MARK: - Home Feed

    public static func parseHomeSections(from data: Data) throws -> (quickPicks: [Song], listenAgain: [Song]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        guard let contents = json["contents"] as? [String: Any],
              let browseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = browseResults["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionList["contents"] as? [[String: Any]] else {
            throw YTMusicError.parsingError
        }

        var quickPicks: [Song] = []
        var listenAgain: [Song] = []
        var generalShelves: [Song] = []

        for section in sectionContents {
            guard let carousel = section["musicCarouselShelfRenderer"] as? [String: Any] else { continue }
            let (shelfTitle, shelfSongs) = parseCarouselShelf(carousel)
            guard !shelfSongs.isEmpty else { continue }

            if shelfTitle.contains("listen again") || shelfTitle.contains("nghe lại") {
                listenAgain.append(contentsOf: shelfSongs)
            } else if shelfTitle.contains("quick picks") || shelfTitle.contains("lựa chọn nhanh") {
                quickPicks.append(contentsOf: shelfSongs)
            } else {
                generalShelves.append(contentsOf: shelfSongs)
            }
        }

        // Nếu người dùng chưa đăng nhập hoặc tiêu đề shelf khác biệt, tận dụng các shelf thật để hiển thị
        if quickPicks.isEmpty && !generalShelves.isEmpty {
            let splitIndex = min(generalShelves.count / 2, 8)
            quickPicks = Array(generalShelves.prefix(splitIndex))
            generalShelves.removeFirst(splitIndex)
        }
        if listenAgain.isEmpty && !generalShelves.isEmpty {
            listenAgain = generalShelves
        }

        if quickPicks.isEmpty && listenAgain.isEmpty && !sectionContents.isEmpty {
            throw YTMusicError.parsingError
        }

        return (quickPicks, listenAgain)
    }

    private static func parseCarouselShelf(_ carousel: [String: Any]) -> (title: String, songs: [Song]) {
        var shelfTitle = ""
        if let header = carousel["header"] as? [String: Any],
           let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
           let titleObj = basicHeader["title"] as? [String: Any],
           let runs = titleObj["runs"] as? [[String: Any]] {
            shelfTitle = runs.compactMap { $0["text"] as? String }.joined().lowercased()
        }

        guard let items = carousel["contents"] as? [[String: Any]] else {
            return (shelfTitle, [])
        }

        var shelfSongs: [Song] = []
        for item in items {
            if let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
               let song = parseResponsiveListItem(renderer) {
                shelfSongs.append(song)
            } else if let renderer = item["musicTwoRowItemRenderer"] as? [String: Any],
                      let song = parseTwoRowItem(renderer) {
                shelfSongs.append(song)
            }
        }
        return (shelfTitle, shelfSongs)
    }

    // MARK: - Playlists & Liked Songs

    public static func parsePlaylistOrShelfSongs(from data: Data) throws -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        guard let contents = json["contents"] as? [String: Any],
              let browseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = browseResults["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionList["contents"] as? [[String: Any]] else {
            throw YTMusicError.parsingError
        }

        var results: [Song] = []
        for section in sectionContents {
            let shelfItems = (section["musicPlaylistShelfRenderer"] as? [String: Any])?["contents"]
                as? [[String: Any]]
                ?? (section["musicShelfRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]

            if let items = shelfItems {
                for item in items {
                    if let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
                       let song = parseResponsiveListItem(renderer) {
                        results.append(song)
                    }
                }
            }
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

    public static func parseTwoRowItem(_ renderer: [String: Any]) -> Song? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let watch = nav?["watchEndpoint"] as? [String: Any]
        guard let videoId = watch?["videoId"] as? String, !videoId.isEmpty else {
            return nil
        }

        let titleRuns = (renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = titleRuns?.first?["text"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        let subRuns = (renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]
        let artist = subRuns?.first?["text"] as? String ?? "Nhiều nghệ sĩ"

        return Song(
            id: videoId,
            title: title,
            artist: artist,
            album: nil,
            duration: 0,
            artworkURL: extractThumbnailURL(from: renderer["thumbnailRenderer"] as? [String: Any])
        )
    }

    private static func extractSectionLists(from contents: [String: Any]) -> [[String: Any]] {
        if let direct = contents["sectionListRenderer"] as? [String: Any] {
            return [direct]
        }
        if let tabbed = contents["tabbedSearchResultsRenderer"] as? [String: Any],
           let tabs = tabbed["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionList = tabContent["sectionListRenderer"] as? [String: Any] {
            return [sectionList]
        }
        return []
    }

    private static func extractThumbnailURL(from container: [String: Any]?) -> URL? {
        guard let container else { return nil }
        let musicThumb = container["musicThumbnailRenderer"] as? [String: Any]
        let thumbObj = (musicThumb?["thumbnail"] as? [String: Any]) ?? (container["thumbnail"] as? [String: Any])
        let thumbs = thumbObj?["thumbnails"] as? [[String: Any]]
        guard let lastThumb = thumbs?.last,
              let urlStr = lastThumb["url"] as? String else {
            return nil
        }
        return URL(string: urlStr)
    }

    private static func parseDurationString(_ text: String) -> TimeInterval {
        let parts = text.components(separatedBy: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 {
            return (parts[0] * 60) + parts[1]
        } else if parts.count == 3 {
            return (parts[0] * 3600) + (parts[1] * 60) + parts[2]
        }
        return 0
    }
}
