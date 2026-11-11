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
    public let kind: Kind
    public var isPinned: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        artworkURL: URL? = nil,
        kind: Kind = .song,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.kind = kind
        self.isPinned = isPinned
    }

    /// Khởi tạo SpeedDialItem từ đối tượng Song có sẵn.
    public init(song: Song, isPinned: Bool = false) {
        self.id = song.id
        self.title = song.title
        self.subtitle = song.artist
        self.artworkURL = song.artworkURL
        self.kind = .song
        self.isPinned = isPinned
    }

    /// Chuyển đổi thành Song đối với các item thuộc loại bài hát.
    public var asSong: Song {
        Song(
            id: id,
            title: title,
            artist: subtitle,
            artworkURL: artworkURL
        )
    }
}
