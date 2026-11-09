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

    private let logger = Logger(subsystem: "com.oto.music", category: "PlayerViewModel")
    private var playbackGeneration: Int = 0
    private var hasAdvancedCurrentTrack: Bool = false
    private var positionTimerTask: Task<Void, Never>?

    public init(
        queueManager: QueueManager = QueueManager(),
        clock: InterpolatedClock = InterpolatedClock()
    ) {
        self.queueManager = queueManager
        self.clock = clock
        setupPlayerBridge()
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

    // MARK: - Actions

    /// Bắt đầu phát một bài hát cụ thể và cập nhật hàng đợi.
    public func play(song: Song) {
        queueManager.setQueue(songs: [song])
        startPlayback(song: song)
    }

    /// Bắt đầu engine cho bài mà QueueManager đã chọn, không làm mất phần còn lại của hàng đợi.
    private func startPlayback(song: Song) {
        playbackGeneration += 1
        hasAdvancedCurrentTrack = false
        let gen = playbackGeneration

        AudioSessionManager.shared.activateSession()
        clock.pause(at: 0)
        playbackState = .playing(song: song, position: 0)
        currentPosition = 0
        SingletonPlayerWebView.shared.loadVideo(id: song.id, startSeconds: 0, generation: gen)
        NowPlayingManager.shared.updateNowPlaying(song: song, isPlaying: true, currentTime: 0)
    }

    /// Khởi tạo hàng đợi mới từ danh sách bài hát và bắt đầu phát từ vị trí chỉ định.
    public func playQueue(songs: [Song], startIndex: Int = 0) {
        guard !songs.isEmpty else { return }
        queueManager.setQueue(songs: songs, startIndex: startIndex)
        if let targetSong = queueManager.currentSong {
            startPlayback(song: targetSong)
        }
    }

    /// Phát bài hát tại một vị trí cụ thể trong hàng đợi và cập nhật currentIndex.
    public func playQueueItem(at index: Int) {
        if let targetSong = queueManager.skipToIndex(index) {
            startPlayback(song: targetSong)
        }
    }

    /// Tiếp tục phát.
    public func resume() {
        guard let song = currentSong else { return }
        AudioSessionManager.shared.activateSession()
        clock.play(from: currentPosition, rate: 1.0)
        playbackState = .playing(song: song, position: currentPosition)
        SingletonPlayerWebView.shared.play()
        NowPlayingManager.shared.updateNowPlaying(song: song, isPlaying: true, currentTime: currentPosition)
        startPositionTracking()
    }

    /// Tạm dừng.
    public func pause() {
        guard let song = currentSong else { return }
        clock.pause()
        currentPosition = clock.currentPosition()
        playbackState = .paused(song: song, position: currentPosition)
        SingletonPlayerWebView.shared.pause()
        NowPlayingManager.shared.updateNowPlaying(song: song, isPlaying: false, currentTime: currentPosition)
        stopPositionTracking()
    }

    /// Đổi trạng thái Play / Pause.
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Chuyển bài tiếp theo trong queue.
    public func next() {
        if let nextSong = queueManager.next() {
            startPlayback(song: nextSong)
        } else {
            pause()
            seek(to: 0)
        }
    }

    /// Quay lại bài trước.
    public func previous() {
        if currentPosition > 3.0 {
            seek(to: 0)
        } else if let prevSong = queueManager.previous() {
            startPlayback(song: prevSong)
        } else {
            seek(to: 0)
        }
    }

    /// Nhảy đến vị trí thời gian chỉ định (Seek).
    public func seek(to position: TimeInterval) {
        clock.seek(to: position)
        currentPosition = position
        SingletonPlayerWebView.shared.seek(to: position)
        if let song = currentSong {
            if isPlaying {
                playbackState = .playing(song: song, position: position)
            } else {
                playbackState = .paused(song: song, position: position)
            }
            NowPlayingManager.shared.updateNowPlaying(song: song, isPlaying: isPlaying, currentTime: position)
        }
    }

    /// Bật/tắt trộn bài.
    public func toggleShuffle() {
        queueManager.toggleShuffle()
    }

    /// Đổi chế độ lặp.
    public func toggleRepeat() {
        queueManager.toggleRepeat()
    }

    // MARK: - Internal Player Bridge & NowPlaying Callbacks

    private func setupPlayerBridge() {
        SingletonPlayerWebView.shared.onPositionUpdate = { [weak self] cur, _ in
            guard let self, self.isPlaying else { return }
            let clockPos = self.clock.currentPosition()
            if abs(clockPos - cur) > 0.5 {
                self.clock.seek(to: cur)
            }
            self.currentPosition = cur
            NowPlayingManager.shared.updateNowPlaying(
                song: self.currentSong,
                isPlaying: true,
                currentTime: cur
            )
        }

        SingletonPlayerWebView.shared.onTrackEnded = { [weak self] in
            self?.advanceOnce()
        }

        SingletonPlayerWebView.shared.onPlaybackStateChange = { [weak self] state in
            guard let self else { return }
            if state == 1 { // YT.PlayerState.PLAYING
                if !self.isPlaying, let song = self.currentSong {
                    self.clock.play(from: self.currentPosition, rate: 1.0)
                    self.playbackState = .playing(song: song, position: self.currentPosition)
                    self.startPositionTracking()
                }
            } else if state == 2 { // YT.PlayerState.PAUSED
                if self.isPlaying, let song = self.currentSong {
                    self.clock.pause()
                    self.playbackState = .paused(song: song, position: self.currentPosition)
                    self.stopPositionTracking()
                }
            }
        }

        SingletonPlayerWebView.shared.onError = { [weak self] code in
            self?.logger.error("Lỗi playback YouTube Iframe: code \(code)")
            if code == 100 || code == 101 || code == 150 || code == 152 {
                self?.advanceOnce()
            }
        }
    }

    /// Chuyển bài kế tiếp duy nhất một lần khi bài hiện tại kết thúc, ngăn chặn nhảy bài kép.
    private func advanceOnce() {
        guard !hasAdvancedCurrentTrack else { return }
        hasAdvancedCurrentTrack = true
        next()
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
                // Timer chỉ cập nhật tiến trình hiển thị; việc chuyển bài do onTrackEnded đảm nhiệm.
            }
        }
    }

    private func stopPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = nil
    }
}
