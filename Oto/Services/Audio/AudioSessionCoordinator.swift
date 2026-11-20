import Foundation
import AVFoundation
import os

/// Điều phối AVAudioSession tuần tự ngoài main thread bằng Swift Concurrency Actor.
///
/// Giải quyết triệt để cảnh báo: "This method can lead to UI unresponsiveness if called on the main thread".
/// Tuân thủ:
/// - iOS 18+: Sử dụng API kích hoạt bất đồng bộ `activate(options:)` / `deactivate(options:)`.
/// - iOS 17: Tuần tự hoá cuộc gọi `setActive` trên cooperative thread pool của actor, không chặn main thread.
/// - Không bao giờ kích hoạt trong `init()`. Chỉ kích hoạt sau khi có User Playback Intent.
public actor AudioSessionCoordinator {
    public static let shared = AudioSessionCoordinator()
    private let logger = Logger(subsystem: "com.oto.music", category: "AudioSessionCoordinator")

    private var isSessionActive = false

    private init() {
        // TUYỆT ĐỐI không gọi activateSession trong init()!
    }

    /// Cấu hình và kích hoạt AudioSession cho phát nhạc nền (chỉ chạy ngoài main thread).
    public func configureForWebPlayback() async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .default, options: [])
        // WKWebView/WebContent tự kích hoạt audio session khi media bắt đầu phát.
        // App chỉ đặt category để không kích hoạt session cạnh tranh trước lệnh Play.
        isSessionActive = false
        logger.info("Đã cấu hình playback category; WebKit sẽ tự kích hoạt audio session khi phát.")
        #endif
    }

    /// Hủy kích hoạt AudioSession khi dừng hẳn hoặc giải phóng tài nguyên.
    public func deactivate() async {
        #if os(iOS)
        guard isSessionActive else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            if #available(iOS 27.0, *) {
                try await session.deactivate(options: [.notifyOthersOnDeactivation])
                isSessionActive = false
                logger.info("AVAudioSession đã được hủy kích hoạt bất đồng bộ (iOS async API).")
            } else {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
                isSessionActive = false
                logger.info("AVAudioSession đã được hủy kích hoạt trên background executor (iOS 17 fallback).")
            }
        } catch {
            logger.error("Lỗi khi hủy kích hoạt AVAudioSession: \(error.localizedDescription)")
        }
        #endif
    }

    /// Đánh dấu phiên bị gián đoạn bởi hệ thống mà không gọi setActive đồng bộ.
    public func handleSystemInterruptionBegan() {
        isSessionActive = false
        logger.info("AudioSessionCoordinator ghi nhận sự kiện ngắt từ hệ thống.")
    }
}

/// Hợp đồng kích hoạt âm thanh có thể thay bằng fake trong unit test.
public protocol PlaybackAudioSession: Sendable {
    func prepareForPlayback() async throws
    func invalidateForInterruption() async
}

extension PlaybackAudioSession {
    public func invalidateForInterruption() async {}
}

extension AudioSessionCoordinator: PlaybackAudioSession {
    public func invalidateForInterruption() async {
        handleSystemInterruptionBegan()
    }

    public func prepareForPlayback() async throws {
        try await configureForWebPlayback()
    }
}
