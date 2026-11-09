import Foundation
import Observation
import OtoCore

/// ViewModel quản lý dữ liệu hiển thị trên màn hình Trang chủ (Home Feed).
@MainActor
@Observable
public final class HomeViewModel {
    public var quickPicks: [Song] = []
    public var listenAgain: [Song] = []
    public var recentlyPlayed: [Song] = []
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
        loadCachedData()
    }

    /// Khôi phục dữ liệu từ bộ đệm tài khoản nếu có.
    private func loadCachedData() {
        if let cached = cache.loadCachedFeed() {
            self.quickPicks = cached.quickPicks
            if cached.listenAgain.count > 4 {
                self.listenAgain = Array(cached.listenAgain.prefix(4))
                self.recentlyPlayed = Array(cached.listenAgain.dropFirst(4))
            } else {
                self.listenAgain = cached.listenAgain
                self.recentlyPlayed = []
            }
        }
    }

    /// Nạp dữ liệu mới nhất từ YouTube Music API thật, không dùng ID giả.
    public func loadFeed() async {
        isLoading = true
        errorMessage = nil

        do {
            let feed = try await client.fetchHomeFeed()
            if !feed.quickPicks.isEmpty || !feed.listenAgain.isEmpty {
                self.quickPicks = feed.quickPicks
                if feed.listenAgain.count > 4 {
                    self.listenAgain = Array(feed.listenAgain.prefix(4))
                    self.recentlyPlayed = Array(feed.listenAgain.dropFirst(4))
                } else {
                    self.listenAgain = feed.listenAgain
                    self.recentlyPlayed = []
                }
                cache.saveFeed(quickPicks: feed.quickPicks, listenAgain: feed.listenAgain)
            }
        } catch is CancellationError {
            // Phiên cũ đã bị hủy hoặc view không còn hiển thị; không ghi lỗi trễ vào UI.
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
