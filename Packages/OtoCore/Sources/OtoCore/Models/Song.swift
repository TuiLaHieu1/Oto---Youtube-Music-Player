import Foundation

/// Nghệ sĩ gắn với một bài hát, giữ đúng browse ID do YouTube Music trả về.
/// Không suy ra ID bằng cách tách chuỗi tên nghệ sĩ.
public struct ArtistReference: Identifiable, Sendable, Codable, Hashable {
    public let browseId: String
    public let name: String
    public var id: String { browseId }

    public init(browseId: String, name: String) {
        self.browseId = browseId
        self.name = name
    }
}

/// Định danh và thông tin siêu dữ liệu của một bài hát trong Oto.
public struct Song: Identifiable, Sendable, Codable, Hashable {
    public static let localIDPrefix = "local:"
    public var isLocal: Bool { id.hasPrefix(Self.localIDPrefix) }

    public let id: String
    public let title: String
    public let artist: String
    public let artists: [ArtistReference]
    public let album: String?
    public let duration: TimeInterval
    public let artworkURL: URL?
    public let isExplicit: Bool

    public init(
        id: String,
        title: String,
        artist: String,
        artists: [ArtistReference] = [],
        album: String? = nil,
        duration: TimeInterval = 0,
        artworkURL: URL? = nil,
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artists = artists
        self.album = album
        self.duration = duration
        if let artworkURL {
            self.artworkURL = artworkURL
        } else if !id.isEmpty && !id.hasPrefix(Self.localIDPrefix) {
            self.artworkURL = URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
        } else {
            self.artworkURL = nil
        }
        self.isExplicit = isExplicit
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, artists, album, duration, artworkURL, isExplicit
    }

    /// Bộ đệm cũ không có `artists`; đọc thiếu trường này phải vẫn hợp lệ.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.artist = try container.decode(String.self, forKey: .artist)
        self.artists = try container.decodeIfPresent([ArtistReference].self, forKey: .artists) ?? []
        self.album = try container.decodeIfPresent(String.self, forKey: .album)
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        self.isExplicit = try container.decodeIfPresent(Bool.self, forKey: .isExplicit) ?? false
        if let decodedArtwork = try container.decodeIfPresent(URL.self, forKey: .artworkURL) {
            self.artworkURL = decodedArtwork
        } else if !id.isEmpty && !id.hasPrefix(Self.localIDPrefix) {
            self.artworkURL = URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
        } else {
            self.artworkURL = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        if !artists.isEmpty {
            try container.encode(artists, forKey: .artists)
        }
        try container.encodeIfPresent(album, forKey: .album)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(artworkURL, forKey: .artworkURL)
        try container.encode(isExplicit, forKey: .isExplicit)
    }
}

/// Thông tin cơ bản về nghệ sĩ.
public struct Artist: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    public let thumbnailURL: URL?

    public init(id: String, name: String, thumbnailURL: URL? = nil) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
    }
}

/// Thông tin về album hoặc đĩa đơn.
public struct Album: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let title: String
    public let artist: String
    public let artworkURL: URL?
    public let year: Int?
    public let songs: [Song]

    public init(
        id: String,
        title: String,
        artist: String,
        artworkURL: URL? = nil,
        year: Int? = nil,
        songs: [Song] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.year = year
        self.songs = songs
    }
}
