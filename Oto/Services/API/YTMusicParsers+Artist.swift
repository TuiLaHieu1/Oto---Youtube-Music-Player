import Foundation
import OtoCore

extension YTMusicParsers {
    public struct ArtistSongsEndpoint: Sendable, Equatable {
        let browseId: String
        let params: String?
    }

    struct ArtistSongsPage: Sendable {
        let songs: [Song]
        let nextToken: String?
    }

    public struct ArtistDetail: Sendable, Equatable {
        public let id: String
        public let name: String
        public let description: String?
        public let thumbnailURL: URL?
        public let songs: [Song]
        public let songsEndpoint: ArtistSongsEndpoint?
        public let albums: [Playlist]
        public let sections: [HomeSection]

        public init(
            id: String,
            name: String,
            description: String? = nil,
            thumbnailURL: URL? = nil,
            songs: [Song] = [],
            albums: [Playlist] = [],
            sections: [HomeSection] = [],
            songsEndpoint: ArtistSongsEndpoint? = nil
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.thumbnailURL = thumbnailURL
            self.songs = songs
            self.songsEndpoint = songsEndpoint
            self.albums = albums
            self.sections = sections
        }
    }

    public static func parseArtistDetail(browseId: String, from data: Data) throws -> ArtistDetail {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        let headers = collectRenderers(named: "musicImmersiveHeaderRenderer", in: root)
            + collectRenderers(named: "musicVisualHeaderRenderer", in: root)
            + collectRenderers(named: "musicHeaderRenderer", in: root)
        guard let header = headers.first,
              let name = artistText(in: header["title"]), !name.isEmpty else {
            throw YTMusicError.parsingError
        }
        let description = artistText(in: header["description"])
        let thumbnail = (header["thumbnail"] as? [String: Any])
            ?? (header["foregroundThumbnail"] as? [String: Any])

        let contents = root["contents"] as? [String: Any]
        let column = contents?["singleColumnBrowseResultsRenderer"] as? [String: Any]
        let tabs = column?["tabs"] as? [[String: Any]]
        let tab = tabs?.first?["tabRenderer"] as? [String: Any]
        let tabContent = tab?["content"] as? [String: Any]
        let sectionList = tabContent?["sectionListRenderer"] as? [String: Any]
        let shelfContainers = sectionList?["contents"] as? [[String: Any]] ?? []
        let sections: [HomeSection] = shelfContainers.enumerated().compactMap { index, container in
            guard let shelf = container["musicCarouselShelfRenderer"] as? [String: Any] else { return nil }
            let parsed = parseCarouselShelf(shelf)
            guard !parsed.items.isEmpty else { return nil }
            return HomeSection(
                id: "artist_\(index)_\(parsed.title)",
                title: parsed.title,
                subtitle: parsed.subtitle,
                items: parsed.items
            )
        }

        let songShelves = shelfContainers.compactMap { $0["musicShelfRenderer"] as? [String: Any] }
        let songSource: Any = songShelves.isEmpty ? root : songShelves
        var seenSongs = Set<String>()
        let songs = collectRenderers(named: "musicResponsiveListItemRenderer", in: songSource)
            .compactMap { parseResponsiveListItem($0) }
            .filter { seenSongs.insert($0.id).inserted }
            .map { song in
                songShelves.isEmpty ? song : Self.linkArtistShelfSong(song, browseId: browseId, name: name)
            }

        var seenAlbums = Set<String>()
        let albums = collectRenderers(named: "musicTwoRowItemRenderer", in: root)
            .compactMap { parsePlaylistFromTwoRow($0) }
            .filter { $0.id.hasPrefix("MPRE") && seenAlbums.insert($0.id).inserted }

        let songsEndpoint = songShelves.lazy.compactMap(Self.artistSongsEndpoint(in:)).first
        return ArtistDetail(
            id: browseId,
            name: name,
            description: description,
            thumbnailURL: extractThumbnailURL(from: thumbnail),
            songs: songs,
            albums: albums,
            sections: sections,
            songsEndpoint: songsEndpoint
        )
    }

    private static func linkArtistShelfSong(_ song: Song, browseId: String, name: String) -> Song {
        guard browseId.hasPrefix("UC"), song.artists.isEmpty,
              song.artist.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        else { return song }
        return Song(
            id: song.id, title: song.title, artist: song.artist,
            artists: [ArtistReference(browseId: browseId, name: name)],
            album: song.album, duration: song.duration, artworkURL: song.artworkURL, isExplicit: song.isExplicit
        )
    }

    private static func artistSongsEndpoint(in shelf: [String: Any]) -> ArtistSongsEndpoint? {
        guard let contents = shelf["contents"] as? [[String: Any]],
              Self.collectRenderers(named: "musicResponsiveListItemRenderer", in: contents)
                .contains(where: { Self.parseResponsiveListItem($0) != nil }),
              let bottom = shelf["bottomEndpoint"] as? [String: Any],
              let browse = bottom["browseEndpoint"] as? [String: Any],
              let id = browse["browseId"] as? String, !id.isEmpty else { return nil }
        return ArtistSongsEndpoint(browseId: id, params: browse["params"] as? String)
    }

    static func parseArtistSongsPage(from data: Data, isContinuation: Bool) throws -> ArtistSongsPage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        let containers = Self.collectRenderers(
            named: isContinuation ? "appendContinuationItemsAction" : "sectionListRenderer", in: root
        )
        guard !containers.isEmpty else { throw YTMusicError.parsingError }
        let songs = Self.collectRenderers(named: "musicResponsiveListItemRenderer", in: containers)
            .compactMap { Self.parseResponsiveListItem($0) }
        let token = Self.collectRenderers(named: "continuationCommand", in: containers)
            .compactMap { $0["token"] as? String }.first { !$0.isEmpty }
        return ArtistSongsPage(songs: songs, nextToken: token)
    }

    private static func artistText(in value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        let runs = object["runs"] as? [[String: Any]]
        let text = runs?.compactMap { $0["text"] as? String }.joined()
            ?? (object["simpleText"] as? String)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
