import Foundation
import OtoCore

// MARK: - Speed Dial & Home Feed Extensions

extension YTMusicParsers {
    /// Cấu trúc dữ liệu đầy đủ của Trang chủ YouTube Music bao gồm Speed Dial và các phân đoạn nội dung.
    public struct HomeFeedContent: Sendable {
        public let speedDial: [SpeedDialItem]
        public let sections: [HomeSection]

        public var quickPicks: [Song] {
            if let qpSection = sections.first(where: {
                let lower = $0.title.lowercased()
                return lower.contains("quick") || lower.contains("nhanh")
            }) {
                return qpSection.items.map(\.asSong)
            }
            return []
        }

        public var listenAgain: [Song] {
            if let laSection = sections.first(where: {
                let lower = $0.title.lowercased()
                return lower.contains("phối") || lower.contains("dành cho bạn")
                    || lower.contains("mix") || lower.contains("nghe lại") || lower.contains("listen again")
            }) {
                return laSection.items.map(\.asSong)
            }
            return []
        }

        public init(
            speedDial: [SpeedDialItem] = [],
            sections: [HomeSection] = []
        ) {
            self.speedDial = speedDial
            self.sections = sections
        }
    }

    struct ParsedShelf: Sendable {
        let title: String
        let songs: [Song]
        let items: [SpeedDialItem]
    }

    /// Nạp và phân loại chuẩn xác các khối Home Feed từ YouTube Music theo thứ tự danh sách thực tế.
    public static func parseHomeFeed(from data: Data) throws -> HomeFeedContent {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        let shelves = extractOrderedShelves(from: json)
        guard !shelves.isEmpty else {
            throw YTMusicError.parsingError
        }

        var speedDialItems: [SpeedDialItem] = []
        var sections: [HomeSection] = []
        var sectionIndex = 0

        for shelf in shelves {
            let parsed = parseCarouselShelf(shelf)
            guard !parsed.items.isEmpty else { continue }
            let lowerTitle = parsed.title.lowercased()

            let isSpeedDial = [
                "speed dial", "speeddial", "quay số nhanh", "listen again", "nghe lại",
                "thường nghe", "nghe nhiều", "gần đây", "recently"
            ].contains { lowerTitle.contains($0) } || shelf["musicSpeedDialShelfRenderer"] != nil

            if isSpeedDial && speedDialItems.isEmpty {
                speedDialItems = parsed.items
            } else {
                sectionIndex += 1
                let sectionId = "\(sectionIndex)_\(parsed.title)"
                sections.append(HomeSection(id: sectionId, title: parsed.title, items: parsed.items))
            }
        }

        // Fallback tài khoản khách nếu không có shelf Speed dial riêng:
        // Nếu shelf đầu tiên không phải Quick picks, dùng làm Speed dial
        if speedDialItems.isEmpty && !sections.isEmpty {
            let firstTitle = sections.first?.title.lowercased() ?? ""
            let isFirstQuickPick = firstTitle.contains("quick") || firstTitle.contains("nhanh")
            if !isFirstQuickPick {
                let first = sections.removeFirst()
                speedDialItems = first.items
            }
        }

        var seenSpeedDialIds = Set<String>()
        let uniqueSpeedDial = speedDialItems.filter { item in
            guard !seenSpeedDialIds.contains(item.id) else { return false }
            seenSpeedDialIds.insert(item.id)
            return true
        }

        if uniqueSpeedDial.isEmpty && sections.isEmpty {
            throw YTMusicError.parsingError
        }

        return HomeFeedContent(speedDial: uniqueSpeedDial, sections: sections)
    }

    /// Giữ tương thích ngược với API cũ cho các unit test hiện có.
    public static func parseHomeSections(from data: Data) throws -> (quickPicks: [Song], listenAgain: [Song]) {
        let content = try parseHomeFeed(from: data)
        let picks = content.quickPicks.isEmpty ? content.speedDial.map(\.asSong) : content.quickPicks
        return (picks, content.listenAgain)
    }

    private static func extractOrderedShelves(from json: [String: Any]) -> [[String: Any]] {
        var rawShelves: [[String: Any]] = []

        if let contents = json["contents"] as? [String: Any],
           let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
           let sectionContents = sectionList["contents"] as? [[String: Any]] {
            for container in sectionContents {
                if let shelf = container["musicCarouselShelfRenderer"] as? [String: Any]
                    ?? container["musicShelfRenderer"] as? [String: Any]
                    ?? container["musicSpeedDialShelfRenderer"] as? [String: Any]
                    ?? container["musicSpeedDialShelfModel"] as? [String: Any] {
                    rawShelves.append(shelf)
                }
            }
        }

        if rawShelves.isEmpty {
            rawShelves = collectRenderers(named: "musicCarouselShelfRenderer", in: json)
        }
        return rawShelves
    }

    static func parseCarouselShelf(_ carousel: [String: Any]) -> ParsedShelf {
        var headerTexts: [String] = []
        if let header = carousel["header"] as? [String: Any] {
            let basicHeader = (header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any])
                ?? (header["musicShelfHeaderRenderer"] as? [String: Any])
            if let basic = basicHeader {
                if let titleObj = basic["title"] as? [String: Any],
                   let runs = titleObj["runs"] as? [[String: Any]] {
                    headerTexts.append(contentsOf: runs.compactMap { $0["text"] as? String })
                }
                if let straplineObj = basic["strapline"] as? [String: Any],
                   let runs = straplineObj["runs"] as? [[String: Any]] {
                    headerTexts.append(contentsOf: runs.compactMap { $0["text"] as? String })
                }
            }
        }
        let shelfTitle = headerTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = shelfTitle.isEmpty ? "Gợi ý cho bạn" : shelfTitle

        let rawItems = (carousel["contents"] as? [[String: Any]])
            ?? (carousel["items"] as? [[String: Any]])
            ?? ((carousel["data"] as? [String: Any])?["items"] as? [[String: Any]])
        guard let items = rawItems else {
            return ParsedShelf(title: resolvedTitle, songs: [], items: [])
        }

        var shelfSongs: [Song] = []
        var speedDialItems: [SpeedDialItem] = []

        for item in items {
            if let speedItem = parseSpeedDialItem(item) {
                speedDialItems.append(speedItem)
                if speedItem.kind == .song {
                    shelfSongs.append(speedItem.asSong)
                }
            } else if let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
                      let song = parseResponsiveListItem(renderer) {
                shelfSongs.append(song)
                speedDialItems.append(SpeedDialItem(song: song))
            } else if let renderer = (item["musicTwoRowItemRenderer"] as? [String: Any])
                        ?? (item["musicSpeedDialItemRenderer"] as? [String: Any]),
                      let song = parseTwoRowItem(renderer) {
                shelfSongs.append(song)
                speedDialItems.append(SpeedDialItem(song: song))
            }
        }
        return ParsedShelf(title: resolvedTitle, songs: shelfSongs, items: speedDialItems)
    }

    // MARK: - Speed Dial Item Parsers

    /// Phân tích phần tử tổng quát cho Speed Dial (hỗ trợ cả Song, Playlist, Album, Artist).
    public static func parseSpeedDialItem(_ item: [String: Any]) -> SpeedDialItem? {
        if let renderer = item["musicSpeedDialItemRenderer"] as? [String: Any] {
            return parseSpeedDialItemRenderer(renderer)
        }
        if let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
           let song = parseResponsiveListItem(renderer) {
            return SpeedDialItem(song: song)
        }
        if let renderer = item["musicTwoRowItemRenderer"] as? [String: Any] {
            return parseTwoRowSpeedDialItem(renderer)
        }
        return nil
    }

    static func parseSpeedDialItemRenderer(_ renderer: [String: Any]) -> SpeedDialItem? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let watch = nav?["watchEndpoint"] as? [String: Any]
        let watchPlaylist = nav?["watchPlaylistEndpoint"] as? [String: Any]
        let browse = nav?["browseEndpoint"] as? [String: Any]

        let videoId = watch?["videoId"] as? String
        let playlistId = watchPlaylist?["playlistId"] as? String
            ?? watch?["playlistId"] as? String
            ?? (browse?["browseId"] as? String)

        guard let id = videoId ?? playlistId, !id.isEmpty else {
            return nil
        }

        let isArtist = (browse?["browseId"] as? String)?.starts(with: "UC") == true
        let kind: SpeedDialItem.Kind = isArtist ? .artist : (videoId != nil ? .song : .playlist)

        let titleRuns = (renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = titleRuns?.first?["text"] as? String
            ?? (renderer["title"] as? [String: Any])?["simpleText"] as? String
            ?? ""
        guard !title.isEmpty else { return nil }

        let subRuns = (renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]
        let subtitle = subRuns?.first?["text"] as? String
            ?? (renderer["subtitle"] as? [String: Any])?["simpleText"] as? String
            ?? (kind == .song ? "Nghệ sĩ" : "Danh sách phát")

        let thumbContainer = (renderer["thumbnailRenderer"] as? [String: Any])
            ?? (renderer["thumbnail"] as? [String: Any])

        return SpeedDialItem(
            id: id,
            title: title,
            subtitle: subtitle,
            artworkURL: extractThumbnailURL(from: thumbContainer),
            kind: kind,
            isPinned: false
        )
    }

    static func parseTwoRowSpeedDialItem(_ renderer: [String: Any]) -> SpeedDialItem? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let watch = nav?["watchEndpoint"] as? [String: Any]
        let watchPlaylist = nav?["watchPlaylistEndpoint"] as? [String: Any]
        let browse = nav?["browseEndpoint"] as? [String: Any]

        let overlay = renderer["thumbnailOverlay"] as? [String: Any]
        let overlayItem = overlay?["musicItemThumbnailOverlayRenderer"] as? [String: Any]
        let playBtn = (overlayItem?["content"] as? [String: Any])?["musicPlayButtonRenderer"] as? [String: Any]
        let playNav = playBtn?["playNavigationEndpoint"] as? [String: Any]
        let playWatch = playNav?["watchEndpoint"] as? [String: Any]
        let playWatchPlaylist = playNav?["watchPlaylistEndpoint"] as? [String: Any]

        let videoId = watch?["videoId"] as? String
            ?? playWatch?["videoId"] as? String

        let rawPlaylistId = watchPlaylist?["playlistId"] as? String
            ?? watch?["playlistId"] as? String
            ?? playWatchPlaylist?["playlistId"] as? String
            ?? (browse?["browseId"] as? String)

        var playlistId: String?
        if let raw = rawPlaylistId {
            playlistId = raw.starts(with: "VL") ? String(raw.dropFirst(2)) : raw
        }

        guard let id = videoId ?? playlistId, !id.isEmpty else {
            return nil
        }

        let isArtist = (browse?["browseId"] as? String)?.starts(with: "UC") == true
        let kind: SpeedDialItem.Kind = isArtist ? .artist : (videoId != nil ? .song : .playlist)

        let titleRuns = (renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = titleRuns?.first?["text"] as? String
            ?? (renderer["title"] as? [String: Any])?["simpleText"] as? String
            ?? ""
        guard !title.isEmpty else { return nil }

        let subRuns = (renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]
        let subtitle = subRuns?.first?["text"] as? String
            ?? (renderer["subtitle"] as? [String: Any])?["simpleText"] as? String
            ?? (kind == .song ? "Nhiều nghệ sĩ" : (isArtist ? "Nghệ sĩ" : "Danh sách phát"))

        let thumbContainer = (renderer["thumbnailRenderer"] as? [String: Any])
            ?? (renderer["thumbnail"] as? [String: Any])

        return SpeedDialItem(
            id: id,
            title: title,
            subtitle: subtitle,
            artworkURL: extractThumbnailURL(from: thumbContainer),
            kind: kind,
            isPinned: false
        )
    }
}
