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
    private var loadTask: Task<Void, Never>?

    public init(
        client: YTMusicClient = .shared,
        cache: HomeCache = .shared
    ) {
        self.client = client
        self.cache = cache
        SessionStore.shared.registerResetHandler { [weak self] in
            self?.clearSessionData()
        }
        loadTask = Task { [weak self] in
            await self?.loadCachedData()
        }
    }

    /// Khôi phục dữ liệu từ bộ đệm tài khoản nếu có hoàn toàn bất đồng bộ.
    public func loadCachedData() async {
        guard !Task.isCancelled else { return }
        if let cached = await cache.loadCachedFeed() {
            guard !Task.isCancelled else { return }
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

    /// Xóa toàn bộ dữ liệu bộ nhớ của trang chủ khi đăng xuất.
    public func clearSessionData() {
        loadTask?.cancel()
        loadTask = nil
        self.quickPicks = []
        self.listenAgain = []
        self.recentlyPlayed = []
        self.errorMessage = nil
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
                await cache.saveFeed(quickPicks: feed.quickPicks, listenAgain: feed.listenAgain)
            }
        } catch is CancellationError {
            // Phiên cũ đã bị hủy hoặc view không còn hiển thị; không ghi lỗi trễ vào UI.
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
