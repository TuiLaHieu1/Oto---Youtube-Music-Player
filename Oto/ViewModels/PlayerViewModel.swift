import Foundation
import SwiftUI
import OtoCore
import os

/// ViewModel quản lý toàn bộ trạng thái phát nhạc và hàng đợi trên MainActor.
///
/// Phối hợp chặt chẽ với:
/// 1. `PlaybackStateMachine` (OtoCore) để phân tách rạch ròi user intent, engine state, interruption state.
/// 2. `AudioSessionCoordinator` (Actor ngoài main thread) để kích hoạt/hủy phiên an toàn, không block UI.
/// 3. `AudioSessionObserver` để đón nhận gián đoạn cuộc gọi/siri và ngắt tai nghe mà không gọi setActive đồng bộ.
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

    /// Thời lượng phát thực tế đo được từ WebKit engine, bù đắp trường hợp API không trả duration.
    public var runtimeDuration: TimeInterval?

    /// Thời lượng phát hiệu lực ưu tiên runtime duration từ media player.
    public var effectiveDuration: TimeInterval {
        if let runtime = runtimeDuration, runtime > 0 {
            return runtime
        }
        return currentSong?.duration ?? 0
    }

    public var isShuffleEnabled: Bool {
        queueManager.isShuffleEnabled
    }

    public var repeatMode: RepeatMode {
        queueManager.repeatMode
    }

    // MARK: - User Intent Actions

    /// Bắt đầu phát một bài hát cụ thể từ ý định người dùng và cập nhật hàng đợi.
    public func play(song: Song) {
        queueManager.setQueue(songs: [song])
        let effects = stateMachine.userPlay(song: song)
        applyEffects(effects)
    }

    /// Khởi tạo hàng đợi mới từ danh sách bài hát và bắt đầu phát từ vị trí chỉ định.
    public func playQueue(songs: [Song], startIndex: Int = 0) {
        guard !songs.isEmpty else { return }
        queueManager.setQueue(songs: songs, startIndex: startIndex)
        if let targetSong = queueManager.currentSong {
            let effects = stateMachine.userPlay(song: targetSong)
            applyEffects(effects)
        }
    }

    /// Phát bài hát tại một vị trí cụ thể trong hàng đợi và cập nhật currentIndex.
    public func playQueueItem(at index: Int) {
        if let targetSong = queueManager.skipToIndex(index) {
            let effects = stateMachine.userPlay(song: targetSong)
            applyEffects(effects)
        }
    }

    /// Người dùng tiếp tục phát (Resume).
    public func resume() {
        let effects = stateMachine.userResume()
        applyEffects(effects)
    }

    /// Người dùng tạm dừng (Pause).
    public func pause() {
        let effects = stateMachine.userPause()
        applyEffects(effects)
    }

    /// Đổi trạng thái Play / Pause.
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Chuyển bài tiếp theo trong hàng đợi.
    public func next() {
        if let nextSong = queueManager.next() {
            let effects = stateMachine.userPlay(song: nextSong)
            applyEffects(effects)
        } else {
            pause()
            seek(to: 0)
        }
    }

    /// Quay lại bài trước hoặc tua về đầu bài.
    public func previous() {
        if currentPosition > 3.0 {
            seek(to: 0)
        } else if let prevSong = queueManager.previous() {
            let effects = stateMachine.userPlay(song: prevSong)
            applyEffects(effects)
        } else {
            seek(to: 0)
        }
    }

    /// Nhảy đến vị trí thời gian chỉ định (Seek).
    public func seek(to position: TimeInterval) {
        let effects = stateMachine.userSeek(to: position)
        applyEffects(effects)
    }

    /// Bật/tắt trộn bài.
    public func toggleShuffle() {
        queueManager.toggleShuffle()
    }

    /// Đổi chế độ lặp.
    public func toggleRepeat() {
        queueManager.toggleRepeat()
    }
}

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
            let effects = self.stateMachine.interruptionBegan()
            self.applyEffects(effects)
        }

        AudioSessionObserver.shared.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            let effects = self.stateMachine.interruptionEnded(shouldResume: shouldResume)
            self.applyEffects(effects)
        }

        AudioSessionObserver.shared.onHeadphonesUnplugged = { [weak self] in
            guard let self else { return }
            let effects = self.stateMachine.routeUnplugged()
            self.applyEffects(effects)
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
            let effects = self.stateMachine.engineCrashed()
            self.applyEffects(effects)
        }
    }

    private func handleBridgeStateChange(stateCode: Int, generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }

        let engineState: EnginePlaybackState
        switch stateCode {
        case 1:
            engineState = .playing
        case 2:
            engineState = .paused
        default:
            engineState = .buffering
        }

        let effects = stateMachine.engineStateChanged(engineState, generation: generation)
        applyEffects(effects)

        if engineState == .playing {
            if !clock.isPlaying {
                clock.play(from: currentPosition, rate: 1.0)
            }
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

        if duration > 0 {
            runtimeDuration = duration
        }

        stateMachine.engineTimeUpdated(currentTime: current, generation: generation)
        let clockPos = clock.currentPosition()
        if abs(clockPos - current) > 0.5 {
            clock.seek(to: current)
        }
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
        let effects = stateMachine.engineTrackEnded(generation: generation)
        applyEffects(effects)
    }

    private func handleBridgeError(code: Int, generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration else {
            logger.warning(
                "Bỏ qua lỗi playback từ gen cũ \(generation) (hiện tại: \(self.stateMachine.currentGeneration))"
            )
            return
        }
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
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard let self = self, self.isPlaying else { break }
                let newPos = self.clock.currentPosition()
                self.currentPosition = newPos
            }
        }
    }

    private func stopPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = nil
    }
}
