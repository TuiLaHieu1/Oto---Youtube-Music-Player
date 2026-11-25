#if DEBUG && OTO_STREAM_PROBE
import Foundation
import UIKit

/// Bộ nhớ URL audio đã lấy bằng yt-dlp, theo hạn dùng của từng URL. Chỉ trong bộ nhớ, giới hạn số mục.
/// Gộp các yêu cầu trùng cho cùng một bài để một bài không chạy yt-dlp hai lần cùng lúc.
@MainActor
final class YTStreamURLCache {
    struct Entry {
        let url: URL
        let expiresAt: Date
    }

    static let shared = YTStreamURLCache()
    /// URL còn dưới khoảng này là coi như hết hạn, để không phát một URL sắp chết giữa bài.
    static let refreshMargin: TimeInterval = 10 * 60
    private static let capacity = 40

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<URL?, Never>] = [:]

    func freshURL(for videoID: String, now: Date = Date()) -> URL? {
        guard let entry = self.entries[videoID], entry.expiresAt.timeIntervalSince(now) > Self.refreshMargin else {
            return nil
        }
        return entry.url
    }

    func invalidate(_ videoID: String) {
        self.entries[videoID] = nil
        self.order.removeAll { $0 == videoID }
    }

    /// Trả URL còn hạn nếu có; nếu không thì chạy yt-dlp (gộp yêu cầu trùng). Nil khi không lấy được.
    func url(for videoID: String, reason: String) async -> URL? {
        if let url = self.freshURL(for: videoID) { return url }
        if let task = self.inFlight[videoID] { return await task.value }
        let task = Task { @MainActor [weak self] () -> URL? in
            // Xin thêm thời gian chạy khi app ở nền (ví dụ Next từ Lock Screen sau khi Pause lâu).
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "oto.stream-resolve")
            defer {
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            let result = await PythonStreamResolver.resolve(videoID: videoID)
            StreamProbeLog.write(
                "StreamProbe resolve reason=\(reason) appState=\(UIApplication.shared.applicationState.rawValue) "
                    + "ok=\(result.url != nil)"
            )
            guard let url = result.url else { return nil }
            let lifetime = TimeInterval(result.secondsUntilExpiry ?? 0)
            self?.store(url, for: videoID, expiresAt: Date().addingTimeInterval(lifetime))
            return url
        }
        self.inFlight[videoID] = task
        let url = await task.value
        self.inFlight[videoID] = nil
        return url
    }

    func prefetch(_ videoIDs: [String]) {
        for videoID in videoIDs where YTMusicClient.isValidVideoID(videoID) {
            guard self.freshURL(for: videoID) == nil, self.inFlight[videoID] == nil else { continue }
            Task { _ = await self.url(for: videoID, reason: "prefetch") }
        }
    }

    private func store(_ url: URL, for videoID: String, expiresAt: Date) {
        self.entries[videoID] = Entry(url: url, expiresAt: expiresAt)
        self.order.removeAll { $0 == videoID }
        self.order.append(videoID)
        while self.order.count > Self.capacity {
            let oldest = self.order.removeFirst()
            self.entries[oldest] = nil
        }
    }
}
#endif
