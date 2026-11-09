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

    private let logger = Logger(subsystem: "com.oto.music", category: "PlayerViewModel")
    private var stateMachine = PlaybackStateMachine()
    private var positionTimerTask: Task<Void, Never>?

    public init(
        queueManager: QueueManager = QueueManager(),
        clock: InterpolatedClock = InterpolatedClock()
    ) {
        self.queueManager = queueManager
        self.clock = clock
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

    // MARK: - Side Effects Dispatcher

    private func applyEffects(_ effects: PlaybackEffects) {
        // 1. Kích hoạt AudioSession bất đồng bộ ngoài main thread khi có yêu cầu
        if effects.shouldActivateSession {
            Task {
                do {
                    try await AudioSessionCoordinator.shared.configureAndActivate()
                } catch {
                    self.logger.error("Lỗi kích hoạt AVAudioSession: \(error.localizedDescription)")
                }
            }
        }

        // 2. Nạp bài hát mới vào WebKit engine
        if let payload = effects.shouldStartEngine {
            clock.pause(at: payload.startSeconds)
            SingletonPlayerWebView.shared.loadVideo(
                id: payload.songId,
                startSeconds: payload.startSeconds,
                generation: payload.generation
            )
        }

        // 3. Tiếp tục WebKit engine
        if effects.shouldResumeEngine {
            clock.play(from: stateMachine.currentPosition, rate: 1.0)
            SingletonPlayerWebView.shared.play()
            startPositionTracking()
        }

        // 4. Tạm dừng WebKit engine
        if effects.shouldPauseEngine {
            clock.pause()
            SingletonPlayerWebView.shared.pause()
            stopPositionTracking()
        }

        // 5. Tua WebKit engine
        if let seekTime = effects.shouldSeekEngine {
            clock.seek(to: seekTime)
            SingletonPlayerWebView.shared.seek(to: seekTime)
        }

        // 6. Chuyển bài kế tiếp
        if effects.shouldAdvanceToNextTrack {
            next()
        }

        // 7. Đồng bộ trạng thái ra giao diện người dùng và NowPlaying
        syncPublicState()
    }

    private func syncPublicState() {
        playbackState = stateMachine.playbackState
        currentPosition = stateMachine.currentPosition

        NowPlayingManager.shared.updateNowPlaying(
            song: currentSong,
            isPlaying: isPlaying,
            currentTime: currentPosition
        )
    }

    // MARK: - Observer & Bridge Wireup

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
        SingletonPlayerWebView.shared.onPlaybackStateChange = { [weak self] (stateCode, gen) in
            guard let self else { return }
            let engineState: EnginePlaybackState
            switch stateCode {
            case 1:
                engineState = .playing
            case 2:
                engineState = .paused
            default:
                engineState = .buffering
            }

            let effects = self.stateMachine.engineStateChanged(engineState, generation: gen)
            self.applyEffects(effects)
        }

        SingletonPlayerWebView.shared.onPositionUpdate = { [weak self] (cur, _, gen) in
            guard let self else { return }
            self.stateMachine.engineTimeUpdated(currentTime: cur, generation: gen)
            let clockPos = self.clock.currentPosition()
            if abs(clockPos - cur) > 0.5 {
                self.clock.seek(to: cur)
            }
            self.currentPosition = cur
            NowPlayingManager.shared.updateNowPlaying(
                song: self.currentSong,
                isPlaying: self.isPlaying,
                currentTime: cur
            )
        }

        SingletonPlayerWebView.shared.onTrackEnded = { [weak self] gen in
            guard let self else { return }
            let effects = self.stateMachine.engineTrackEnded(generation: gen)
            self.applyEffects(effects)
        }

        SingletonPlayerWebView.shared.onError = { [weak self] code in
            self?.logger.error("Lỗi playback YouTube Iframe: code \(code)")
            if code == 100 || code == 101 || code == 150 || code == 152 {
                self?.next()
            }
        }
    }

    private func setupNowPlayingCommands() {
        NowPlayingManager.shared.onPlayCommand = { [weak self] in
            Task { @MainActor in
                self?.resume()
            }
        }
        NowPlayingManager.shared.onPauseCommand = { [weak self] in
            Task { @MainActor in
                self?.pause()
            }
        }
        NowPlayingManager.shared.onNextCommand = { [weak self] in
            Task { @MainActor in
                self?.next()
            }
        }
        NowPlayingManager.shared.onPreviousCommand = { [weak self] in
            Task { @MainActor in
                self?.previous()
            }
        }
        NowPlayingManager.shared.onSeekCommand = { [weak self] targetPosition in
            Task { @MainActor in
                self?.seek(to: targetPosition)
            }
        }
    }

    // MARK: - Internal Position Tracking

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
