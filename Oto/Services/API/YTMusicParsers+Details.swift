import Foundation
import OtoCore

// MARK: - Album & Artist Details

extension YTMusicParsers {
    /// Typealias đại diện cho chi tiết Album để tương thích nhất quán.
    public typealias AlbumDetail = Album

    /// Dữ liệu chi tiết của nghệ sĩ bao gồm bài hát nổi bật và danh sách album.
    public struct ArtistDetail: Sendable, Equatable {
        public let id: String
        public let name: String
        public let description: String?
        public let thumbnailURL: URL?
        public let songs: [Song]
        public let albums: [Playlist]

        public init(
            id: String,
            name: String,
            description: String? = nil,
            thumbnailURL: URL? = nil,
            songs: [Song] = [],
            albums: [Playlist] = []
        ) {
            self.id = id; self.name = name; self.description = description
            self.thumbnailURL = thumbnailURL; self.songs = songs; self.albums = albums
        }
    }

    private struct AlbumHeaderMetadata {
        let title: String, artist: String, year: Int?, artworkURL: URL?
    }

    private struct ArtistHeaderMetadata {
        let name: String, description: String?, thumbnailURL: URL?
    }

    /// Phân tích dữ liệu chi tiết Album từ browse endpoint (MPREb_...).
    public static func parseAlbumDetail(browseId: String, from data: Data) throws -> Album {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        guard let meta = parseAlbumHeader(from: json) else {
            throw YTMusicError.parsingError
        }
        let itemRenderers = collectRenderers(named: "musicResponsiveListItemRenderer", in: json)
        let songs: [Song] = itemRenderers.compactMap { renderer in
            guard let song = parseResponsiveListItem(renderer) else { return nil }
            return Song(
                id: song.id,
                title: song.title,
                artist: song.artist == "Nhiều nghệ sĩ" ? meta.artist : song.artist,
                artists: song.artists,
                album: song.album ?? meta.title,
                duration: song.duration,
                artworkURL: song.artworkURL ?? meta.artworkURL,
                isExplicit: song.isExplicit
            )
        }
        return Album(id: browseId, title: meta.title, artist: meta.artist,
                     artworkURL: meta.artworkURL, year: meta.year, songs: songs)
    }

    private static func extractHeaderTitle(from header: [String: Any]) -> String? {
        guard let titleObj = header["title"] as? [String: Any] else { return nil }
        if let runs = titleObj["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        guard let simpleText = titleObj["simpleText"] as? String else { return nil }
        let text = simpleText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func parseAlbumHeader(from json: [String: Any]) -> AlbumHeaderMetadata? {
        var artist = "Nhiều nghệ sĩ"
        var year: Int?
        let headers = collectRenderers(named: "musicDetailHeaderRenderer", in: json)
            + collectRenderers(named: "musicResponsiveHeaderRenderer", in: json)
            + collectRenderers(named: "musicHeaderRenderer", in: json)
        guard let header = headers.first,
              let title = extractHeaderTitle(from: header) else { return nil }
        let subObj = (header["subtitle"] as? [String: Any]) ?? (header["straplineTextOne"] as? [String: Any])
        if let runs = subObj?["runs"] as? [[String: Any]] {
            for text in runs.compactMap({ $0["text"] as? String }) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count == 4, let yr = Int(trimmed), yr > 1900 && yr < 2100 {
                    year = yr
                } else if artist == "Nhiều nghệ sĩ" && !trimmed.isEmpty
                    && !["•", "Album", "EP", "Single"].contains(trimmed) {
                    artist = trimmed
                }
            }
        }
        let thumb = (header["thumbnail"] as? [String: Any]) ?? (header["thumbnailRenderer"] as? [String: Any])
        return AlbumHeaderMetadata(title: title, artist: artist, year: year,
                                   artworkURL: extractThumbnailURL(from: thumb))
    }

    /// Phân tích dữ liệu chi tiết Nghệ sĩ từ browse endpoint (UC...).
    public static func parseArtistDetail(browseId: String, from data: Data) throws -> ArtistDetail {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        guard let meta = parseArtistHeader(from: json) else {
            throw YTMusicError.parsingError
        }
        var songs: [Song] = []
        var seenSongIds = Set<String>()
        for renderer in collectRenderers(named: "musicResponsiveListItemRenderer", in: json) {
            if let song = parseResponsiveListItem(renderer), !seenSongIds.contains(song.id) {
                seenSongIds.insert(song.id)
                songs.append(song)
            }
        }
        var albums: [Playlist] = []
        var seenAlbumIds = Set<String>()
        for renderer in collectRenderers(named: "musicTwoRowItemRenderer", in: json) {
            if let playlist = parsePlaylistFromTwoRow(renderer), !seenAlbumIds.contains(playlist.id) {
                seenAlbumIds.insert(playlist.id)
                albums.append(playlist)
            }
        }
        return ArtistDetail(id: browseId, name: meta.name, description: meta.description,
                            thumbnailURL: meta.thumbnailURL, songs: songs, albums: albums)
    }

    private static func parseArtistHeader(from json: [String: Any]) -> ArtistHeaderMetadata? {
        var desc: String?
        let headers = collectRenderers(named: "musicVisualHeaderRenderer", in: json)
            + collectRenderers(named: "musicImmersiveHeaderRenderer", in: json)
            + collectRenderers(named: "musicHeaderRenderer", in: json)
        guard let header = headers.first,
              let name = extractHeaderTitle(from: header) else { return nil }
        if let descObj = header["description"] as? [String: Any] {
            if let runs = descObj["runs"] as? [[String: Any]] {
                desc = runs.compactMap { $0["text"] as? String }.joined(separator: " ")
            } else if let simple = descObj["simpleText"] as? String {
                desc = simple
            }
        }
        let thumb = (header["thumbnail"] as? [String: Any]) ?? (header["foregroundThumbnail"] as? [String: Any])
        return ArtistHeaderMetadata(name: name, description: desc,
                                    thumbnailURL: extractThumbnailURL(from: thumb))
    }
}
