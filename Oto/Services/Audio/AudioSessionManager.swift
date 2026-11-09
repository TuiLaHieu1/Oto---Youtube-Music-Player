import Foundation
import AVFoundation
import os

/// Quản lý cấu hình âm thanh nền, gián đoạn cuộc gọi/siri và thay đổi cổng cắm tai nghe.
@MainActor
public final class AudioSessionManager {
    public static let shared = AudioSessionManager()
    private let logger = Logger(subsystem: "com.oto.music", category: "AudioSessionManager")

    public var onInterruptionBegan: (() -> Void)?
    public var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?
    public var onHeadphonesUnplugged: (() -> Void)?

    private init() {
        setupNotifications()
    }

    /// Kích hoạt phiên âm thanh nền cho ứng dụng phát nhạc.
    public func activateSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            logger.error("Lỗi kích hoạt AVAudioSession: \(error.localizedDescription)")
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
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
                return
            }
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        }
        #endif
    }

    #if os(iOS)
    private func handleInterruption(typeValue: UInt, optionsValue: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let shouldResume = options.contains(.shouldResume)
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt) {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        // Khi rút tai nghe hoặc ngắt kết nối bluetooth: tạm dừng bài hát tránh phát ra loa ngoài đột ngột
        if reason == .oldDeviceUnavailable {
            onHeadphonesUnplugged?()
        }
    }
    #endif
}
