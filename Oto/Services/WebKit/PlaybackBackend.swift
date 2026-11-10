import Foundation

/// Giao diện trừu tượng hóa backend phát nhạc (WebKit WebView hoặc Mock cho unit tests).
@MainActor
public protocol PlaybackBackend: AnyObject {
    var onTrackActivated: ((_ trackId: String, _ generation: Int) -> Void)? { get set }
    var onPlaybackStateChange: ((_ state: Int, _ generation: Int, _ trackId: String) -> Void)? { get set }
    var onPositionUpdate: ((
        _ current: TimeInterval,
        _ duration: TimeInterval,
        _ generation: Int,
        _ trackId: String
    ) -> Void)? { get set }
    var onTrackEnded: ((_ generation: Int, _ trackId: String) -> Void)? { get set }
    var onError: ((_ code: Int, _ generation: Int, _ trackId: String) -> Void)? { get set }
    var onRecoveryRequired: (() -> Void)? { get set }

    func loadVideo(id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool)
    func play()
    func pause()
    func seek(to position: TimeInterval)
    func resetForSignOut()
}
