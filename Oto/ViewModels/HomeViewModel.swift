import Foundation
import Observation
import OtoCore
import os

/// Nguồn dữ liệu Home có thể thay bằng fake trong test.
/// Tách rõ đọc cache với gọi mạng để view không tự nạp lại khi quay về tab.
public struct HomeFeedSource: Sendable {
    var loadCachedFeed: @Sendable () async -> CachedHomeFeed?
    var fetchFeed: @Sendable () async throws -> YTMusicParsers.HomeFeedContent
    var fetchContinuation: @Sendable (String) async throws -> YTMusicParsers.HomeContinuationPage
    var saveFeed: @Sendable (CachedHomeFeed) async -> Void
    var clearCache: @Sendable () async -> Void

    static func live(client: YTMusicClient = .shared, cache: HomeCache = .shared) -> HomeFeedSource {
        HomeFeedSource(
            loadCachedFeed: { await cache.loadCachedFeed() },
            fetchFeed: { try await client.fetchHomeFeed() },
            fetchContinuation: { token in try await client.fetchHomeContinuation(token: token) },
            saveFeed: { cached in
                await cache.saveFeed(
                    speedDial: cached.speedDial,
                    sections: cached.sections,
                    quickPicks: cached.quickPicks,
                    listenAgain: cached.listenAgain
                )
            },
            clearCache: { await cache.clear() }
        )
    }
}

/// ViewModel quản lý dữ liệu hiển thị trên màn hình Trang chủ (Home Feed).
@MainActor
@Observable
public final class HomeViewModel {
    public var speedDialItems: [SpeedDialItem] = []
    private(set) var pinnedItems: [SpeedDialItem] = []
    public var sections: [HomeSection] = []
    public var quickPicks: [Song] = []
    public var listenAgain: [Song] = []
    public var recentlyPlayed: [Song] = []
    public var isLoading: Bool = false
    public var errorMessage: String?
    private(set) var refreshIncomplete = false
    private(set) var moreRecommendationsUnavailable = false

    /// Kiểm tra xem trang chủ đã có dữ liệu hiển thị hay chưa để tránh chớp màn hình rỗng.
    public var hasContent: Bool {
        !speedDialItems.isEmpty || !sections.isEmpty || !quickPicks.isEmpty || !listenAgain.isEmpty
    }

    var hasVisibleContent: Bool { hasContent || !pinnedItems.isEmpty }

    private let source: HomeFeedSource
    private let pinStore: SpeedDialPinStore
    private let logger = Logger(subsystem: "com.oto.music", category: "HomeViewModel")
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var hasRestoredCache = false

    public init(
        client: YTMusicClient = .shared,
        cache: HomeCache = .shared,
        pinStore: SpeedDialPinStore = .shared,
        source: HomeFeedSource? = nil
    ) {
        self.source = source ?? .live(client: client, cache: cache)
        self.pinStore = pinStore
        SessionStore.shared.registerResetHandler { [weak self] in
            self?.clearSessionData()
        }
        SessionStore.shared.registerSignInHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.source.clearCache()
                self.clearSessionData()
                await self.loadFeed()
            }
        }
    }

    /// Khôi phục dữ liệu từ bộ đệm tài khoản nếu có hoàn toàn bất đồng bộ.
    /// Chỉ đọc cache; không gọi mạng.
    public func loadCachedData() async {
        guard !Task.isCancelled else { return }
        let cached = await source.loadCachedFeed()
        guard !Task.isCancelled else { return }
        hasRestoredCache = true
        pinnedItems = pinStore.loadPinnedItems()
        guard let cached else { return }
        self.speedDialItems = cached.speedDial
        self.sections = cached.sections
        self.quickPicks = cached.quickPicks
        self.listenAgain = cached.listenAgain
        self.recentlyPlayed = []
    }

    /// Gọi khi tab Home xuất hiện lại. Chỉ đọc cache nếu chưa có dữ liệu,
    /// và chỉ gọi mạng khi cache cũng không có nội dung.
    public func loadIfNeeded() async {
        if !hasContent, !hasRestoredCache {
            await loadCachedData()
        }
        guard !hasContent else { return }
        await loadFeed()
    }

    /// Người dùng chủ động làm mới hoặc đổi ngôn ngữ/tài khoản: luôn gọi mạng.
    public func refresh() async {
        await loadFeed()
    }

    /// Xóa toàn bộ dữ liệu bộ nhớ của trang chủ khi đăng xuất.
    public func clearSessionData() {
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        hasRestoredCache = false
        self.speedDialItems = []
        pinnedItems = []
        self.sections = []
        self.quickPicks = []
        self.listenAgain = []
        self.recentlyPlayed = []
        self.errorMessage = nil
        refreshIncomplete = false
        moreRecommendationsUnavailable = false
        isLoading = false
    }

    /// Nạp dữ liệu mới nhất từ YouTube Music API thật, không dùng ID giả.
    public func loadFeed() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let keepsPreviousFeed = hasContent
        pinnedItems = pinStore.loadPinnedItems()
        isLoading = true
        errorMessage = nil
        refreshIncomplete = false
        moreRecommendationsUnavailable = false
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let feed = try await source.fetchFeed()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            guard !feed.speedDial.isEmpty || !feed.sections.isEmpty || !feed.quickPicks.isEmpty
                    || !feed.listenAgain.isEmpty else {
                refreshIncomplete = keepsPreviousFeed
                return
            }

            var sections = feed.sections
            logHomeStatus(stage: "first", sections: sections, hasMore: feed.continuationToken != nil)
            if !keepsPreviousFeed { applyFeed(feed, sections: sections) }

            var nextToken = feed.continuationToken
            var seenTokens = Set<String>()
            for pageNumber in 1...6 {
                guard let token = nextToken, seenTokens.insert(token).inserted else { break }
                do {
                    let page = try await fetchContinuationWithRetry(token, generation: generation)
                    guard generation == loadGeneration, !Task.isCancelled else { return }
                    sections += Self.sectionsForPage(page.sections, number: pageNumber)
                    if !keepsPreviousFeed { self.sections = sections }
                    nextToken = page.nextToken
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == loadGeneration, !Task.isCancelled else { return }
                    let reason = Self.homeFailureCategory(error)
                    let status = "page-\(pageNumber) result=\(reason)"
                    logger.warning("Home fetch stage=\(status, privacy: .public)")
                    logHomeStatus(stage: "partial", sections: sections, hasMore: true)
                    handlePartialFeed(feed, sections: sections, reason: reason)
                    return
                }
            }

            guard generation == loadGeneration, !Task.isCancelled else { return }
            applyFeed(feed, sections: sections)
            logHomeStatus(stage: "complete", sections: sections, hasMore: nextToken != nil)
            await source.saveFeed(CachedHomeFeed(
                speedDial: speedDialItems, sections: sections,
                quickPicks: feed.quickPicks, listenAgain: feed.listenAgain
            ))
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            let reason = Self.homeFailureCategory(error)
            logger.warning("Home fetch stage=first result=\(reason, privacy: .public)")
            refreshIncomplete = hasVisibleContent
        }
    }

    private func handlePartialFeed(
        _ feed: YTMusicParsers.HomeFeedContent, sections: [HomeSection], reason: String
    ) {
        if reason == "response-shape", !sections.isEmpty {
            // Giữ các nhóm đã đọc được ngay cả khi trang kế có cấu trúc chưa hỗ trợ.
            // Dữ liệu thiếu trang không thay bộ đệm đã lưu.
            if sections.count > feed.sections.count {
                applyFeed(feed, sections: sections)
            }
            moreRecommendationsUnavailable = true
        } else {
            refreshIncomplete = true
        }
    }

    private func fetchContinuationWithRetry(
        _ token: String, generation: Int
    ) async throws -> YTMusicParsers.HomeContinuationPage {
        do {
            return try await source.fetchContinuation(token)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch where isRetryableContinuationError(error) {
            try await Task.sleep(for: .milliseconds(300))
            guard generation == loadGeneration else { throw CancellationError() }
            return try await source.fetchContinuation(token)
        }
    }

    private func isRetryableContinuationError(_ error: any Error) -> Bool {
        if let error = error as? URLError { return error.code == .timedOut || error.code == .networkConnectionLost }
        switch error as? YTMusicError {
        case .transport, .serverError: return true
        default: return false
        }
    }

    private static func sectionsForPage(_ sections: [HomeSection], number: Int) -> [HomeSection] {
        sections.map { section in
            let prefix = section.id.hasPrefix("server_speed_dial_") ? "server_speed_dial_" : ""
            return HomeSection(id: "\(prefix)page_\(number)_\(section.id)", title: section.title,
                               subtitle: section.subtitle, items: section.items)
        }
    }

    private func logHomeStatus(stage: String, sections: [HomeSection], hasMore: Bool) {
        let speedDial = sections.filter { $0.id.hasPrefix("server_speed_dial_") }.count
        let status = "\(stage) shelves=\(sections.count) speedDial=\(speedDial) more=\(hasMore)"
        logger.info("Home fetch stage=\(status, privacy: .public)")
    }

    private static func homeFailureCategory(_ error: any Error) -> String {
        switch error as? YTMusicError {
        case .transport: "transport"
        case .authenticationExpired: "session-expired"
        case .permissionDenied: "permission"
        case .rateLimited: "rate-limited"
        case .serverError: "server"
        case .invalidResponse, .parsingError: "response-shape"
        case .invalidURL: "request"
        case nil: "other"
        }
    }

    private func applyFeed(_ feed: YTMusicParsers.HomeFeedContent, sections: [HomeSection]) {
        speedDialItems = sections.first(where: { $0.id.hasPrefix("server_speed_dial_") })?.items ?? feed.speedDial
        self.sections = sections
        quickPicks = feed.quickPicks
        listenAgain = feed.listenAgain
    }

    /// Ghim hoặc Bỏ ghim một item trong Speed Dial.
    public func togglePin(for item: SpeedDialItem) {
        pinStore.togglePin(item)
        pinnedItems = pinStore.loadPinnedItems()
    }
}
