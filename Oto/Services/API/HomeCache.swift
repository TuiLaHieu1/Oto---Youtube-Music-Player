import Foundation
import CryptoKit
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

/// Bộ nhớ đệm tệp cục bộ lưu trữ dữ liệu trang chủ an toàn, tách biệt theo tài khoản người dùng với TTL 15 phút.
@MainActor
public final class HomeCache {
    public static let shared = HomeCache()
    private let logger = Logger(subsystem: "com.oto.music", category: "HomeCache")
    private let fileManager = FileManager.default
    private let ttlSeconds: TimeInterval = 900 // 15 phút

    private init() {}

    /// Mã định danh phân vùng bộ nhớ đệm dựa trên cookie phiên hiện tại (ngăn rò rỉ dữ liệu giữa các tài khoản).
    public var accountScopeKey: String {
        let cookies = CookieStorage.shared.loadCookies()
        if let authCookie = cookies.first(where: { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" }) {
            let digest = SHA256.hash(data: Data(authCookie.value.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return "user_\(hex.prefix(12))"
        }
        return "guest"
    }

    private var cacheFileURL: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("home_feed_\(accountScopeKey).json")
    }

    /// Lưu dữ liệu trang chủ vào bộ đệm tệp cục bộ theo tài khoản ngoài MainActor.
    public func saveFeed(quickPicks: [Song], listenAgain: [Song]) {
        guard let url = cacheFileURL else { return }
        let cached = CachedHomeFeed(quickPicks: quickPicks, listenAgain: listenAgain)
        Task.detached(priority: .utility) { [logger = self.logger] in
            do {
                let data = try JSONEncoder().encode(cached)
                try data.write(to: url, options: .atomic)
                logger.info("Đã lưu bộ đệm trang chủ theo phân vùng tài khoản.")
            } catch {
                logger.error("Không thể ghi bộ đệm trang chủ: \(error.localizedDescription)")
            }
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

    /// Xoá sạch toàn bộ các tệp bộ đệm trang chủ của tất cả tài khoản khi đăng xuất.
    public func clear() {
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        if let fileList = try? fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil) {
            for file in fileList where file.lastPathComponent.hasPrefix("home_feed_") {
                try? fileManager.removeItem(at: file)
            }
        }
        logger.info("Đã xoá sạch toàn bộ tệp bộ đệm trang chủ trên đĩa.")
    }
}
