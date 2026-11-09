import Foundation
import SwiftUI
import OtoCore

/// ViewModel quản lý toàn bộ trạng thái phát nhạc và hàng đợi trên MainActor.
@MainActor
@Observable
public final class PlayerViewModel {
    public var playbackState: PlaybackState = .idle
    public var currentPosition: TimeInterval = 0
    public var isExpanded: Bool = false
    public var showLyrics: Bool = false
    public var showQueue: Bool = false

    public let queueManager: QueueManager
    public let clock: InterpolatedClock

    private var positionTimerTask: Task<Void, Never>?

    public init(
        queueManager: QueueManager = QueueManager(),
        clock: InterpolatedClock = InterpolatedClock()
    ) {
        self.queueManager = queueManager
        self.clock = clock
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
        clock.play(from: 0, rate: 1.0)
        playbackState = .playing(song: song, position: 0)
        currentPosition = 0
        startPositionTracking()
    }

    /// Tiếp tục phát.
    public func resume() {
        guard let song = currentSong else { return }
        clock.play(from: currentPosition, rate: 1.0)
        playbackState = .playing(song: song, position: currentPosition)
        startPositionTracking()
    }

    /// Tạm dừng.
    public func pause() {
        guard let song = currentSong else { return }
        clock.pause()
        currentPosition = clock.currentPosition()
        playbackState = .paused(song: song, position: currentPosition)
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
            play(song: nextSong)
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
            play(song: prevSong)
        } else {
            seek(to: 0)
        }
    }

    /// Nhảy đến vị trí thời gian chỉ định (Seek).
    public func seek(to position: TimeInterval) {
        clock.seek(to: position)
        currentPosition = position
        if let song = currentSong {
            if isPlaying {
                playbackState = .playing(song: song, position: position)
            } else {
                playbackState = .paused(song: song, position: position)
            }
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

    // MARK: - Internal Position Tracking

    private func startPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard let self = self, self.isPlaying else { break }
                let newPos = self.clock.currentPosition()
                self.currentPosition = newPos

                // Kiểm tra khi hết thời lượng bài hát
                if let song = self.currentSong, song.duration > 0, newPos >= song.duration {
                    self.next()
                    break
                }
            }
        }
    }

    private func stopPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = nil
    }
}
