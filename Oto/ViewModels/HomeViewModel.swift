import Foundation
import Observation
import OtoCore

/// ViewModel quản lý dữ liệu hiển thị trên màn hình Trang chủ (Home Feed).
@MainActor
@Observable
public final class HomeViewModel {
    public var speedDialItems: [SpeedDialItem] = []
    public var sections: [HomeSection] = []
    public var quickPicks: [Song] = []
    public var listenAgain: [Song] = []
    public var recentlyPlayed: [Song] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private let client: YTMusicClient
    private let cache: HomeCache
    private let pinStore: SpeedDialPinStore
    private var loadTask: Task<Void, Never>?

    public init(
        client: YTMusicClient = .shared,
        cache: HomeCache = .shared,
        pinStore: SpeedDialPinStore = .shared
    ) {
        self.client = client
        self.cache = cache
        self.pinStore = pinStore
        SessionStore.shared.registerResetHandler { [weak self] in
            self?.clearSessionData()
        }
        SessionStore.shared.registerSignInHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.clearSessionData()
                await self?.loadFeed()
            }
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
            self.speedDialItems = pinStore.mergePinned(with: cached.speedDial)
            self.sections = cached.sections
            self.quickPicks = cached.quickPicks
            self.listenAgain = cached.listenAgain
            self.recentlyPlayed = []
        }
    }

    /// Xóa toàn bộ dữ liệu bộ nhớ của trang chủ khi đăng xuất.
    public func clearSessionData() {
        loadTask?.cancel()
        loadTask = nil
        self.speedDialItems = []
        self.sections = []
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
            if !feed.speedDial.isEmpty || !feed.sections.isEmpty || !feed.quickPicks.isEmpty {
                self.speedDialItems = pinStore.mergePinned(with: feed.speedDial)
                self.sections = feed.sections
                self.quickPicks = feed.quickPicks
                self.listenAgain = feed.listenAgain
                self.recentlyPlayed = []
                await cache.saveFeed(
                    speedDial: feed.speedDial,
                    sections: feed.sections,
                    quickPicks: feed.quickPicks,
                    listenAgain: feed.listenAgain
                )
            }
        } catch is CancellationError {
            // Phiên cũ đã bị hủy hoặc view không còn hiển thị; không ghi lỗi trễ vào UI.
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Ghim hoặc Bỏ ghim một item trong Speed Dial.
    public func togglePin(for item: SpeedDialItem) {
        pinStore.togglePin(item)
        self.speedDialItems = pinStore.mergePinned(with: self.speedDialItems)
    }
}
