import Foundation

/// Định danh và thông tin siêu dữ liệu của một bài hát trong Oto.
public struct Song: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let duration: TimeInterval
    public let artworkURL: URL?
    public let isExplicit: Bool

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval = 0,
        artworkURL: URL? = nil,
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.isExplicit = isExplicit
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
