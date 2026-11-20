import Foundation
import CryptoKit
import OtoCore

extension YTMusicParsers {
    /// Cấu trúc dữ liệu đầy đủ của Trang chủ YouTube Music bao gồm Speed Dial và các phân đoạn nội dung.
    public struct HomeFeedContent: Sendable {
        public let speedDial: [SpeedDialItem]
        public let sections: [HomeSection]
        public let continuationToken: String?

        public var quickPicks: [Song] {
            guard let section = sections.first(where: {
                let lower = $0.title.lowercased()
                return lower.contains("quick") || lower.contains("nhanh")
            }) else { return [] }
            return section.items.filter { $0.kind == .song }.compactMap(\.asSong)
        }

        public var listenAgain: [Song] {
            guard let section = sections.first(where: {
                let lower = $0.title.lowercased()
                return lower.contains("phối") || lower.contains("dành cho bạn")
                    || lower.contains("mix") || lower.contains("nghe lại") || lower.contains("listen again")
            }) else { return [] }
            return section.items.filter { $0.kind == .song }.compactMap(\.asSong)
        }

        public init(speedDial: [SpeedDialItem] = [], sections: [HomeSection] = [], continuationToken: String? = nil) {
            self.speedDial = speedDial
            self.sections = sections
            self.continuationToken = continuationToken
        }
    }

    struct ParsedShelf: Sendable {
        let title: String
        let subtitle: String?
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

        let sections = shelves.enumerated().compactMap { index, shelf in
            parseServerHomeShelf(shelf, id: "server_shelf_\(index)")
        }
        guard !sections.isEmpty else { throw YTMusicError.parsingError }
        let speedDial = sections.first(where: { $0.id.hasPrefix("server_speed_dial_") })?.items ?? []
        return HomeFeedContent(speedDial: speedDial, sections: sections,
                               continuationToken: try homeContinuationToken(from: data))
    }

    static func parseServerHomeShelf(_ shelf: [String: Any], id: String) -> HomeSection? {
        let parsed = parseCarouselShelf(shelf)
        guard !parsed.items.isEmpty else { return nil }
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isSpeedDial = (shelf["_isSpeedDialRenderer"] as? Bool == true)
            || ["speed dial", "speeddial", "quay số nhanh"].contains(title)
        var seen = Set<String>()
        let items = isSpeedDial ? parsed.items.filter { seen.insert($0.id).inserted } : parsed.items
        return HomeSection(id: isSpeedDial ? "server_speed_dial_" + id : id, title: parsed.title,
                           subtitle: parsed.subtitle, items: items)
    }

    /// Giữ tương thích ngược với API cũ cho các unit test hiện có.
    public static func parseHomeSections(from data: Data) throws -> (quickPicks: [Song], listenAgain: [Song]) {
        let content = try parseHomeFeed(from: data)
        let picks = content.quickPicks.isEmpty
            ? content.speedDial.filter { $0.kind == .song }.compactMap(\.asSong)
            : content.quickPicks
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
                if var shelf = container["musicSpeedDialShelfRenderer"] as? [String: Any]
                    ?? container["musicSpeedDialShelfModel"] as? [String: Any] {
                    shelf["_isSpeedDialRenderer"] = true
                    rawShelves.append(shelf)
                } else if let shelf = container["musicCarouselShelfRenderer"] as? [String: Any]
                    ?? container["musicShelfRenderer"] as? [String: Any] {
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
        let header = carousel["header"] as? [String: Any]
        let basic = (header?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any])
            ?? (header?["musicShelfHeaderRenderer"] as? [String: Any])
        let shelfTitle = shelfText(basic?["title"] ?? carousel["title"])
        let strapline = shelfText(basic?["strapline"])
        let resolvedTitle = shelfTitle.isEmpty ? "Gợi ý cho bạn" : shelfTitle

        let rawItems = (carousel["contents"] as? [[String: Any]])
            ?? (carousel["items"] as? [[String: Any]])
            ?? ((carousel["data"] as? [String: Any])?["items"] as? [[String: Any]])
        guard let items = rawItems else {
            return ParsedShelf(
                title: resolvedTitle, subtitle: strapline.isEmpty ? nil : strapline, songs: [], items: []
            )
        }

        var shelfSongs: [Song] = []
        var speedDialItems: [SpeedDialItem] = []

        for item in items {
            if let speedItem = parseSpeedDialItem(item) {
                speedDialItems.append(speedItem)
                if speedItem.kind == .song, let song = speedItem.asSong { shelfSongs.append(song) }
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
        return ParsedShelf(
            title: resolvedTitle, subtitle: strapline.isEmpty ? nil : strapline,
            songs: shelfSongs, items: speedDialItems
        )
    }

    private static func shelfText(_ value: Any?) -> String {
        guard let object = value as? [String: Any] else { return "" }
        let runs = object["runs"] as? [[String: Any]]
        return (runs?.compactMap { $0["text"] as? String }.joined() ?? object["simpleText"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func resolveKindAndId(from renderer: [String: Any]) -> (kind: SpeedDialItem.Kind, id: String)? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let browse = nav?["browseEndpoint"] as? [String: Any]
        let browseId = browse?["browseId"] as? String
        let watch = nav?["watchEndpoint"] as? [String: Any]
        let watchPlaylist = nav?["watchPlaylistEndpoint"] as? [String: Any]

        // 1. Kiểm tra browseEndpoint.browseId trước tiên (Ưu tiên Album, Nghệ sĩ, Playlist)
        if let browseId, !browseId.isEmpty {
            if browseId.hasPrefix("MPRE") { return (.album, browseId) }
            if browseId.hasPrefix("UC") { return (.artist, browseId) }
            if browseId.hasPrefix("VL") || browseId.hasPrefix("PL") {
                let playlistId = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId
                return (.playlist, playlistId)
            }
        }

        // watchEndpoint có videoId vẫn là bài hát; playlistId chỉ là context của bài đó.
        if let videoId = watch?["videoId"] as? String, !videoId.isEmpty {
            return (.song, videoId)
        }
        if let rawPlaylist = (watchPlaylist?["playlistId"] as? String) ?? (watch?["playlistId"] as? String),
           !rawPlaylist.isEmpty {
            let playlistId = rawPlaylist.hasPrefix("VL") ? String(rawPlaylist.dropFirst(2)) : rawPlaylist
            return (.playlist, playlistId)
        }

        guard let id = Self.overlayPlaylistID(in: renderer) else { return nil }
        return (.playlist, id)
    }

    static func parseSpeedDialItemRenderer(_ renderer: [String: Any]) -> SpeedDialItem? {
        parseTwoRowSpeedDialItem(renderer)
    }

    static func parseTwoRowSpeedDialItem(_ renderer: [String: Any]) -> SpeedDialItem? {
        guard let (kind, id) = resolveKindAndId(from: renderer) else {
            return nil
        }

        let titleRuns = (renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = titleRuns?.first?["text"] as? String
            ?? (renderer["title"] as? [String: Any])?["simpleText"] as? String
            ?? ""
        guard !title.isEmpty else { return nil }

        let defaultSub: String
        switch kind {
        case .song, .album: defaultSub = "Nhiều nghệ sĩ"
        case .artist: defaultSub = "Nghệ sĩ"
        case .playlist: defaultSub = "Danh sách phát"
        }

        let subtitleObject = renderer["subtitle"] as? [String: Any]
        let subtitle = extractArtist(from: subtitleObject, fallback: defaultSub)
        let thumbContainer = (renderer["thumbnailRenderer"] as? [String: Any])
            ?? (renderer["thumbnail"] as? [String: Any])

        return SpeedDialItem(
            id: id,
            title: title,
            subtitle: subtitle,
            artworkURL: extractThumbnailURL(from: thumbContainer),
            kind: kind,
            artists: kind == .song ? Self.extractArtists(from: subtitleObject) : []
        )
    }

    /// Phân tích dữ liệu chi tiết Album từ browse endpoint (MPREb_...).
    public static func parseAlbumDetail(browseId: String, from data: Data) throws -> Album {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        let headers = ["musicDetailHeaderRenderer", "musicResponsiveHeaderRenderer", "musicHeaderRenderer"]
            .flatMap { collectRenderers(named: $0, in: json) }

        var title = "Album"
        var artist = "Nhiều nghệ sĩ"
        var albumArtists: [ArtistReference] = []
        var year: Int?
        var artworkURL: URL?

        if let header = headers.first {
            if let titleObj = header["title"] as? [String: Any] {
                if let runs = titleObj["runs"] as? [[String: Any]] {
                    title = runs.compactMap { $0["text"] as? String }.joined(separator: " ")
                } else if let simple = titleObj["simpleText"] as? String {
                    title = simple
                }
            }
            let subObj = (header["subtitle"] as? [String: Any]) ?? (header["straplineTextOne"] as? [String: Any])
            albumArtists = extractArtists(from: header["straplineTextOne"] as? [String: Any])
            if albumArtists.isEmpty { albumArtists = extractArtists(from: subObj) }
            artist = albumArtists.isEmpty
                ? extractArtist(from: subObj) : albumArtists.map(\.name).joined(separator: ", ")
            if let runs = subObj?["runs"] as? [[String: Any]] {
                for runItem in runs {
                    guard let text = runItem["text"] as? String else { continue }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count == 4, let yr = Int(trimmed), (1900...2100).contains(yr) {
                        year = yr
                    }
                }
            }
            let thumb = (header["thumbnail"] as? [String: Any]) ?? (header["thumbnailRenderer"] as? [String: Any])
            artworkURL = extractThumbnailURL(from: thumb)
        }

        let itemRenderers = collectRenderers(named: "musicResponsiveListItemRenderer", in: json)
        let songs: [Song] = itemRenderers.compactMap { renderer in
            guard let song = parseResponsiveListItem(renderer) else { return nil }
            let hasUnknownCredit = Self.isNonArtistLabel(song.artist) || song.artist.isEmpty || song.artist == title
            let matchesHeader = albumArtists.count == 1
                && albumArtists.first?.name.compare(song.artist, options: [.caseInsensitive, .diacriticInsensitive])
                    == .orderedSame
            let inheritsAlbumArtist = albumArtists.count == 1 && (hasUnknownCredit || matchesHeader)
            let trackArtists = song.artists.isEmpty && inheritsAlbumArtist ? albumArtists : song.artists
            return Song(
                id: song.id,
                title: song.title,
                artist: hasUnknownCredit ? (trackArtists.first?.name ?? "Nhiều nghệ sĩ") : song.artist,
                artists: trackArtists,
                album: song.album ?? title,
                duration: song.duration,
                artworkURL: song.artworkURL ?? artworkURL,
                isExplicit: song.isExplicit
            )
        }
        return Album(id: browseId, title: title, artist: artist, artworkURL: artworkURL, year: year, songs: songs)
    }
}

// MARK: - YTMusicClient Album Extension

extension YTMusicClient {
    private func makeAlbumBrowseRequest(browseId: String) throws -> URLRequest {
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, val) in [
            ("Origin", "https://music.youtube.com"), ("X-Origin", "https://music.youtube.com"),
            ("Referer", "https://music.youtube.com/"), ("X-Youtube-Client-Name", "67"),
            ("X-Youtube-Client-Version", "1.20261104.00.00")
        ] {
            request.setValue(val, forHTTPHeaderField: field)
        }
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let cookies = CookieStorage.shared.loadCookies()
        let sorted = cookies.sorted { c1, _ in !c1.domain.lowercased().contains("youtube.com") }
        let cookieDict = Dictionary(sorted.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
        let cookieHeader = cookieDict.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
            request.setValue("true", forHTTPHeaderField: "X-Youtube-Bootstrap-Logged-In")
        }

        let sapisidCookie = cookies.first(where: {
            ($0.name == "SAPISID" || $0.name == "__Secure-3PAPISID")
                && ($0.expiresDate.map { $0 > Date() } ?? true)
        })
        if let sapisidCookie {
            let timestamp = Int(Date().timeIntervalSince1970)
            let input = "\(timestamp) \(sapisidCookie.value) https://music.youtube.com"
            let hash = Insecure.SHA1.hash(data: Data(input.utf8))
                .map { String(format: "%02x", $0) }.joined()
            let token = "\(timestamp)_\(hash)"
            let authValue = "SAPISIDHASH \(token) SAPISID1PHASH \(token) SAPISID3PHASH \(token)"
            request.setValue(authValue, forHTTPHeaderField: "Authorization")
        }

        let bodyPayload: [String: Any] = [
            "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20261104.00.00",
                                   "hl": "vi", "gl": "VN"]],
            "browseId": browseId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyPayload)
        return request
    }

    /// Nạp chi tiết Album (bao gồm danh sách bài hát) từ YouTube Music API theo browseId.
    public func fetchAlbumDetail(browseId: String) async throws -> Album {
        let trimmed = browseId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw YTMusicError.invalidURL }
        let request = try makeAlbumBrowseRequest(browseId: trimmed)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw YTMusicError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw YTMusicError.authenticationExpired
            case 403: throw YTMusicError.permissionDenied
            case 429: throw YTMusicError.rateLimited(retryAfter: nil)
            case 500...599: throw YTMusicError.serverError(statusCode: httpResponse.statusCode)
            default: throw YTMusicError.invalidResponse
            }
        }
        return try YTMusicParsers.parseAlbumDetail(browseId: trimmed, from: data)
    }
}
