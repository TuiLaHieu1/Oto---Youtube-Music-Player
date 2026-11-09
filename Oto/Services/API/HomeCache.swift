import Foundation
import OtoCore
import os

/// Cấu trúc lưu trữ dữ liệu trang chủ kèm thời điểm tạo để tính TTL.
public struct CachedHomeFeed: Codable, Sendable {
    public let quickPicks: [Song]
    public let listenAgain: [Song]
    public let timestamp: Date

    public init(quickPicks: [Song], listenAgain: [Song], timestamp: Date = Date()) {
        self.quickPicks = quickPicks
        self.listenAgain = listenAgain
        self.timestamp = timestamp
    }
}

/// Bộ nhớ đệm tệp cục bộ lưu trữ dữ liệu trang chủ an toàn với TTL 15 phút.
public final class HomeCache: @unchecked Sendable {
    public static let shared = HomeCache()
    private let logger = Logger(subsystem: "com.oto.music", category: "HomeCache")
    private let fileManager = FileManager.default
    private let ttlSeconds: TimeInterval = 900 // 15 phút

    private var cacheFileURL: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("home_feed_cache.json")
    }

    private init() {}

    /// Lưu dữ liệu trang chủ vào bộ đệm tệp cục bộ.
    public func saveFeed(quickPicks: [Song], listenAgain: [Song]) {
        guard let url = cacheFileURL else { return }
        let cached = CachedHomeFeed(quickPicks: quickPicks, listenAgain: listenAgain)
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: url, options: .atomic)
            logger.info("Đã lưu bộ đệm trang chủ thành công.")
        } catch {
            logger.error("Không thể ghi bộ đệm trang chủ: \(error.localizedDescription)")
        }
    }

    /// Tải dữ liệu trang chủ từ bộ đệm nếu chưa hết hạn TTL.
    public func loadCachedFeed() -> CachedHomeFeed? {
        guard let url = cacheFileURL, fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let cached = try JSONDecoder().decode(CachedHomeFeed.self, from: data)
            if Date().timeIntervalSince(cached.timestamp) > ttlSeconds {
                logger.info("Bộ đệm trang chủ đã hết hạn.")
                return nil
            }
            logger.info("Đã khôi phục dữ liệu từ bộ đệm trang chủ.")
            return cached
        } catch {
            logger.error("Không thể đọc bộ đệm trang chủ: \(error.localizedDescription)")
            return nil
        }
    }

    /// Xoá sạch tệp bộ đệm trang chủ khi người dùng đăng xuất.
    public func clear() {
        guard let url = cacheFileURL, fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
        logger.info("Đã xoá bộ đệm trang chủ.")
    }
}
