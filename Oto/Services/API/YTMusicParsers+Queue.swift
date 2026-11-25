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
    /// `seedID` là bài đang phát: nếu một mục bọc có bản còn lại chính là bài này thì lấy bản đó,
    /// để bộ lọc theo ID bỏ được mục trùng với bài đang phát.
    public static func parseUpNextQueue(from data: Data, seedID: String? = nil) throws -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }

        let renderers = upNextRenderers(in: json, seedID: seedID)
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

    /// Lấy đúng một renderer cho mỗi mục trong hàng đợi, theo thứ tự.
    /// Với tài khoản có nút chuyển Bài hát/Video, mỗi mục được bọc trong `playlistPanelVideoWrapperRenderer`:
    /// `primaryRenderer` là bản đang chọn, `counterpart` là bản còn lại (audio hoặc MV). Chỉ lấy bản chính,
    /// nếu không một bài có MV sẽ hiện hai lần.
    private static func upNextRenderers(in json: [String: Any], seedID: String?) -> [[String: Any]] {
        let panels = collectRenderers(named: "playlistPanelRenderer", in: json)
        guard !panels.isEmpty else {
            return collectRenderers(named: "playlistPanelVideoRenderer", in: json)
        }
        var trace = UpNextTrace()
        let renderers = panels.flatMap { panel -> [[String: Any]] in
            let items = panel["contents"] as? [[String: Any]] ?? []
            return items.compactMap { item in
                if let renderer = item["playlistPanelVideoRenderer"] as? [String: Any] {
                    trace.plain += 1
                    if seedID != nil, renderer["videoId"] as? String == seedID { trace.seedPlain += 1 }
                    return renderer
                }
                let wrapper = item["playlistPanelVideoWrapperRenderer"] as? [String: Any]
                let primary = (wrapper?["primaryRenderer"] as? [String: Any])?["playlistPanelVideoRenderer"]
                    as? [String: Any]
                let counterparts = (wrapper?["counterpart"] as? [[String: Any]] ?? []).compactMap {
                    ($0["counterpartRenderer"] as? [String: Any])?["playlistPanelVideoRenderer"] as? [String: Any]
                }
                guard let primary else { return nil }
                trace.wrapped += 1
                if seedID != nil, primary["videoId"] as? String == seedID { trace.seedPrimary += 1 }
                if let seedID, let seed = counterparts.first(where: { $0["videoId"] as? String == seedID }) {
                    trace.seedCounterpart += 1
                    return seed
                }
                return primary
            }
        }
        #if DEBUG && OTO_STREAM_PROBE
        StreamProbeLog.write("StreamProbe upnext plain=\(trace.plain) wrapped=\(trace.wrapped) "
            + "seedPlain=\(trace.seedPlain) seedPrimary=\(trace.seedPrimary) seedCounterpart=\(trace.seedCounterpart)")
        #endif
        return renderers
    }

    /// Số đếm cấu trúc hàng đợi cho trace khảo sát; không chứa ID hay tiêu đề.
    private struct UpNextTrace {
        var plain = 0
        var wrapped = 0
        var seedPlain = 0
        var seedPrimary = 0
        var seedCounterpart = 0
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

enum MusicSearchResult: Identifiable, Sendable {
    case song(Song)
    case video(Song)
    case album(Playlist)
    case artist(ArtistReference, artworkURL: URL?, subtitle: String)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .song(let song), .video(let song): "song:" + song.id
        case .album(let album): "album:" + album.id
        case .artist(let artist, _, _): "artist:" + artist.id
        case .playlist(let playlist): "playlist:" + playlist.id
        }
    }
}

struct MusicSearchPage: Sendable {
    var topResult: MusicSearchResult?
    var results: [MusicSearchResult] = []
    var nextToken: String?
    var isEmpty: Bool { topResult == nil && results.isEmpty }
}

extension YTMusicParsers {
    static func parseMusicSearch(
        from data: Data, scope: SearchScope, isContinuation: Bool = false
    ) throws -> MusicSearchPage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        let sections: [[String: Any]]
        let shelves: [[String: Any]]
        if isContinuation {
            let continuation = root["continuationContents"] as? [String: Any]
            guard let shelf = continuation?["musicShelfContinuation"] as? [String: Any],
                  shelf["contents"] is [[String: Any]] else { throw YTMusicError.parsingError }
            sections = []
            shelves = [shelf]
        } else {
            guard let contents = root["contents"] as? [String: Any] else { throw YTMusicError.parsingError }
            sections = Self.extractSectionLists(from: contents)
            guard !sections.isEmpty else { throw YTMusicError.parsingError }
            shelves = Self.collectRenderers(named: "musicShelfRenderer", in: sections)
        }

        let rows = Self.collectRenderers(
            named: "musicResponsiveListItemRenderer", in: scope == .all ? sections : shelves
        )
        var seen = Set<String>()
        let results = rows.compactMap { Self.musicSearchResult(from: $0, scope: scope) }
            .filter { seen.insert($0.id).inserted }
        let card = scope == .all ? Self.collectRenderers(named: "musicCardShelfRenderer", in: sections).first : nil
        let top = card.flatMap { Self.topMusicSearchResult(from: $0, results: results) }
        let nextToken = scope == .all ? nil : Self.collectRenderers(named: "nextContinuationData", in: shelves)
            .compactMap { $0["continuation"] as? String }.first { !$0.isEmpty }
        return MusicSearchPage(topResult: top, results: results.filter { $0.id != top?.id }, nextToken: nextToken)
    }

    private static func topMusicSearchResult(
        from card: [String: Any], results: [MusicSearchResult]
    ) -> MusicSearchResult? {
        let title = card["title"] as? [String: Any]
        let titleRuns = title?["runs"] as? [[String: Any]]
        guard let name = titleRuns?.first?["text"] as? String, !name.isEmpty else { return nil }
        let navigation = (card["onTap"] as? [String: Any])
            ?? (titleRuns?.first?["navigationEndpoint"] as? [String: Any])
        let subtitle = card["subtitle"] as? [String: Any]
        let artwork = Self.extractThumbnailURL(from: card["thumbnail"] as? [String: Any])
        if let watch = navigation?["watchEndpoint"] as? [String: Any],
           let id = watch["videoId"] as? String, !id.isEmpty {
            if let result = results.first(where: { $0.id == "song:" + id }) { return result }
            let artists = Self.extractArtists(from: subtitle)
            let artist = artists.map(\.name).joined(separator: ", ")
            let song = Song(id: id, title: name, artist: artist, artists: artists, artworkURL: artwork)
            return Self.containsVideo(card, id: id) ? .video(song) : .song(song)
        }
        let browse = navigation?["browseEndpoint"] as? [String: Any]
        guard let id = browse?["browseId"] as? String else { return nil }
        let subtitleRuns = subtitle?["runs"] as? [[String: Any]]
        let description = subtitleRuns?.compactMap { $0["text"] as? String }.joined() ?? ""
        return Self.musicBrowseResult(id: id, title: name, subtitle: description, artwork: artwork, scope: .all)
    }

    private static func musicSearchResult(from row: [String: Any], scope: SearchScope) -> MusicSearchResult? {
        let navigation = row["navigationEndpoint"] as? [String: Any]
        let browse = navigation?["browseEndpoint"] as? [String: Any]
        guard let id = browse?["browseId"] as? String else {
            guard scope == .all || scope == .songs || scope == .videos,
                  let song = Self.parseResponsiveListItem(row) else { return nil }
            let isVideo = scope == .videos || (scope == .all && Self.containsVideo(row, id: song.id))
            return isVideo ? .video(song) : .song(song)
        }
        let columns = Self.collectRenderers(
            named: "musicResponsiveListItemFlexColumnRenderer", in: row["flexColumns"] ?? []
        )
        let texts = columns.map { column in
            let text = column["text"] as? [String: Any]
            let runs = text?["runs"] as? [[String: Any]]
            return runs?.compactMap { $0["text"] as? String }.joined() ?? ""
        }
        guard let title = texts.first, !title.isEmpty else { return nil }
        return Self.musicBrowseResult(
            id: id, title: title, subtitle: texts.dropFirst().first ?? "",
            artwork: Self.extractThumbnailURL(from: row["thumbnail"] as? [String: Any]), scope: scope
        )
    }

    private static func musicBrowseResult(
        id: String, title: String, subtitle: String, artwork: URL?, scope: SearchScope
    ) -> MusicSearchResult? {
        if id.hasPrefix("UC"), id.count > 2, scope == .all || scope == .artists {
            return .artist(ArtistReference(browseId: id, name: title), artworkURL: artwork, subtitle: subtitle)
        }
        let album = id.hasPrefix("MPRE")
        let playlist = id.hasPrefix("VL") && id.count > 2
        guard (album && (scope == .all || scope == .albums))
                || (playlist && (scope == .all || scope == .playlists)) else { return nil }
        let item = Playlist(
            id: album ? id : String(id.dropFirst(2)),
            title: title,
            subtitle: subtitle,
            artworkURL: artwork
        )
        return album ? .album(item) : .playlist(item)
    }
}

extension YTMusicParsers {
    static func supportsVideo(in data: Data, id: String) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return false }
        return Self.containsVideo(root, id: id)
    }

    private static func containsVideo(_ node: Any, id: String) -> Bool {
        if let item = node as? [String: Any] {
            if let endpoint = item["watchEndpoint"] as? [String: Any],
               endpoint["videoId"] as? String == id,
               let configs = endpoint["watchEndpointMusicSupportedConfigs"] as? [String: Any],
               let config = configs["watchEndpointMusicConfig"] as? [String: Any],
               let type = config["musicVideoType"] as? String,
               type == "MUSIC_VIDEO_TYPE_OMV" || type == "MUSIC_VIDEO_TYPE_UGC" {
                return true
            }
            return item.values.contains { Self.containsVideo($0, id: id) }
        }
        if let items = node as? [Any] {
            return items.contains { Self.containsVideo($0, id: id) }
        }
        return false
    }
}
