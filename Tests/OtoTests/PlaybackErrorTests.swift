import Testing
import Foundation
import OtoCore
@testable import Oto

private var recoveryBudgetResetKey: UInt8 = 0

extension MockPlaybackBackend: CrashRecoverableBackend {
    var recoveryBudgetResetCount: Int {
        get {
            (objc_getAssociatedObject(self, &recoveryBudgetResetKey) as? Int) ?? 0
        }
        set {
            objc_setAssociatedObject(self, &recoveryBudgetResetKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func resetCrashRecoveryBudget() {
        recoveryBudgetResetCount += 1
    }
}

@MainActor
func makeTestPlayer(backend: MockPlaybackBackend) -> PlayerViewModel {
    PlayerViewModel(backend: backend)
}

@MainActor
func waitForAudioSessionOperation(_ player: PlayerViewModel) async {
    try? await Task.sleep(nanoseconds: 10_000_000)
}

@Suite("Player playback regressions")
struct PlaybackErrorTests {
    @Test("Repeat One tự lặp không gọi nạp radio lặp lại, nhưng Next thủ công vẫn được nạp")
    func repeatOneOnlySuppressesAutomaticRadioExpansion() {
        #expect(!PlayerViewModel.shouldLoadRadioQueue(
            remainingCount: 1,
            repeatMode: .one,
            userInitiated: false
        ))
        #expect(PlayerViewModel.shouldLoadRadioQueue(
            remainingCount: 1,
            repeatMode: .one,
            userInitiated: true
        ))
        #expect(PlayerViewModel.shouldLoadRadioQueue(
            remainingCount: 1,
            repeatMode: .off,
            userInitiated: false
        ))
        #expect(!PlayerViewModel.shouldLoadRadioQueue(
            remainingCount: 3,
            repeatMode: .off,
            userInitiated: false
        ))
    }

    @Test("Repeat One: nút Next chuyển bài, bài kết thúc thì tự lặp bài hiện tại")
    @MainActor
    func repeatOneSeparatesManualNextFromAutomaticAdvance() async {
        let first = Song(id: "repeat_first", title: "First", artist: "Artist", duration: 100)
        let second = Song(id: "repeat_second", title: "Second", artist: "Artist", duration: 100)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)
        player.playQueue(songs: [first, second])
        await waitForAudioSessionOperation(player)
        player.toggleRepeat()
        player.toggleRepeat()

        player.next()
        await waitForAudioSessionOperation(player)
        #expect(player.currentSong?.id == second.id)
        #expect(backend.loadCalls.last?.id == second.id)
        // Sang bài khác bằng tay thì Repeat One tự tắt; bật lại để kiểm tra tự lặp.
        #expect(player.repeatMode == .off)
        player.toggleRepeat()
        player.toggleRepeat()
        #expect(player.repeatMode == .one)

        backend.onTrackEnded?(2, second.id)
        await waitForAudioSessionOperation(player)
        #expect(player.currentSong?.id == second.id)
        #expect(backend.loadCalls.last?.id == second.id)
        #expect(backend.loadCalls.last?.generation == 3)
    }

    @Test("Bài không khả dụng không tự phát bài khác nếu người dùng đã pause")
    @MainActor
    func unavailableTrackDoesNotAdvanceAfterUserPaused() async {
        let first = Song(id: "paused_unavailable", title: "Unavailable", artist: "Artist", duration: 100)
        let second = Song(id: "paused_next", title: "Next", artist: "Artist", duration: 100)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)
        player.playQueue(songs: [first, second])
        await waitForAudioSessionOperation(player)
        player.pause()

        backend.onError?(100, 1, first.id)

        #expect(player.currentSong?.id == first.id)
        #expect(!player.isPlaying)
        #expect(player.playbackErrorMessage != nil)
        #expect(backend.loadCalls.count == 1)
    }

    @Test("Bridge error ends buffering and lets the user retry the current track")
    @MainActor
    func retryCurrentTrackAfterBackendError() async {
        let song = Song(id: "test_track_1", title: "Test Song", artist: "Artist", duration: 180)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)
        player.play(song: song)
        await waitForAudioSessionOperation(player)

        backend.onError?(-999, 1, song.id)

        #expect(player.playbackErrorMessage != nil)
        #expect(!player.isBuffering)

        player.retryCurrentTrack()
        await waitForAudioSessionOperation(player)

        #expect(player.playbackErrorMessage == nil)
        #expect(backend.loadCalls.count == 2)
        #expect(backend.loadCalls.last?.id == song.id)
        #expect(backend.recoveryBudgetResetCount == 1)
    }

    @Test("Retry giữ nguyên thứ tự queue và trạng thái shuffle")
    @MainActor
    func retryPreservesQueueState() async {
        let songs = (1...4).map { index in
            Song(id: "retry_track_\(index)", title: "Song \(index)", artist: "Artist", duration: 180)
        }
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)
        player.playQueue(songs: songs)
        await waitForAudioSessionOperation(player)
        player.toggleShuffle()

        let queueBeforeRetry = player.queueItems.map(\.id)
        let currentSong = player.currentSong
        guard let currentSong else {
            #expect(Bool(false))
            return
        }
        backend.onError?(-999, 1, currentSong.id)

        player.retryCurrentTrack()
        await waitForAudioSessionOperation(player)

        #expect(player.queueItems.map(\.id) == queueBeforeRetry)
        #expect(player.currentSong?.id == currentSong.id)
        #expect(player.isShuffleEnabled)
    }

    @Test("PlayerBridgeScript preserves the user's YouTube Music volume")
    func playerBridgeScriptPreservesUserVolume() {
        let script = PlayerBridgeScript.source

        #expect(!script.contains("setVolume(100)"))
        #expect(!script.contains("volume = 1.0"))
        #expect(script.contains("oto-volume-migration-v1"))
        #expect(script.contains("localStorage.removeItem('yt-player-volume')"))
        #expect(script.contains("window.__otoUserPaused = true;"))
    }

    @Test("Lệnh pause và seek trong lúc tải được giữ trong pending playback")
    @MainActor
    func pendingPlaybackKeepsLatestUserIntentAndPosition() {
        let pending = SingletonPlayerWebView.PendingPlayback(
            id: "pending_track",
            startSeconds: 12,
            generation: 4,
            shouldPlay: true
        )

        let paused = pending.setting(shouldPlay: false).seeking(to: 48)

        #expect(paused.id == "pending_track")
        #expect(paused.generation == 4)
        #expect(paused.startSeconds == 48)
        #expect(!paused.shouldPlay)
    }
}

// MARK: - Backend Resilience & Watchdog Tests

extension PlaybackErrorTests {
    @Test("Playback backend bỏ qua thời gian không hợp lệ")
    @MainActor
    func ignoresInvalidBackendTimeUpdates() async {
        let song = Song(id: "time_track", title: "Time", artist: "Artist", duration: 180)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)
        player.play(song: song)
        await waitForAudioSessionOperation(player)

        backend.onPositionUpdate?(-1, 190, 1, song.id)
        #expect(player.currentPosition == 0)
        #expect(player.effectiveDuration == song.duration)

        backend.onPositionUpdate?(25, 190, 1, song.id)
        #expect(player.currentPosition == 25)
        #expect(player.effectiveDuration == 190)

        backend.onPositionUpdate?(Double.infinity, Double.infinity, 1, song.id)
        #expect(player.currentPosition == 25)
        #expect(player.effectiveDuration == 190)
    }

    @Test("Tự phục hồi: timeUpdate với currentTime > 0 trong lúc buffering chuyển engineState sang playing")
    @MainActor
    func timeUpdateWhileBufferingTransitionsEngineToPlaying() async {
        let song = Song(id: "self_heal_1", title: "Self Heal", artist: "Artist", duration: 180)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)

        player.play(song: song)
        await waitForAudioSessionOperation(player)

        #expect(player.isBuffering)
        #expect(!player.isPlaying)

        // WebKit bridge phát tín hiệu tiến trình thời gian thực (> 0s)
        backend.onPositionUpdate?(1.25, 180, 1, song.id)

        #expect(!player.isBuffering)
        #expect(player.isPlaying)
        #expect(player.currentPosition == 1.25)
        #expect(player.playbackErrorMessage == nil)
    }

    @Test("Lỗi nạp bài kết thúc trạng thái buffering bằng thông báo lỗi retryable")
    @MainActor
    func loadingErrorTerminatesBufferingWithRetryableError() async {
        let song = Song(id: "error_track_1", title: "Error Track", artist: "Artist", duration: 200)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)

        player.play(song: song)
        await waitForAudioSessionOperation(player)

        #expect(player.isBuffering)
        #expect(player.playbackErrorMessage == nil)

        // WebKit hoặc navigation delegate báo lỗi nạp
        backend.onError?(-1009, 1, song.id)

        #expect(!player.isBuffering)
        #expect(!player.isPlaying)
        #expect(player.playbackErrorMessage != nil)
        #expect(player.playbackErrorMessage?.contains("Không thể phát") == true)
    }

    @Test("Callback generation cũ không ảnh hưởng bài mới")
    @MainActor
    func staleGenerationCallbackDoesNotAffectNewSong() async {
        let first = Song(id: "first_song", title: "First", artist: "Artist", duration: 180)
        let second = Song(id: "second_song", title: "Second", artist: "Artist", duration: 180)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)

        player.play(song: first)
        await waitForAudioSessionOperation(player)
        #expect(player.currentSong?.id == first.id)

        player.play(song: second)
        await waitForAudioSessionOperation(player)
        #expect(player.currentSong?.id == second.id)

        // Giả lập callback lỗi trễ từ generation 1 của bài cũ
        backend.onError?(-999, 1, first.id)

        // Không được làm gián đoạn bài hát mới đang ở generation 2
        #expect(player.currentSong?.id == second.id)
        #expect(player.playbackErrorMessage == nil)
        #expect(player.isBuffering)
    }

    @Test("Resume khi đang buffering tái kích hoạt watchdog nạp bài")
    @MainActor
    func resumeWhileBufferingRearmsLoadingWatchdog() async {
        let song = Song(id: "buffering_watchdog", title: "Buffering Watchdog", artist: "Artist", duration: 180)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)

        player.play(song: song)
        await waitForAudioSessionOperation(player)

        #expect(player.isBuffering)
        #expect(player.isWatchdogActive)

        // Người dùng tạm dừng lúc đang buffering -> watchdog bị hủy
        player.pause()
        await waitForAudioSessionOperation(player)

        #expect(!player.isWatchdogActive)
        #expect(player.isBuffering)

        // Người dùng tiếp tục phát -> watchdog được tái kích hoạt vì vẫn đang buffering
        player.resume()
        await waitForAudioSessionOperation(player)

        #expect(player.isBuffering)
        #expect(player.isWatchdogActive)

        // Khi engine chuyển sang playing, watchdog tắt hẳn
        backend.onPlaybackStateChange?(1, 1, song.id)
        await waitForAudioSessionOperation(player)

        #expect(player.isPlaying)
        #expect(!player.isWatchdogActive)

        // Pause và resume lúc playing không kích hoạt watchdog nạp
        player.pause()
        await waitForAudioSessionOperation(player)
        player.resume()
        await waitForAudioSessionOperation(player)

        #expect(!player.isWatchdogActive)
    }

    @Test("Cập nhật vị trí với duration vô hạn không làm hỏng effectiveDuration")
    @MainActor
    func positionUpdateWithInfiniteDurationDoesNotCorruptEffectiveDuration() async {
        let song = Song(id: "infinite_duration_song", title: "Live Stream", artist: "Artist", duration: 180)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)

        player.play(song: song)
        await waitForAudioSessionOperation(player)

        // WebKit gửi duration = Double.infinity (luồng live hoặc chưa xác định)
        backend.onPositionUpdate?(15.0, Double.infinity, 1, song.id)
        await waitForAudioSessionOperation(player)

        #expect(player.runtimeDuration == nil)
        #expect(player.effectiveDuration == 180)
        #expect(player.effectiveDuration.isFinite)

        // Gửi duration hợp lệ
        backend.onPositionUpdate?(20.0, 240.0, 1, song.id)
        await waitForAudioSessionOperation(player)

        #expect(player.runtimeDuration == 240.0)
        #expect(player.effectiveDuration == 240.0)
    }

    @Test("Lỗi từ WebKit với trackId không khớp bài hiện tại bị bỏ qua")
    @MainActor
    func errorWithMismatchedTrackIdIsIgnored() async {
        let song = Song(id: "current_song", title: "Current Song", artist: "Artist", duration: 180)
        let backend = MockPlaybackBackend()
        let player = makeTestPlayer(backend: backend)

        player.play(song: song)
        await waitForAudioSessionOperation(player)

        // Gửi lỗi cùng generation nhưng trackId khác
        backend.onError?(-999, 1, "different_song_id")
        await waitForAudioSessionOperation(player)

        #expect(player.playbackErrorMessage == nil)
        #expect(player.isBuffering)
        #expect(player.currentSong?.id == song.id)
    }
}
