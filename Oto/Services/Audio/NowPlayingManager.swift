import Foundation
import ImageIO
import MediaPlayer
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
import OtoCore
#if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
import MediaAccessibility
import os
#endif

#if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
enum MusicHapticsPilotSample {
    static let videoID = "67ibXO8viXE"
    static let isrc = "GBUM71308836"
    static let song = Song(
        id: Self.videoID, title: "I'm Not the Only One", artist: "Sam Smith", album: "In the Lonely Hour"
    )
}
#endif

/// Quản lý thông tin hiển thị tại Màn hình khóa (Lock Screen), Dynamic Island và Trung tâm điều khiển.
public final class NowPlayingManager: @unchecked Sendable {
    public static let shared = NowPlayingManager()

    public var onPlayCommand: (@Sendable () -> Void)?
    public var onPauseCommand: (@Sendable () -> Void)?
    public var onTogglePlayPauseCommand: (@Sendable () -> Void)?
    public var onNextCommand: (@Sendable () -> Void)?
    public var onPreviousCommand: (@Sendable () -> Void)?
    public var onSeekCommand: (@Sendable (TimeInterval) -> Void)?
    private let fetchArtwork: @Sendable (URL) async throws -> Data

    #if canImport(UIKit)
    private struct ArtworkKey: Equatable {
        let songId: String
        let url: URL
    }

    private var cachedArtworkKey: ArtworkKey?
    private var cachedArtworkImage: UIImage?
    private var currentArtworkKey: ArtworkKey?
    private var artworkRequestGeneration = 0
    private var loadingArtworkKey: ArtworkKey?
    private var failedArtworkKey: ArtworkKey?
    private var artworkRetryCount = 0
    private var artworkTask: Task<Void, Never>?
    private var thumbnailTask: Task<Data?, Never>?
    private var retryArtworkTask: Task<Void, Never>?
    #endif
    #if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
    @MainActor private var hapticsStatusToken: (any NSCopying)?
    @MainActor private var didLogHapticsPilot = false
    #endif
    private let retryArtworkDelayNanoseconds: UInt64

    init(
        fetchArtwork: @escaping @Sendable (URL) async throws -> Data = { url in
            try await URLSession.shared.data(from: url).0
        },
        registerRemoteCommands: Bool = true,
        retryArtworkDelayNanoseconds: UInt64 = 30_000_000_000
    ) {
        self.fetchArtwork = fetchArtwork
        self.retryArtworkDelayNanoseconds = retryArtworkDelayNanoseconds
        if registerRemoteCommands { setupRemoteCommands() }
    }

    #if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
    @available(iOS 18.0, *)
    @MainActor
    private func observeHapticsPilot() {
        let manager = MAMusicHapticsManager.shared
        let logger = Logger(subsystem: "com.oto.music", category: "MusicHapticsPilot")
        let report: @Sendable (String, Bool) -> Void = { code, active in
            logger.info("Haptics pilot status sample=\(code == MusicHapticsPilotSample.isrc) active=\(active)")
        }
        hapticsStatusToken = manager.addStatusObserver(report)
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let stored = info?[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] as? String
        let declared = Bundle.main.object(forInfoDictionaryKey: "MusicHapticsSupported") as? Bool == true
        logger.info("""
            Haptics pilot check systemActive=\(manager.isActive) registered=\(self.hapticsStatusToken != nil) \
            localISRCMatches=\(stored == MusicHapticsPilotSample.isrc) declared=\(declared)
            """)
    }
    #endif

    /// Cập nhật thông tin bài hát đang phát lên NowPlayingInfoCenter với hỗ trợ runtime duration.
    @MainActor
    public func updateNowPlaying(
        song: Song?,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval? = nil
    ) {
        #if os(iOS)
        guard let song = song else {
            clearArtwork()
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

        #if DEBUG && OTO_HAPTICS_PILOT
        if #available(iOS 18.0, *), song.id == MusicHapticsPilotSample.videoID {
            info[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] = MusicHapticsPilotSample.isrc
        }
        #endif

        if let album = song.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        #if canImport(UIKit)
        if let artworkURL = song.artworkURL {
            let key = ArtworkKey(songId: song.id, url: artworkURL)
            selectArtwork(key)
            if cachedArtworkKey == key, let image = cachedArtworkImage {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
            } else {
                loadArtworkAsync(for: key)
            }
        } else {
            clearArtwork()
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
        #if DEBUG && OTO_HAPTICS_PILOT
        if #available(iOS 18.0, *), song.id == MusicHapticsPilotSample.videoID, isPlaying, !didLogHapticsPilot {
            didLogHapticsPilot = true
            observeHapticsPilot()
        }
        #endif
        #endif
    }

    #if canImport(UIKit)
    @MainActor
    private func selectArtwork(_ key: ArtworkKey) {
        guard currentArtworkKey != key else { return }
        artworkTask?.cancel()
        artworkTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        retryArtworkTask?.cancel()
        retryArtworkTask = nil
        loadingArtworkKey = nil
        failedArtworkKey = nil
        artworkRetryCount = 0
        artworkRequestGeneration += 1
        currentArtworkKey = key
    }

    @MainActor
    private func loadArtworkAsync(for key: ArtworkKey) {
        guard loadingArtworkKey != key else { return }
        guard failedArtworkKey != key else { return }
        loadingArtworkKey = key
        let requestGeneration = artworkRequestGeneration
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let imageData: Data?
            if let data = try? await self.fetchArtwork(key.url) {
                guard !Task.isCancelled, self.artworkRequestGeneration == requestGeneration else { return }
                let task = Task.detached(priority: .utility) {
                    Self.downsampleArtwork(data)
                }
                self.thumbnailTask = task
                imageData = await task.value
                if self.artworkRequestGeneration == requestGeneration { self.thumbnailTask = nil }
            } else {
                imageData = nil
            }
            guard let imageData, let image = UIImage(data: imageData) else {
                if !Task.isCancelled,
                   self.artworkRequestGeneration == requestGeneration,
                   self.loadingArtworkKey == key {
                    self.loadingArtworkKey = nil
                    self.artworkTask = nil
                    self.failedArtworkKey = key
                    if self.artworkRetryCount < 2 {
                        self.artworkRetryCount += 1
                        self.retryArtworkTask = Task { [weak self] in
                            guard let self else { return }
                            try? await Task.sleep(nanoseconds: self.retryArtworkDelayNanoseconds)
                            guard !Task.isCancelled, self.artworkRequestGeneration == requestGeneration else {
                                return
                            }
                            self.failedArtworkKey = nil
                            self.retryArtworkTask = nil
                            self.loadArtworkAsync(for: key)
                        }
                    }
                }
                return
            }
            guard !Task.isCancelled,
                  self.artworkRequestGeneration == requestGeneration,
                  self.loadingArtworkKey == key else { return }
            self.loadingArtworkKey = nil
            self.artworkTask = nil
            self.failedArtworkKey = nil
            self.artworkRetryCount = 0
            self.cachedArtworkKey = key
            self.cachedArtworkImage = image
            guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private static func downsampleArtwork(_ data: Data) -> Data? {
        guard !Task<Never, Never>.isCancelled else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        guard !Task<Never, Never>.isCancelled else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    @MainActor
    private func clearArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        retryArtworkTask?.cancel()
        retryArtworkTask = nil
        currentArtworkKey = nil
        artworkRequestGeneration += 1
        loadingArtworkKey = nil
        failedArtworkKey = nil
        artworkRetryCount = 0
        cachedArtworkKey = nil
        cachedArtworkImage = nil
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
