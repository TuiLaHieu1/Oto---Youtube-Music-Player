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
    public var playbackErrorMessage: String?
    var playbackSourceTitle: String?
    var confirmedVideoSelectionID: String?
    private var loadingWatchdogTask: Task<Void, Never>?
    var isWatchdogActive: Bool { loadingWatchdogTask != nil && !(loadingWatchdogTask?.isCancelled ?? true) }

    private var queueRevision = 0
    public let queueManager: QueueManager
    public let clock: InterpolatedClock
    let backend: any PlaybackBackend
    let audioSession: any PlaybackAudioSession
    var activationTask: Task<Void, Never>?
    var interruptionTask: Task<Void, Never>?
    var pendingEngineLoad: PlaybackEffects.StartEnginePayload?
    var engineOperationRevision = 0
    var selectionRevision = 0
    var usesRadio = false
    var waitsForArtistRadio = false
    var artistRadioEndGeneration: Int?
    var artistRadioAdvanceWasManual = false
    let catalog: any PlaybackCatalog
    let updatesSystemNowPlaying: Bool
    let logger = Logger(subsystem: "com.oto.music", category: "PlayerViewModel")
    var stateMachine = PlaybackStateMachine()
    private var positionTimerTask: Task<Void, Never>?
    var radioLoadTask: Task<Void, Never>?
    var playlistLoadTask: Task<Void, Never>?
    var albumLoadTask: Task<Void, Never>?

    public init(
        queueManager: QueueManager = QueueManager(),
        clock: InterpolatedClock = InterpolatedClock(),
        backend: (any PlaybackBackend)? = nil,
        audioSession: any PlaybackAudioSession = AudioSessionCoordinator.shared,
        catalog: any PlaybackCatalog = YTMusicClient.shared,
        updatesSystemNowPlaying: Bool = true
    ) {
        self.queueManager = queueManager
        self.clock = clock
        self.backend = backend ?? LocalMusicPlaybackRouter(web: SingletonPlayerWebView.shared)
        self.audioSession = audioSession
        self.catalog = catalog
        self.updatesSystemNowPlaying = updatesSystemNowPlaying
        let previousQueueObserver = queueManager.onQueueChanged
        queueManager.onQueueChanged = { [weak self] in
            previousQueueObserver?()
            Task { @MainActor [weak self] in
                self?.queueRevision &+= 1
            }
        }
        setupPlayerBridge()
        setupAudioSessionObserver()
        if updatesSystemNowPlaying { setupNowPlayingCommands() }
    }

    public var currentSong: Song? { playbackState.currentSong ?? queueManager.currentSong }
    public var isPlaying: Bool { playbackState.isPlaying }
    public var isBuffering: Bool { playbackState.isBuffering }
    public var shouldShowPauseButton: Bool { isPlaying || isBuffering || stateMachine.userIntent == .playing }
    public var runtimeDuration: TimeInterval?
    public var effectiveDuration: TimeInterval {
        runtimeDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? currentSong?.duration ?? 0
    }
    var queueSnapshot: QueueManager.Snapshot {
        _ = queueRevision
        return queueManager.snapshot()
    }

    public var isShuffleEnabled: Bool { queueSnapshot.isShuffleEnabled }
    public var repeatMode: RepeatMode { queueSnapshot.repeatMode }
    public var queueItems: [QueueItem] { queueSnapshot.items }
    var canShuffle: Bool { queueItems.count > 1 }

    public static func shouldLoadRadioQueue(remainingCount: Int, repeatMode: RepeatMode, userInitiated: Bool) -> Bool {
        (repeatMode != .one || userInitiated) && remainingCount <= 2
    }

    static func stableDisplayedPosition(
        previous: TimeInterval, candidate: TimeInterval
    ) -> TimeInterval {
        guard candidate.isFinite, candidate >= 0 else { return previous }
        if candidate < previous, previous - candidate <= 1.0 {
            return previous
        }
        return candidate
    }

    public func retryCurrentTrack() {
        guard let currentSong = queueManager.currentSong else { return }
        playbackErrorMessage = nil
        backend.resetCrashRecoveryBudget()
        applyEffects(stateMachine.userPlay(song: currentSong))
    }

    public func clearForSignOut() {
        activationTask?.cancel()
        activationTask = nil
        pendingEngineLoad = nil
        engineOperationRevision += 1
        cancelLoadingWatchdog()
        playbackErrorMessage = nil
        cancelCatalogSelection()
        positionTimerTask?.cancel()
        clock.pause(at: 0)
        currentPosition = 0
        runtimeDuration = nil
        isExpanded = false
        showLyrics = false
        showQueue = false
        showAuth = false
        queueManager.setQueue(songs: [])
        stateMachine = PlaybackStateMachine()
        backend.resetForSignOut()
        syncPublicState()
    }

}

// MARK: - Internal Engine Bridge & Synchronization
extension PlayerViewModel {
    func applyEffects(_ effects: PlaybackEffects) {
        if let payload = effects.shouldStartEngine {
            cancelLoadingWatchdog()
            pendingEngineLoad = payload
            runtimeDuration = nil
            playbackErrorMessage = nil
            clock.pause(at: payload.startSeconds)
        }
        if effects.shouldActivateSession || effects.shouldStartEngine != nil || effects.shouldResumeEngine {
            scheduleEngineOperation()
        }
        if effects.shouldPauseEngine {
            clock.pause()
            backend.pause()
            stopPositionTracking()
        }
        if let seekTime = effects.shouldSeekEngine {
            clock.seek(to: seekTime)
            backend.seek(to: seekTime)
            currentPosition = seekTime
        }
        if effects.shouldAdvanceToNextTrack { advanceQueue(userInitiated: false) }
        syncPublicState()
    }

    func syncPublicState() {
        playbackState = stateMachine.playbackState
        currentPosition = stateMachine.currentPosition
        if updatesSystemNowPlaying { NowPlayingManager.shared.updateNowPlaying(
            song: currentSong, isPlaying: isPlaying, currentTime: currentPosition, duration: effectiveDuration
        ) }
    }
    private func setupAudioSessionObserver() {
        let obs = AudioSessionObserver.shared
        obs.onInterruptionBegan = { [weak self] in
            if let self {
                self.invalidateAudioSessionForInterruption()
                self.applyEffects(self.stateMachine.interruptionBegan())
            }
        }
        obs.onInterruptionEnded = { [weak self] shouldResume in
            if let self { self.applyEffects(self.stateMachine.interruptionEnded(shouldResume: shouldResume)) }
        }
        obs.onHeadphonesUnplugged = { [weak self] in
            if let self { self.applyEffects(self.stateMachine.routeUnplugged()) }
        }
    }
    private func setupPlayerBridge() {
        backend.onTrackActivated = { [weak self] trackId, generation in
            guard let self, generation == self.stateMachine.currentGeneration,
                  trackId == self.stateMachine.currentSong?.id else { return }
            self.logger.info("Engine đã xác nhận bài active: \(trackId), gen: \(generation)")
        }
        backend.onPlaybackStateChange = { [weak self] stateCode, gen, trackId in
            self?.handleBridgeStateChange(stateCode: stateCode, generation: gen, trackId: trackId)
        }
        backend.onPositionUpdate = { [weak self] cur, dur, gen, trackId in
            self?.handleBridgePositionUpdate(current: cur, duration: dur, generation: gen, trackId: trackId)
        }
        backend.onTrackEnded = { [weak self] gen, trackId in
            self?.handleBridgeTrackEnded(generation: gen, trackId: trackId)
        }
        backend.onError = { [weak self] code, gen, trackId in
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

    func startLoadingWatchdog(for generation: Int) {
        loadingWatchdogTask?.cancel()
        loadingWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.stateMachine.currentGeneration == generation,
                  self.stateMachine.playbackState.isBuffering,
                  self.stateMachine.userIntent == .playing else { return }

            self.logger.warning("Playback loading watchdog: Quá thời gian nạp nhạc (12s) cho gen \(generation).")
            self.activationTask?.cancel()
            self.activationTask = nil
            self.pendingEngineLoad = nil
            self.engineOperationRevision += 1
            self.playbackErrorMessage = "Không thể phát bài hát này. Hãy thử lại."
            self.pause()
        }
    }

    func cancelLoadingWatchdog() {
        loadingWatchdogTask?.cancel()
        loadingWatchdogTask = nil
    }
    private func handleBridgeStateChange(stateCode: Int, generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }
        logger.info("Playback state gen=\(generation) code=\(stateCode)")
        let engineState: EnginePlaybackState = (stateCode == 1) ? .playing : ((stateCode == 2) ? .paused : .buffering)
        applyEffects(stateMachine.engineStateChanged(engineState, generation: generation))

        if engineState == .playing {
            cancelLoadingWatchdog()
            playbackErrorMessage = nil
            if !clock.isPlaying { clock.play(from: currentPosition, rate: 1.0) }
            startPositionTracking()
        } else if engineState == .paused || engineState == .buffering {
            clock.pause()
            if stateMachine.userIntent == .playing, stateMachine.interruptionState == .active {
                if !isWatchdogActive { startLoadingWatchdog(for: generation) }
            } else { cancelLoadingWatchdog() }
        }
    }

    private func handleBridgePositionUpdate(
        current: TimeInterval, duration: TimeInterval, generation: Int, trackId: String
    ) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }
        guard current.isFinite, current >= 0 else { return }

        if duration.isFinite, duration > 0 { runtimeDuration = duration }
        let displayedPosition = Self.stableDisplayedPosition(
            previous: currentPosition, candidate: current
        )
        stateMachine.engineTimeUpdated(currentTime: displayedPosition, generation: generation)
        if abs(clock.currentPosition() - current) > 0.5 { clock.seek(to: current) }
        currentPosition = displayedPosition
        if updatesSystemNowPlaying { NowPlayingManager.shared.updateNowPlaying(
            song: currentSong, isPlaying: isPlaying, currentTime: displayedPosition, duration: effectiveDuration
        ) }
    }

    private func handleBridgeTrackEnded(generation: Int, trackId: String) {
        let matches = generation == stateMachine.currentGeneration && trackId == stateMachine.currentSong?.id
        let qSnap = queueManager.snapshot()
        logger.info("""
            Playback end t=\(ProcessInfo.processInfo.systemUptime, privacy: .public) \
            gen=\(generation) curGen=\(self.stateMachine.currentGeneration) \
            match=\(matches) started=\(self.stateMachine.hasStartedForCurrentTrack) \
            pos=\(self.currentPosition, format: .fixed(precision: 2)) \
            repeat=\(qSnap.repeatMode.rawValue, privacy: .public) \
            qIdx=\(qSnap.currentIndex ?? -1) qCount=\(qSnap.items.count) \
            intent=\(String(describing: self.stateMachine.userIntent), privacy: .public)
            """)
        guard matches else { return }
        applyEffects(stateMachine.engineTrackEnded(generation: generation))
    }
    private func handleBridgeError(code: Int, generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration,
              trackId.isEmpty || trackId == stateMachine.currentSong?.id else { return }
        logger.error("""
            Playback error t=\(ProcessInfo.processInfo.systemUptime) code=\(code) \
            gen=\(generation) intent=\(String(describing: self.stateMachine.userIntent))
            """)
        cancelLoadingWatchdog()
        let isUnavailable = code == 100 || code == 101 || code == 150 || code == 152
        let canAdvance = queueManager.remainingCount > 0 || (repeatMode == .all && queueManager.items.count > 1)
        if isUnavailable, canAdvance, stateMachine.userIntent == .playing, repeatMode != .one {
            next()
            return
        }
        playbackErrorMessage = code == -999
            ? "Trình phát đã dừng sau nhiều lần khôi phục. Hãy thử lại." : "Không thể phát bài hát (mã \(code))."
        pause(reason: "engineError")
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
    func startPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.stateMachine.userIntent == .playing else { break }
                if self.isPlaying {
                    self.currentPosition = Self.stableDisplayedPosition(
                        previous: self.currentPosition,
                        candidate: self.clock.currentPosition()
                    )
                }
            }
        }
    }
    private func stopPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = nil
    }
}

/// Giao diện cho backend hỗ trợ đặt lại ngân sách khôi phục sự cố crash WebKit.
@MainActor
public protocol CrashRecoverableBackend: AnyObject {
    func resetCrashRecoveryBudget()
}

extension PlaybackBackend {
    public func resetCrashRecoveryBudget() {
        if let recoverable = self as? any CrashRecoverableBackend {
            recoverable.resetCrashRecoveryBudget()
        } else if let webView = self as? SingletonPlayerWebView {
            webView.crashRetryCount = 0
        }
    }
}
