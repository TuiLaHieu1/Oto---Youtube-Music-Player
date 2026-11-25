#if DEBUG && OTO_STREAM_PROBE
import Foundation
import UIKit

/// Kết quả lấy URL cho một bài.
enum YTStreamResolution: Sendable {
    case url(URL)
    /// `unavailable`: lỗi do chính bài (bị chặn, không có định dạng phát được), nên bỏ qua bài.
    case failed(unavailable: Bool)
}

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
    private var inFlight: [String: Task<YTStreamResolution, Never>] = [:]

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

    /// Trả URL còn hạn nếu có; nếu không thì chạy yt-dlp (gộp yêu cầu trùng).
    func resolve(_ videoID: String, reason: String) async -> YTStreamResolution {
        if let url = self.freshURL(for: videoID) { return .url(url) }
        if let task = self.inFlight[videoID] { return await task.value }
        let task = Task { @MainActor [weak self] () -> YTStreamResolution in
            // Xin thêm thời gian chạy khi app ở nền (ví dụ Next từ Lock Screen sau khi Pause lâu).
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "oto.stream-resolve")
            defer {
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            let result = await PythonStreamResolver.resolve(videoID: videoID)
            StreamProbeLog.write(
                "StreamProbe resolve reason=\(reason) appState=\(UIApplication.shared.applicationState.rawValue) "
                    + "ok=\(result.url != nil) label=\(result.errorLabel ?? "none")"
            )
            guard let url = result.url else { return .failed(unavailable: result.isTrackUnavailable) }
            let lifetime = TimeInterval(result.secondsUntilExpiry ?? 0)
            self?.store(url, for: videoID, expiresAt: Date().addingTimeInterval(lifetime))
            return .url(url)
        }
        self.inFlight[videoID] = task
        let result = await task.value
        self.inFlight[videoID] = nil
        return result
    }

    /// Lấy trước URL; gọi `completion` cho từng bài lấy được để router nạp sẵn bộ đệm.
    func prefetch(_ videoIDs: [String], completion: @escaping @MainActor (String) -> Void) {
        for videoID in videoIDs where YTMusicClient.isValidVideoID(videoID) {
            if self.freshURL(for: videoID) != nil {
                completion(videoID)
                continue
            }
            guard self.inFlight[videoID] == nil else { continue }
            Task {
                if case .url = await self.resolve(videoID, reason: "prefetch") { completion(videoID) }
            }
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

/// Backend rỗng thay cho WebKit trong bản khảo sát: mọi bài YouTube Music đi qua AVPlayer.
@MainActor
final class NoopPlaybackBackend: PlaybackBackend {
    var onTrackActivated: ((String, Int) -> Void)?
    var onPlaybackStateChange: ((Int, Int, String) -> Void)?
    var onPositionUpdate: ((TimeInterval, TimeInterval, Int, String) -> Void)?
    var onTrackEnded: ((Int, String) -> Void)?
    var onError: ((Int, Int, String) -> Void)?
    var onRemoteCommand: ((PlaybackRemoteCommand) -> Void)?
    var onRecoveryRequired: (() -> Void)?

    func loadVideo(id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool) {
        self.onError?(-1, generation, id)
    }
    func play() {}
    func pause() {}
    func seek(to position: TimeInterval) {}
    func resetForSignOut() {}
}
#endif
