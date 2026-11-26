import Foundation
import SwiftUI
import OtoCore
import os

/// ViewModel quản lý toàn bộ trạng thái phát nhạc và hàng đợi trên MainActor.
@MainActor
@Observable
public final class PlayerViewModel {
    enum SleepTimer: Equatable {
        case minutes(Int, deadline: ContinuousClock.Instant)
        case endOfTrack(generation: Int)
    }

    private(set) var sleepTimer: SleepTimer?
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?
    private(set) var recentlyPlayed: [Song] = []
    @ObservationIgnored private let historyDefaults: UserDefaults
    @ObservationIgnored private var historyKey: String?
    @ObservationIgnored private var recordedGeneration: Int?
    public var playbackState: PlaybackState = .idle
    public var currentPosition: TimeInterval = 0
    public var isExpanded: Bool = false
    public var showLyrics: Bool = false
    public var showQueue: Bool = false
    public var showAuth: Bool = false
    public var playbackErrorMessage: String?
    var playbackSourceTitle: String?
    var confirmedVideoSelectionID: String?
    var playbackResumeStorageKey: String?
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
    var radioLoadTask: Task<Void, Never>?
    var playlistLoadTask: Task<Void, Never>?
    var albumLoadTask: Task<Void, Never>?

    public init(
        queueManager: QueueManager = QueueManager(),
        clock: InterpolatedClock = InterpolatedClock(),
        backend: (any PlaybackBackend)? = nil,
        audioSession: any PlaybackAudioSession = AudioSessionCoordinator.shared,
        catalog: any PlaybackCatalog = YTMusicClient.shared,
        updatesSystemNowPlaying: Bool = true,
        historyDefaults: UserDefaults = .standard
    ) {
        self.queueManager = queueManager
        self.clock = clock
        #if DEBUG && OTO_STREAM_PROBE
        // Bản khảo sát không dùng WebKit để phát: mọi bài YouTube Music đi qua AVPlayer với URL từ yt-dlp.
        self.backend = backend ?? LocalMusicPlaybackRouter(web: NoopPlaybackBackend())
        #else
        self.backend = backend ?? LocalMusicPlaybackRouter(web: SingletonPlayerWebView.shared)
        #endif
        self.audioSession = audioSession
        self.catalog = catalog
        self.updatesSystemNowPlaying = updatesSystemNowPlaying
        self.historyDefaults = historyDefaults
        let previousQueueObserver = queueManager.onQueueChanged
        queueManager.onQueueChanged = { [weak self] in
            previousQueueObserver?()
            Task { @MainActor [weak self] in
                self?.queueRevision &+= 1
            }
        }
        (self.backend as? LocalMusicPlaybackRouter)?.requiresFrequentProgress = { [weak self] in
            self?.isExpanded == true
        }
        setupPlayerBridge()
        setupAudioSessionObserver()
        if updatesSystemNowPlaying { setupNowPlayingCommands() }
        #if DEBUG && OTO_STREAM_PROBE
        if let router = self.backend as? LocalMusicPlaybackRouter {
            router.upcomingTrackIDs = { [queueManager] in
                let snapshot = queueManager.snapshot()
                guard let index = snapshot.currentIndex else { return [] }
                return snapshot.items.dropFirst(index + 1).prefix(2).map(\.song.id)
            }
        }
        #endif
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
        self.cancelSleepTimer()
        if let key = self.historyKey { self.historyDefaults.removeObject(forKey: key) }
        self.historyKey = nil
        self.recordedGeneration = nil
        self.recentlyPlayed = []
        activationTask?.cancel()
        activationTask = nil
        pendingEngineLoad = nil
        engineOperationRevision += 1
        cancelLoadingWatchdog()
        playbackErrorMessage = nil
        cancelCatalogSelection()
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
    func replaceSavedLocalSong(_ song: Song) {
        self.updateSavedLocalSong(id: song.id, replacement: song)
    }

    func removeSavedLocalSong(id: String) {
        self.updateSavedLocalSong(id: id, replacement: nil)
    }

    private func updateSavedLocalSong(id: String, replacement: Song?) {
        let update: ([Song]) -> [Song] = { songs in
            songs.compactMap { $0.id == id ? replacement : $0 }
        }
        self.recentlyPlayed = update(self.recentlyPlayed)
        self.saveRecentlyPlayed()
    }

    func startSleepTimer(minutes: Int) {
        self.cancelSleepTimer()
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(minutes * 60)
        self.sleepTimer = .minutes(minutes, deadline: deadline)
        self.sleepTimerTask = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            guard let self, self.sleepTimer == .minutes(minutes, deadline: deadline) else { return }
            self.cancelSleepTimer()
            self.pause(reason: "sleepTimer")
        }
    }

    func stopAfterCurrentTrack() {
        guard self.stateMachine.currentSong != nil else { return }
        self.cancelSleepTimer()
        self.sleepTimer = .endOfTrack(generation: self.stateMachine.currentGeneration)
    }

    func cancelSleepTimer() {
        self.sleepTimerTask?.cancel()
        self.sleepTimerTask = nil
        self.sleepTimer = nil
    }

    func loadRecentlyPlayed(scopeKey: String) {
        let key = "oto.history.v1." + scopeKey
        guard self.historyKey != key else { return }
        let isFirstScope = self.historyKey == nil
        self.historyKey = key
        self.recordedGeneration = isFirstScope ? nil : self.stateMachine.currentGeneration
        self.recentlyPlayed = self.historyDefaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([Song].self, from: $0)
        }.map { Array($0.prefix(30)) } ?? []
        if isFirstScope, self.stateMachine.engineState == .playing, self.stateMachine.userIntent == .playing {
            self.recordRecentlyPlayed(generation: self.stateMachine.currentGeneration)
        }
    }

    private func recordRecentlyPlayed(generation: Int) {
        guard self.historyKey != nil, self.recordedGeneration != generation,
              let song = self.stateMachine.currentSong else { return }
        self.recordedGeneration = generation
        self.recentlyPlayed = [song] + Array(self.recentlyPlayed.lazy.filter { $0.id != song.id }.prefix(29))
        self.saveRecentlyPlayed()
    }

    private func saveRecentlyPlayed() {
        if let key = self.historyKey, let data = try? JSONEncoder().encode(self.recentlyPlayed) {
            self.historyDefaults.set(data, forKey: key)
        }
    }

    func applyEffects(_ effects: PlaybackEffects) {
        if let payload = effects.shouldStartEngine {
            if case .endOfTrack(let generation) = self.sleepTimer, generation != payload.generation {
                self.cancelSleepTimer()
            }
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
            clock.pause(at: stateMachine.currentPosition)
            backend.pause()
        }
        if let seekTime = effects.shouldSeekEngine {
            clock.pause(at: seekTime)
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
            #if DEBUG && OTO_STREAM_PROBE
            StreamProbeLog.write("StreamProbe vm onInterruptionBegan t=\(ProcessInfo.processInfo.systemUptime)")
            #endif
            if let self {
                self.invalidateAudioSessionForInterruption()
                self.applyEffects(self.stateMachine.interruptionBegan())
            }
        }
        obs.onInterruptionEnded = { [weak self] shouldResume in
            if let self { self.applyEffects(self.stateMachine.interruptionEnded(shouldResume: shouldResume)) }
        }
        obs.onHeadphonesUnplugged = { [weak self] in
            #if DEBUG && OTO_STREAM_PROBE
            StreamProbeLog.write("StreamProbe vm onHeadphonesUnplugged t=\(ProcessInfo.processInfo.systemUptime)")
            #endif
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
            #if DEBUG && OTO_STREAM_PROBE
            // Khảo sát: lần đầu chạy yt-dlp có thể mất 10–20 giây; WebKit dự phòng cũng cần thời gian nạp.
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            #else
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            #endif
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

        if engineState == .playing, stateMachine.userIntent == .playing {
            self.recordRecentlyPlayed(generation: generation)
            cancelLoadingWatchdog()
            playbackErrorMessage = nil
        } else if engineState == .paused || engineState == .buffering {
            clock.pause(at: stateMachine.currentPosition)
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

        if duration.isFinite, duration > 0, runtimeDuration != duration { runtimeDuration = duration }
        // UI lấy vị trí từ media để không chạy đồng hồ khi engine báo playing nhưng đang đứng.
        let mediaPosition = Self.stableDisplayedPosition(previous: stateMachine.currentPosition, candidate: current)
        stateMachine.engineTimeUpdated(currentTime: mediaPosition, generation: generation)
        clock.pause(at: mediaPosition)
        currentPosition = mediaPosition
        if updatesSystemNowPlaying { NowPlayingManager.shared.updateNowPlaying(
            song: currentSong, isPlaying: isPlaying, currentTime: mediaPosition, duration: effectiveDuration
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
        let effects = self.stateMachine.engineTrackEnded(generation: generation)
        if effects.shouldAdvanceToNextTrack, self.sleepTimer == .endOfTrack(generation: generation),
           let song = self.stateMachine.currentSong {
            self.cancelSleepTimer()
            self.pendingEngineLoad = self.stateMachine.restorePaused(song: song, position: 0)
            self.clock.pause(at: 0)
            self.pause(reason: "sleepTimer")
            return
        }
        self.applyEffects(effects)
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
        mgr.onPauseCommand = { [weak self] in Task { @MainActor in self?.pause(reason: "remotePause") } }
        mgr.onTogglePlayPauseCommand = { [weak self] in Task { @MainActor in self?.togglePlayPause() } }
        mgr.onNextCommand = { [weak self] in Task { @MainActor in self?.next() } }
        mgr.onPreviousCommand = { [weak self] in Task { @MainActor in self?.previous() } }
        mgr.onSeekCommand = { [weak self] pos in Task { @MainActor in self?.seek(to: pos) } }
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
