import Foundation

/// Thẻ phần tử trên lưới Speed Dial (Quay số nhanh 3x3) của YouTube Music.
/// Hỗ trợ cả bài hát lẻ, danh sách phát, album và nghệ sĩ.
public struct SpeedDialItem: Identifiable, Sendable, Codable, Hashable {
    public enum Kind: String, Sendable, Codable, Hashable {
        case song
        case playlist
        case album
        case artist
    }

    public let id: String
    public let title: String
    public let subtitle: String
    public let artworkURL: URL?
    private let artists: [ArtistReference]?
    public let kind: Kind
    public var isPinned: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        artworkURL: URL? = nil,
        kind: Kind = .song,
        isPinned: Bool = false,
        artists: [ArtistReference] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.artists = artists.isEmpty ? nil : artists
        self.kind = kind
        self.isPinned = isPinned
    }

    /// Khởi tạo SpeedDialItem từ đối tượng Song có sẵn.
    public init(song: Song, isPinned: Bool = false) {
        self.id = song.id
        self.title = song.title
        self.subtitle = song.artist
        self.artworkURL = song.artworkURL
        self.artists = song.artists.isEmpty ? nil : song.artists
        self.kind = .song
        self.isPinned = isPinned
    }

    /// Chuyển đổi thành Song đối với các item thuộc loại bài hát, trả về nil nếu là album, playlist hoặc artist.
    public var asSong: Song? {
        guard kind == .song else { return nil }
        return Song(
            id: id,
            title: title,
            artist: subtitle,
            artists: artists ?? [],
            artworkURL: artworkURL
        )
    }
}
