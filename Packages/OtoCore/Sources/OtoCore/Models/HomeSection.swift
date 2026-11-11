import Foundation

/// Đại diện cho một phân đoạn nội dung trên trang chủ (Home feed) từ YouTube Music.
public struct HomeSection: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let items: [SpeedDialItem]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        items: [SpeedDialItem] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.items = items
    }
}
