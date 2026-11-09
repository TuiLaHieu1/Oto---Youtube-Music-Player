import Foundation
import SwiftUI
import OtoCore

/// ViewModel cung cấp danh sách bài hát gợi ý cho màn hình Home, tích hợp bộ đệm an toàn.
@MainActor
@Observable
public final class HomeViewModel {
    public var quickPicks: [Song] = []
    public var listenAgain: [Song] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private let client: YTMusicClient
    private let cache: HomeCache

    public init(
        client: YTMusicClient = .shared,
        cache: HomeCache = .shared
    ) {
        self.client = client
        self.cache = cache
        loadCachedDataOrInitial()
    }

    /// Khôi phục dữ liệu từ bộ đệm nếu có, hoặc dùng mock dự phòng ban đầu.
    private func loadCachedDataOrInitial() {
        if let cached = cache.loadCachedFeed() {
            self.quickPicks = cached.quickPicks
            self.listenAgain = cached.listenAgain
        } else {
            loadInitialMockData()
        }
    }

    /// Nạp dữ liệu mới nhất từ YouTube Music API.
    public func loadFeed() async {
        isLoading = true
        errorMessage = nil

        do {
            let feed = try await client.fetchHomeFeed()
            if !feed.quickPicks.isEmpty || !feed.listenAgain.isEmpty {
                self.quickPicks = feed.quickPicks
                self.listenAgain = feed.listenAgain
                cache.saveFeed(quickPicks: feed.quickPicks, listenAgain: feed.listenAgain)
            }
        } catch {
            errorMessage = error.localizedDescription
            if quickPicks.isEmpty {
                loadInitialMockData()
            }
        }

        isLoading = false
    }

    public func loadInitialMockData() {
        quickPicks = [
            Song(
                id: "qp1",
                title: "Ánh Sao Và Bầu Trời",
                artist: "T.R.I, Cá",
                album: "Ánh Sao Và Bầu Trời (Single)",
                duration: 260.0
            ),
            Song(
                id: "qp2",
                title: "Đưa Em Về Nhà",
                artist: "Grey D, Chillies",
                album: "Dự Báo Thời Tiết Hôm Nay Mưa",
                duration: 245.0
            ),
            Song(
                id: "qp3",
                title: "See You Again",
                artist: "Wiz Khalifa, Charlie Puth",
                album: "Furious 7 Soundtrack",
                duration: 229.0
            ),
            Song(
                id: "qp4",
                title: "Counting Stars",
                artist: "OneRepublic",
                album: "Native",
                duration: 257.0
            )
        ]

        listenAgain = [
            Song(
                id: "la1",
                title: "Chờ Đợi Có Đáng Sợ",
                artist: "Andiez",
                album: "Chờ Đợi Có Đáng Sợ (Single)",
                duration: 275.0
            ),
            Song(
                id: "la2",
                title: "Shape of You",
                artist: "Ed Sheeran",
                album: "÷ (Divide)",
                duration: 233.0
            )
        ]
    }
}
