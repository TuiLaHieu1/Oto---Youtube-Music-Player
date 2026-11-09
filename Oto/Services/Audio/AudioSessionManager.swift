import Foundation
import AVFoundation

/// Quản lý cấu hình âm thanh nền, gián đoạn cuộc gọi/siri và thay đổi cổng cắm tai nghe.
public final class AudioSessionManager: @unchecked Sendable {
    public static let shared = AudioSessionManager()

    public var onInterruptionBegan: (@Sendable () -> Void)?
    public var onInterruptionEnded: (@Sendable (_ shouldResume: Bool) -> Void)?
    public var onHeadphonesUnplugged: (@Sendable () -> Void)?

    private init() {
        setupNotifications()
    }

    /// Kích hoạt phiên âm thanh nền cho ứng dụng phát nhạc.
    public func activateSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            // Không làm crash ứng dụng nếu audio session không khởi tạo được trên simulator
        }
        #endif
    }

    private func setupNotifications() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        #endif
    }

    #if os(iOS)
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let shouldResume = options.contains(.shouldResume)
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        // Khi rút tai nghe hoặc ngắt kết nối bluetooth: tạm dừng bài hát tránh phát ra loa ngoài đột ngột
        if reason == .oldDeviceUnavailable {
            onHeadphonesUnplugged?()
        }
    }
    #endif
}
