import Foundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
#endif
import OtoCore

/// Quản lý thông tin hiển thị tại Màn hình khóa (Lock Screen), Dynamic Island và Trung tâm điều khiển.
public final class NowPlayingManager: @unchecked Sendable {
    public static let shared = NowPlayingManager()

    public var onPlayCommand: (@Sendable () -> Void)?
    public var onPauseCommand: (@Sendable () -> Void)?
    public var onTogglePlayPauseCommand: (@Sendable () -> Void)?
    public var onNextCommand: (@Sendable () -> Void)?
    public var onPreviousCommand: (@Sendable () -> Void)?
    public var onSeekCommand: (@Sendable (TimeInterval) -> Void)?

    #if canImport(UIKit)
    private var cachedArtworkSongId: String?
    private var cachedArtworkImage: UIImage?
    private var artworkTask: Task<Void, Never>?
    #endif

    private init() {
        setupRemoteCommands()
    }

    /// Cập nhật thông tin bài hát đang phát lên NowPlayingInfoCenter với hỗ trợ runtime duration.
    public func updateNowPlaying(
        song: Song?,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval? = nil
    ) {
        #if os(iOS)
        guard let song = song else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let totalDuration: TimeInterval
        if let customDuration = duration, customDuration > 0 {
            totalDuration = customDuration
        } else {
            totalDuration = song.duration
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyPlaybackDuration: totalDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyMediaType: MPMediaType.music.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]

        if let album = song.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        #if canImport(UIKit)
        if let artworkURL = song.artworkURL {
            if cachedArtworkSongId == song.id, let image = cachedArtworkImage {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            } else {
                loadArtworkAsync(
                    for: song,
                    url: artworkURL,
                    currentTime: currentTime,
                    duration: totalDuration,
                    isPlaying: isPlaying
                )
            }
        }
        #endif

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.skipForwardCommand.preferredIntervals = []
        commandCenter.skipBackwardCommand.preferredIntervals = []
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    #if canImport(UIKit)
    private func loadArtworkAsync(
        for song: Song,
        url: URL,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) {
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            guard !Task.isCancelled else { return }
            self?.cachedArtworkSongId = song.id
            self?.cachedArtworkImage = image
            self?.updateNowPlaying(song: song, isPlaying: isPlaying, currentTime: currentTime, duration: duration)
        }
    }
    #endif

    private func setupRemoteCommands() {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        // Oto phát nhạc theo track. Tắt các lệnh tua kiểu podcast để hệ thống ưu tiên Previous/Next.
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.skipForwardCommand.preferredIntervals = []
        commandCenter.skipBackwardCommand.preferredIntervals = []
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false

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

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            if let onToggle = self?.onTogglePlayPauseCommand {
                onToggle()
            } else {
                self?.onPlayCommand?()
            }
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
