import Foundation
import OtoCore

// MARK: - Speed Dial & Home Feed Extensions

extension YTMusicParsers {
    /// Cấu trúc dữ liệu đầy đủ của Trang chủ YouTube Music bao gồm Speed Dial, Quick Picks và Nghe lại.
    public struct HomeFeedContent: Sendable {
        public let speedDial: [SpeedDialItem]
        public let quickPicks: [Song]
        public let listenAgain: [Song]

        public init(
            speedDial: [SpeedDialItem] = [],
            quickPicks: [Song] = [],
            listenAgain: [Song] = []
        ) {
            self.speedDial = speedDial
            self.quickPicks = quickPicks
            self.listenAgain = listenAgain
        }
    }

    struct ParsedShelf: Sendable {
        let title: String
        let songs: [Song]
        let items: [SpeedDialItem]
    }

    /// Nạp và phân loại chuẩn xác các khối Home Feed từ YouTube Music.
    public static func parseHomeFeed(from data: Data) throws -> HomeFeedContent {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        var shelves = collectRenderers(named: "musicCarouselShelfRenderer", in: json)
        shelves.append(contentsOf: collectRenderers(named: "musicShelfRenderer", in: json))
        shelves.append(contentsOf: collectRenderers(named: "musicSpeedDialShelfRenderer", in: json))
        shelves.append(contentsOf: collectRenderers(named: "musicSpeedDialShelfModel", in: json))
        guard !shelves.isEmpty else {
            throw YTMusicError.parsingError
        }

        var buckets = classifyShelves(shelves)
        applyHomeFeedFallbacks(buckets: &buckets)

        var seenSpeedDialIds = Set<String>()
        let uniqueSpeedDial = buckets.speedDial.filter { item in
            guard !seenSpeedDialIds.contains(item.id) else { return false }
            seenSpeedDialIds.insert(item.id)
            return true
        }

        if uniqueSpeedDial.isEmpty && buckets.quickPicks.isEmpty && buckets.listenAgain.isEmpty {
            throw YTMusicError.parsingError
        }

        return HomeFeedContent(
            speedDial: uniqueSpeedDial,
            quickPicks: buckets.quickPicks,
            listenAgain: buckets.listenAgain
        )
    }

    /// Giữ tương thích ngược với API cũ cho các unit test hiện có.
    public static func parseHomeSections(from data: Data) throws -> (quickPicks: [Song], listenAgain: [Song]) {
        let content = try parseHomeFeed(from: data)
        let picks = content.quickPicks.isEmpty ? content.speedDial.map(\.asSong) : content.quickPicks
        return (picks, content.listenAgain)
    }

    private struct ShelfBuckets {
        var speedDial: [SpeedDialItem] = []
        var quickPicks: [Song] = []
        var listenAgain: [Song] = []
        var otherShelves: [ParsedShelf] = []
    }

    private static func classifyShelves(_ shelves: [[String: Any]]) -> ShelfBuckets {
        var buckets = ShelfBuckets()
        for shelf in shelves {
            let parsed = parseCarouselShelf(shelf)
            guard !parsed.items.isEmpty else { continue }
            let lowerTitle = parsed.title.lowercased()

            let isSpeedDial = [
                "speed dial", "speeddial", "quay số nhanh", "listen again", "nghe lại",
                "thường nghe", "nghe nhiều", "gần đây", "recently"
            ].contains { lowerTitle.contains($0) } || shelf["musicSpeedDialShelfRenderer"] != nil

            let isQuickPicks = [
                "quick picks", "lựa chọn nhanh", "chọn nhanh", "khởi động radio", "start radio"
            ].contains { lowerTitle.contains($0) }

            let isMixedForYou = [
                "dành cho bạn", "for you", "gợi ý", "mixed for you", "bản phối", "danh sách kết hợp"
            ].contains { lowerTitle.contains($0) }

            if isSpeedDial {
                buckets.speedDial.append(contentsOf: parsed.items)
            } else if isQuickPicks {
                buckets.quickPicks.append(contentsOf: parsed.songs)
            } else if isMixedForYou {
                buckets.listenAgain.append(contentsOf: parsed.songs)
            } else {
                buckets.otherShelves.append(parsed)
            }
        }
        return buckets
    }

    private static func applyHomeFeedFallbacks(buckets: inout ShelfBuckets) {
        if buckets.speedDial.isEmpty && !buckets.otherShelves.isEmpty {
            let first = buckets.otherShelves.removeFirst()
            buckets.speedDial = first.items
        }
        if buckets.quickPicks.isEmpty && !buckets.otherShelves.isEmpty {
            let next = buckets.otherShelves.removeFirst()
            buckets.quickPicks = next.songs
        }
        if buckets.listenAgain.isEmpty && !buckets.otherShelves.isEmpty {
            let next = buckets.otherShelves.removeFirst()
            buckets.listenAgain = next.songs
        }
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
        let shelfTitle = headerTexts.joined(separator: " ").lowercased()

        let rawItems = (carousel["contents"] as? [[String: Any]])
            ?? (carousel["items"] as? [[String: Any]])
            ?? ((carousel["data"] as? [String: Any])?["items"] as? [[String: Any]])
        guard let items = rawItems else {
            return ParsedShelf(title: shelfTitle, songs: [], items: [])
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
        return ParsedShelf(title: shelfTitle, songs: shelfSongs, items: speedDialItems)
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
