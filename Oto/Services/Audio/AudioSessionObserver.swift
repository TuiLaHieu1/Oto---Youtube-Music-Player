import Foundation
import AVFoundation
import os

/// Lắng nghe các thông báo từ hệ thống iOS liên quan đến gián đoạn âm thanh và thay đổi cổng cắm tai nghe.
///
/// Chạy hoàn toàn trên @MainActor để đồng bộ an toàn với PlayerViewModel và giao diện người dùng.
/// Tuyệt đối KHÔNG gọi synchronous `setActive` hay tự ý đổi user intent trong các callback này.
@MainActor
public final class AudioSessionObserver {
    public static let shared = AudioSessionObserver()
    private let logger = Logger(subsystem: "com.oto.music", category: "AudioSessionObserver")

    public var onInterruptionBegan: (() -> Void)?
    public var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?
    public var onHeadphonesUnplugged: (() -> Void)?

    private init() {
        setupNotifications()
    }

    private func setupNotifications() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let reasonValue = userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue, reasonValue: reasonValue)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            let reasonValue = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        }
        #endif
    }

    #if os(iOS)
    private func handleInterruption(typeValue: UInt?, optionsValue: UInt, reasonValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        // Chỉ ghi mã hệ thống, không suy interruption là cuộc gọi hay Siri.
        let timestamp = ProcessInfo.processInfo.systemUptime
        let reason = reasonValue.map(String.init) ?? "missing"
        logger.info("""
            Playback interruption t=\(timestamp) type=\(typeValue) \
            reason=\(reason, privacy: .public) options=\(optionsValue)
            """)
        switch type {
        case .began:
            logger.info("Hệ thống thông báo: AVAudioSession bị gián đoạn; chưa xác định tác nhân.")
            onInterruptionBegan?()

        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let shouldResume = options.contains(.shouldResume)
            logger.info("Hệ thống thông báo: AVAudioSession kết thúc gián đoạn (shouldResume: \(shouldResume)).")
            onInterruptionEnded?(shouldResume)

        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        if reason == .oldDeviceUnavailable {
            logger.info("""
                Playback route t=\(ProcessInfo.processInfo.systemUptime) \
                reason=\(reasonValue) action=unplug
                """)
            logger.info("Tai nghe đã rút hoặc bluetooth ngắt kết nối: Kích hoạt bảo vệ loa ngoài.")
            onHeadphonesUnplugged?()
        } else {
            logger.info("""
                Playback route t=\(ProcessInfo.processInfo.systemUptime) \
                reason=\(reasonValue) action=none
                """)
        }
    }
    #endif
}
