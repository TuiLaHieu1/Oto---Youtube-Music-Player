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
    public func configureAndActivate(force: Bool = false) async throws {
        #if os(iOS)
        if isSessionActive && !force { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .default, options: [])

        if #available(iOS 27.0, *) {
            try await session.activate(options: [])
            isSessionActive = true
            logger.info("AVAudioSession đã được kích hoạt bất đồng bộ (iOS async API).")
        } else {
            // iOS 17 Fallback: Chạy an toàn trên cooperative background executor của actor
            try session.setActive(true)
            isSessionActive = true
            logger.info("AVAudioSession đã được kích hoạt trên background actor executor (iOS 17 fallback).")
        }
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
        // Giữ trạng thái isSessionActive nếu hệ thống sẽ tự khôi phục phiên sau cuộc gọi
        logger.info("AudioSessionCoordinator ghi nhận sự kiện ngắt từ hệ thống.")
    }
}
