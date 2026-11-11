import Foundation

/// Đại diện cho danh sách phát nhạc (Playlist) cá nhân hoặc từ YouTube Music.
public struct Playlist: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let artworkURL: URL?
    public let trackCount: Int?

    public init(
        id: String,
        title: String,
        subtitle: String = "Danh sách phát",
        artworkURL: URL? = nil,
        trackCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.trackCount = trackCount
    }
}
