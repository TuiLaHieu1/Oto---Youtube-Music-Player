import Foundation
import OtoCore

/// Snapshot không nhạy cảm để khôi phục queue và vị trí nghe, luôn giữ trạng thái pause khi mở app.
public struct PlaybackSessionSnapshot: Codable, Sendable, Equatable {
    public let queue: QueueSnapshot
    public let currentPosition: TimeInterval

    public init(queue: QueueSnapshot, currentPosition: TimeInterval) {
        self.queue = queue
        self.currentPosition = currentPosition
    }
}

/// Lưu queue theo tài khoản hiện tại; không lưu thông tin xác thực hoặc dữ liệu phiên WebKit.
@MainActor
public final class PlaybackQueueStore {
    public static let shared = PlaybackQueueStore()
    private let defaults: UserDefaults
    private let accountId: () -> String?
    private let keyPrefix = "oto.playback.snapshot.v1."

    public init(
        defaults: UserDefaults = .standard,
        accountId: @escaping () -> String? = { CookieStorage.shared.opaqueAccountId }
    ) {
        self.defaults = defaults
        self.accountId = accountId
    }

    public func load() -> PlaybackSessionSnapshot? {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(PlaybackSessionSnapshot.self, from: data),
              snapshot.queue.isValid,
              snapshot.queue.currentIndex != nil,
              snapshot.currentPosition.isFinite,
              snapshot.currentPosition >= 0 else {
            return nil
        }
        return snapshot
    }

    public func save(_ snapshot: PlaybackSessionSnapshot) {
        guard snapshot.queue.isValid,
              snapshot.queue.currentIndex != nil,
              snapshot.currentPosition.isFinite,
              snapshot.currentPosition >= 0,
              let data = try? JSONEncoder().encode(snapshot) else {
            clear()
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    public func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    private var storageKey: String {
        keyPrefix + (accountId() ?? "guest")
    }
}
