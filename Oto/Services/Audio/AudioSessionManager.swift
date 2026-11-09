import Foundation
import AVFoundation
import os

/// Quản lý cấu hình âm thanh nền, gián đoạn cuộc gọi/siri và thay đổi cổng cắm tai nghe.
public final class AudioSessionManager: @unchecked Sendable {
    public static let shared = AudioSessionManager()
    private let logger = Logger(subsystem: "com.oto.music", category: "AudioSessionManager")

    public var onInterruptionBegan: (@Sendable () -> Void)?
    public var onInterruptionEnded: (@Sendable (_ shouldResume: Bool) -> Void)?
    public var onHeadphonesUnplugged: (@Sendable () -> Void)?

    private var isSessionActive = false
    private let lock = NSLock()

    private init() {
        setupNotifications()
        activateSession()
    }

    /// Kích hoạt phiên âm thanh nền cho ứng dụng phát nhạc (chỉ kích hoạt 1 lần duy nhất).
    public func activateSession() {
        #if os(iOS)
        lock.lock()
        defer { lock.unlock() }
        guard !isSessionActive else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            isSessionActive = true
            logger.info("AVAudioSession đã được kích hoạt thành công.")
        } catch {
            logger.error("Lỗi kích hoạt AVAudioSession: \(error.localizedDescription)")
        }
        #endif
    }

    private func setupNotifications() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
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
            lock.lock()
            isSessionActive = false
            lock.unlock()
            logger.info("AVAudioSession bị gián đoạn (cuộc gọi / Siri).")
            onInterruptionBegan?()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let shouldResume = options.contains(.shouldResume)
            if shouldResume {
                activateSession()
            }
            logger.info("AVAudioSession kết thúc gián đoạn (shouldResume: \(shouldResume)).")
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
            logger.info("Tai nghe đã rút hoặc bluetooth ngắt kết nối, tạm dừng phát.")
            onHeadphonesUnplugged?()
        }
    }
    #endif
}
