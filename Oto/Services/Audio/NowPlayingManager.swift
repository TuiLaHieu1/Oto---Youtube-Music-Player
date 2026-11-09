import Foundation
import MediaPlayer
import OtoCore

/// Quản lý thông tin hiển thị tại Màn hình khóa (Lock Screen), Dynamic Island và Trung tâm điều khiển.
public final class NowPlayingManager: @unchecked Sendable {
    public static let shared = NowPlayingManager()

    public var onPlayCommand: (@Sendable () -> Void)?
    public var onPauseCommand: (@Sendable () -> Void)?
    public var onNextCommand: (@Sendable () -> Void)?
    public var onPreviousCommand: (@Sendable () -> Void)?
    public var onSeekCommand: (@Sendable (TimeInterval) -> Void)?

    private init() {
        setupRemoteCommands()
    }

    /// Cập nhật thông tin bài hát đang phát lên NowPlayingInfoCenter.
    public func updateNowPlaying(
        song: Song?,
        isPlaying: Bool,
        currentTime: TimeInterval
    ) {
        #if os(iOS)
        guard let song = song else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let album = song.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    private func setupRemoteCommands() {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onPlayCommand?()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onPauseCommand?()
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNextCommand?()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousCommand?()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.onSeekCommand?(positionEvent.positionTime)
            return .success
        }
        #endif
    }
}
