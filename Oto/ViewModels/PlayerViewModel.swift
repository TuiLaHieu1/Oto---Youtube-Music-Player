import Foundation
import SwiftUI
import OtoCore
import os

/// ViewModel quản lý toàn bộ trạng thái phát nhạc và hàng đợi trên MainActor.
@MainActor
@Observable
public final class PlayerViewModel {
    public var playbackState: PlaybackState = .idle
    public var currentPosition: TimeInterval = 0
    public var isExpanded: Bool = false
    public var showLyrics: Bool = false
    public var showQueue: Bool = false
    public var showAuth: Bool = false

    public let queueManager: QueueManager
    public let clock: InterpolatedClock

    private let backend: any PlaybackBackend
    private let logger = Logger(subsystem: "com.oto.music", category: "PlayerViewModel")
    private var stateMachine = PlaybackStateMachine()
    private var positionTimerTask: Task<Void, Never>?
    private var radioLoadTask: Task<Void, Never>?
    private var playlistLoadTask: Task<Void, Never>?

    public init(
        queueManager: QueueManager = QueueManager(),
        clock: InterpolatedClock = InterpolatedClock(),
        backend: (any PlaybackBackend)? = nil
    ) {
        self.queueManager = queueManager
        self.clock = clock
        self.backend = backend ?? SingletonPlayerWebView.shared
        setupPlayerBridge()
        setupAudioSessionObserver()
        setupNowPlayingCommands()
    }

    public var currentSong: Song? {
        playbackState.currentSong ?? queueManager.currentSong
    }

    public var isPlaying: Bool {
        playbackState.isPlaying
    }

    public var isBuffering: Bool {
        playbackState.isBuffering
    }

    /// Trạng thái nút Play/Pause trên giao diện: hiển thị Pause khi đang phát hoặc đang tải bài mới.
    public var shouldShowPauseButton: Bool {
        isPlaying || isBuffering || stateMachine.userIntent == .playing
    }

    /// Thời lượng phát thực tế đo được từ WebKit engine, bù đắp trường hợp API không trả duration.
    public var runtimeDuration: TimeInterval?

    /// Thời lượng phát hiệu lực ưu tiên runtime duration từ media player.
    public var effectiveDuration: TimeInterval {
        if let runtime = runtimeDuration, runtime > 0 { return runtime }
        return currentSong?.duration ?? 0
    }

    public var isShuffleEnabled: Bool { queueManager.isShuffleEnabled }
    public var repeatMode: RepeatMode { queueManager.repeatMode }

    // MARK: - User Intent Actions

    /// Bắt đầu phát một bài hát cụ thể từ ý định người dùng và cập nhật hàng đợi.
    public func play(song: Song) {
        queueManager.setQueue(songs: [song])
        applyEffects(stateMachine.userPlay(song: song))
    }

    /// Bắt đầu phát bài hát chỉ định và nạp danh sách Radio / Up Next tự động từ YouTube Music.
    public func playWithRadio(song: Song) {
        play(song: song)
        loadRadioQueue(for: song.id)
    }

    /// Nạp danh sách bài hát gợi ý Radio Up Next từ YouTube Music cho videoId đang phát.
    public func loadRadioQueue(for videoId: String) {
        radioLoadTask?.cancel()
        radioLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let radioSongs = try await YTMusicClient.shared.fetchUpNextQueue(videoId: videoId)
                guard !Task.isCancelled, self.currentSong?.id == videoId else { return }
                let remaining = radioSongs.filter { $0.id != videoId }
                if !remaining.isEmpty {
                    self.queueManager.appendQueue(songs: remaining)
                    self.logger.info("Đã nạp \(remaining.count) bài hát Radio Up Next cho video \(videoId)")
                }
            } catch {
                self.logger.warning("Không thể nạp Radio Up Next cho video \(videoId): \(error.localizedDescription)")
            }
        }
    }

    /// Bắt đầu phát một danh sách phát hoặc album từ YouTube Music.
    public func playPlaylist(id: String, fallbackSong: Song? = nil) {
        if let fallbackSong {
            play(song: fallbackSong)
        }
        playlistLoadTask?.cancel()
        playlistLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let songs = try await YTMusicClient.shared.fetchPlaylistSongs(playlistId: id)
                guard !Task.isCancelled, !songs.isEmpty else { return }
                self.playQueue(songs: songs, startIndex: 0)
                self.logger.info("Đã nạp và phát danh sách phát \(id) với \(songs.count) bài.")
            } catch {
                self.logger.warning("Không thể nạp playlist \(id): \(error.localizedDescription)")
            }
        }
    }

    /// Khởi tạo hàng đợi mới từ danh sách bài hát và bắt đầu phát từ vị trí chỉ định.
    public func playQueue(songs: [Song], startIndex: Int = 0) {
        guard !songs.isEmpty else { return }
        queueManager.setQueue(songs: songs, startIndex: startIndex)
        if let targetSong = queueManager.currentSong {
            applyEffects(stateMachine.userPlay(song: targetSong))
        }
    }

    /// Phát bài hát tại một vị trí cụ thể trong hàng đợi và cập nhật currentIndex.
    public func playQueueItem(at index: Int) {
        if let targetSong = queueManager.skipToIndex(index) {
            applyEffects(stateMachine.userPlay(song: targetSong))
        }
    }

    public func resume() { applyEffects(stateMachine.userResume()) }
    public func pause() { applyEffects(stateMachine.userPause()) }

    public func togglePlayPause() {
        if shouldShowPauseButton {
            pause()
        } else {
            resume()
        }
    }

    public func next() {
        if let nextSong = queueManager.next() {
            applyEffects(stateMachine.userPlay(song: nextSong))
            if queueManager.remainingCount <= 2 {
                loadRadioQueue(for: nextSong.id)
            }
        } else {
            pause()
            seek(to: 0)
        }
    }

    public func previous() {
        if currentPosition > 3.0 {
            seek(to: 0)
        } else if let prevSong = queueManager.previous() {
            applyEffects(stateMachine.userPlay(song: prevSong))
        } else {
            seek(to: 0)
        }
    }

    public func seek(to position: TimeInterval) {
        applyEffects(stateMachine.userSeek(to: position))
    }

    public func toggleShuffle() { queueManager.toggleShuffle() }
    public func toggleRepeat() { queueManager.toggleRepeat() }
}

// MARK: - Internal Engine Bridge & Synchronization

extension PlayerViewModel {
    private func applyEffects(_ effects: PlaybackEffects) {
        if effects.shouldActivateSession {
            Task {
                do {
                    try await AudioSessionCoordinator.shared.configureAndActivate()
                } catch {
                    self.logger.error("Lỗi kích hoạt AVAudioSession: \(error.localizedDescription)")
                }
            }
        }

        if let payload = effects.shouldStartEngine {
            runtimeDuration = nil
            clock.pause(at: payload.startSeconds)
            backend.loadVideo(
                id: payload.songId,
                startSeconds: payload.startSeconds,
                generation: payload.generation,
                shouldPlay: effects.shouldResumeEngine || stateMachine.userIntent == .playing
            )
        }

        if effects.shouldResumeEngine {
            clock.play(from: stateMachine.currentPosition, rate: 1.0)
            backend.play()
            startPositionTracking()
        }

        if effects.shouldPauseEngine {
            clock.pause()
            backend.pause()
            stopPositionTracking()
        }

        if let seekTime = effects.shouldSeekEngine {
            clock.seek(to: seekTime)
            backend.seek(to: seekTime)
        }

        if effects.shouldAdvanceToNextTrack {
            next()
        }

        syncPublicState()
    }

    private func syncPublicState() {
        playbackState = stateMachine.playbackState
        currentPosition = stateMachine.currentPosition

        NowPlayingManager.shared.updateNowPlaying(
            song: currentSong,
            isPlaying: isPlaying,
            currentTime: currentPosition,
            duration: effectiveDuration
        )
    }

    private func setupAudioSessionObserver() {
        AudioSessionObserver.shared.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.applyEffects(self.stateMachine.interruptionBegan())
        }
        AudioSessionObserver.shared.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            self.applyEffects(self.stateMachine.interruptionEnded(shouldResume: shouldResume))
        }
        AudioSessionObserver.shared.onHeadphonesUnplugged = { [weak self] in
            guard let self else { return }
            self.applyEffects(self.stateMachine.routeUnplugged())
        }
    }

    private func setupPlayerBridge() {
        backend.onTrackActivated = { [weak self] trackId, generation in
            guard let self,
                  generation == self.stateMachine.currentGeneration,
                  trackId == self.stateMachine.currentSong?.id else { return }
            self.logger.info("Engine đã xác nhận bài active: \(trackId), gen: \(generation)")
        }

        backend.onPlaybackStateChange = { [weak self] (stateCode, gen, trackId) in
            self?.handleBridgeStateChange(stateCode: stateCode, generation: gen, trackId: trackId)
        }

        backend.onPositionUpdate = { [weak self] (cur, dur, gen, trackId) in
            self?.handleBridgePositionUpdate(current: cur, duration: dur, generation: gen, trackId: trackId)
        }

        backend.onTrackEnded = { [weak self] gen, trackId in
            self?.handleBridgeTrackEnded(generation: gen, trackId: trackId)
        }

        backend.onError = { [weak self] (code, gen, trackId) in
            self?.handleBridgeError(code: code, generation: gen, trackId: trackId)
        }

        backend.onRemoteCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .play: self.resume()
            case .pause: self.pause()
            case .next: self.next()
            case .previous: self.previous()
            case .seek(let position): self.seek(to: position)
            }
        }

        backend.onRecoveryRequired = { [weak self] in
            guard let self else { return }
            self.logger.warning("Đang thực hiện khôi phục playback sau sự cố crash...")
            self.applyEffects(self.stateMachine.engineCrashed())
        }
    }

    private func handleBridgeStateChange(stateCode: Int, generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }

        let engineState: EnginePlaybackState
        switch stateCode {
        case 1: engineState = .playing
        case 2: engineState = .paused
        default: engineState = .buffering
        }

        applyEffects(stateMachine.engineStateChanged(engineState, generation: generation))

        if engineState == .playing {
            if !clock.isPlaying { clock.play(from: currentPosition, rate: 1.0) }
            startPositionTracking()
        } else if engineState == .paused || engineState == .buffering {
            clock.pause()
        }
    }

    private func handleBridgePositionUpdate(
        current: TimeInterval,
        duration: TimeInterval,
        generation: Int,
        trackId: String
    ) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }

        if duration > 0 { runtimeDuration = duration }
        stateMachine.engineTimeUpdated(currentTime: current, generation: generation)
        let clockPos = clock.currentPosition()
        if abs(clockPos - current) > 0.5 { clock.seek(to: current) }
        currentPosition = current
        NowPlayingManager.shared.updateNowPlaying(
            song: currentSong,
            isPlaying: isPlaying,
            currentTime: current,
            duration: effectiveDuration
        )
    }

    private func handleBridgeTrackEnded(generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }
        applyEffects(stateMachine.engineTrackEnded(generation: generation))
    }

    private func handleBridgeError(code: Int, generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration else { return }
        logger.error("Lỗi playback YouTube Web (code: \(code), track: \(trackId), gen: \(generation))")
        if code == 100 || code == 101 || code == 150 || code == 152 {
            next()
        }
    }

    private func setupNowPlayingCommands() {
        let mgr = NowPlayingManager.shared
        mgr.onPlayCommand = { [weak self] in Task { @MainActor in self?.resume() } }
        mgr.onPauseCommand = { [weak self] in Task { @MainActor in self?.pause() } }
        mgr.onTogglePlayPauseCommand = { [weak self] in Task { @MainActor in self?.togglePlayPause() } }
        mgr.onNextCommand = { [weak self] in Task { @MainActor in self?.next() } }
        mgr.onPreviousCommand = { [weak self] in Task { @MainActor in self?.previous() } }
        mgr.onSeekCommand = { [weak self] pos in Task { @MainActor in self?.seek(to: pos) } }
    }

    private func startPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self = self, self.isPlaying else { break }
                self.currentPosition = self.clock.currentPosition()
            }
        }
    }

    private func stopPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = nil
    }
}
