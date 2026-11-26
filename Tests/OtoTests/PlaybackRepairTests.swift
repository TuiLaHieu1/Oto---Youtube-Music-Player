import Foundation
import Observation
import Testing
import OtoCore
@testable import Oto

actor TestAudioSession: PlaybackAudioSession {
    var events: [String] = []
    func prepareForPlayback() async throws { events.append("activate") }
    func invalidateForInterruption() async { events.append("invalidate") }
}

actor GatedAudioSession: PlaybackAudioSession {
    var requests = 0
    var events: [String] = []
    var pending: [CheckedContinuation<Void, Error>] = []

    func prepareForPlayback() async throws {
        requests += 1
        events.append("activate")
        try await withCheckedThrowingContinuation { pending.append($0) }
    }

    func invalidateForInterruption() async { events.append("invalidate") }

    func waitForRequest(count: Int = 1) async {
        while requests < count { await Task.yield() }
    }

    func finish(failing: Bool = false) {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations {
            if failing { continuation.resume(throwing: URLError(.unknown)) } else { continuation.resume() }
        }
    }
}

actor DeferredCatalog: PlaybackCatalog {
    var request: CheckedContinuation<Album, Error>?
    func fetchAlbumDetail(browseId: String) async throws -> Album {
        try await withCheckedThrowingContinuation { request = $0 }
    }
    func waitForRequest() async {
        while request == nil { await Task.yield() }
    }
    func finish(_ album: Album) { request?.resume(returning: album); request = nil }
    func fetchPlaylistSongs(playlistId: String) async throws -> [Song] { [] }
    func fetchUpNextQueue(videoId: String) async throws -> [Song] { [] }
}

@Suite("Hồi quy playback sau bàn giao Teamwork")
@MainActor
struct PlaybackRepairTests {
    let first = Song(id: "first", title: "First", artist: "Artist", duration: 180)
    let second = Song(id: "second", title: "Second", artist: "Other Artist", duration: 200)

    @Test("Hẹn giờ hết bài chặn chuyển bài và có thể phát lại")
    func sleepTimerStopsAtTrackEnd() async throws {
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
        player.playQueue(songs: [self.first, self.second])
        await player.waitForPendingAudioOperation()
        let load = try #require(backend.loadCalls.last)
        backend.onPlaybackStateChange?(1, load.generation, self.first.id)
        player.stopAfterCurrentTrack()
        backend.onTrackEnded?(load.generation, self.first.id)
        backend.onTrackEnded?(load.generation, self.first.id)

        #expect(player.sleepTimer == nil)
        #expect(player.currentSong?.id == self.first.id)
        #expect(player.stateMachine.userIntent == .paused)
        #expect(backend.loadCalls.count == 1)

        player.resume()
        await player.waitForPendingAudioOperation()
        let replay = try #require(backend.loadCalls.last)
        #expect(replay.generation != load.generation)
        backend.onPlaybackStateChange?(1, replay.generation, self.first.id)
        backend.onTrackEnded?(replay.generation, self.first.id)
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == self.second.id)
    }

    @Test("Lịch sử ghi khi phát và tách dữ liệu theo phiên")
    func recentHistoryIsScopedAndRequiresPlayback() async throws {
        let suite = "oto.tests.history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(
            backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false, historyDefaults: defaults
        )
        player.loadRecentlyPlayed(scopeKey: "first-scope")
        player.play(song: self.first)
        await player.waitForPendingAudioOperation()
        let load = try #require(backend.loadCalls.last)
        #expect(player.recentlyPlayed.isEmpty)
        backend.onPlaybackStateChange?(1, load.generation, self.first.id)
        backend.onPlaybackStateChange?(1, load.generation, self.first.id)
        #expect(player.recentlyPlayed.map(\.id) == [self.first.id])
        player.loadRecentlyPlayed(scopeKey: "second-scope")
        backend.onPlaybackStateChange?(1, load.generation, self.first.id)
        #expect(player.recentlyPlayed.isEmpty)
        player.loadRecentlyPlayed(scopeKey: "first-scope")
        #expect(player.recentlyPlayed.map(\.id) == [self.first.id])
        player.clearForSignOut()
        player.loadRecentlyPlayed(scopeKey: "first-scope")
        #expect(player.recentlyPlayed.isEmpty)
    }

    @Test("Mốc WebKit đến trễ không làm đồng hồ đang phát nhảy lùi")
    func delayedPositionUpdateKeepsDisplayStable() async {
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
        player.play(song: first)
        await player.waitForPendingAudioOperation()
        guard let load = backend.loadCalls.last else {
            Issue.record("Backend chưa nhận lệnh phát")
            return
        }

        backend.onPlaybackStateChange?(1, load.generation, load.id)
        player.seek(to: 10.05)
        backend.onPositionUpdate?(9.95, 180, load.generation, load.id)
        #expect(player.currentPosition >= 10.05)
        player.pause()
        #expect(player.currentPosition >= 10.05)
        backend.onPositionUpdate?(9.95, 180, load.generation, load.id)
        #expect(player.currentPosition >= 10.05)
        player.resume()
        await player.waitForPendingAudioOperation()
        backend.onPlaybackStateChange?(1, load.generation, load.id)

        backend.onPositionUpdate?(11.3, 180, load.generation, load.id)
        #expect(player.currentPosition >= 11.3)
        backend.onPositionUpdate?(7, 180, load.generation, load.id)
        #expect(player.currentPosition >= 7 && player.currentPosition < 7.2)
    }

    @Test("Chờ activation và giữ pause/seek khi activation chưa xong")
    func activationPreservesIntent() async {
        let gate = GatedAudioSession()
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: gate, updatesSystemNowPlaying: false)
        player.play(song: first)
        await gate.waitForRequest()
        #expect(backend.loadCalls.isEmpty)
        player.pause()
        player.seek(to: 35)
        await gate.finish()
        await player.waitForPendingAudioOperation()
        #expect(backend.loadCalls.last?.shouldPlay == false)
        #expect(backend.loadCalls.last?.startSeconds == 35)
        player.clearForSignOut()
    }

    @Test("Activation lỗi không gửi lệnh load")
    func activationFailure() async {
        let gate = GatedAudioSession()
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: gate, updatesSystemNowPlaying: false)
        player.play(song: first)
        await gate.waitForRequest()
        await gate.finish(failing: true)
        await player.waitForPendingAudioOperation()
        #expect(backend.loadCalls.isEmpty)
        #expect(player.playbackErrorMessage != nil)
        player.clearForSignOut()
    }

    @Test("Interruption invalidation hoàn tất trước activation khi resume")
    func interruptionOrdering() async {
        let audio = TestAudioSession()
        let player = PlayerViewModel(
            backend: MockPlaybackBackend(), audioSession: audio, updatesSystemNowPlaying: false
        )
        player.play(song: first)
        await player.waitForPendingAudioOperation()
        player.invalidateAudioSessionForInterruption()
        player.applyEffects(player.stateMachine.interruptionBegan())
        player.applyEffects(player.stateMachine.interruptionEnded(shouldResume: true))
        await player.waitForPendingAudioOperation()
        #expect(await audio.events == ["activate", "invalidate", "activate"])
        player.clearForSignOut()
    }

    @Test("Hai interruption began không invalidate muộn activation mới")
    func duplicateInterruptionOrdering() async {
        let gate = GatedAudioSession()
        let player = PlayerViewModel(backend: MockPlaybackBackend(), audioSession: gate, updatesSystemNowPlaying: false)
        player.play(song: first)
        await gate.waitForRequest()
        player.invalidateAudioSessionForInterruption()
        player.applyEffects(player.stateMachine.interruptionBegan())
        player.invalidateAudioSessionForInterruption()
        player.applyEffects(player.stateMachine.interruptionBegan())
        player.applyEffects(player.stateMachine.interruptionEnded(shouldResume: true))
        await gate.finish()
        await gate.waitForRequest(count: 2)
        await gate.finish()
        await player.waitForPendingAudioOperation()
        #expect(await gate.events == ["activate", "invalidate", "invalidate", "activate"])
        player.clearForSignOut()
    }

    @Test("Vị trí dương chưa chứng minh engine đang phát")
    func positionDoesNotFakePlaying() async {
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
        player.play(song: first)
        await player.waitForPendingAudioOperation()
        backend.onPositionUpdate?(40, 180, 1, first.id)
        #expect(player.isBuffering)
        #expect(!player.isPlaying)
        #expect(player.isWatchdogActive)
        player.clearForSignOut()
    }

    @Test("Repeat One tự phát lại đúng bài, Next thủ công sang bài kế và tắt Repeat One")
    func repeatOneReplaysSameTrackOnlyOnce() async {
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
        player.playQueue(songs: [first, second])
        await player.waitForPendingAudioOperation()
        let firstLoad = backend.loadCalls.last
        #expect(firstLoad?.id == first.id)

        player.toggleRepeat()
        player.toggleRepeat()
        #expect(player.repeatMode == .one)

        backend.onPlaybackStateChange?(1, firstLoad?.generation ?? 1, first.id)
        backend.onTrackEnded?(firstLoad?.generation ?? 1, first.id)
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == first.id)
        #expect(backend.loadCalls.count == 2)
        let replayLoad = backend.loadCalls.last
        #expect(replayLoad?.id == first.id)
        #expect(replayLoad?.generation == (firstLoad?.generation ?? 0) + 1)

        // Ended trùng của lượt trước không được kết thúc lượt vừa nạp lại.
        backend.onTrackEnded?(replayLoad?.generation ?? 0, first.id)
        await player.waitForPendingAudioOperation()
        #expect(backend.loadCalls.count == 2)

        // Người dùng bấm Next vẫn sang bài kế.
        player.next()
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == second.id)
        #expect(backend.loadCalls.last?.id == second.id)
        #expect(player.repeatMode == .off)
        player.clearForSignOut()
    }

    @Test("Vuốt Mini Player sang phải chuyển occurrence trước dù bài đã chạy quá ba giây")
    func miniPlayerSwipePreviousSkipsTrack() async {
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
        player.playQueue(songs: [first, second], startIndex: 1)
        await player.waitForPendingAudioOperation()
        player.seek(to: 20)
        player.swipeToPreviousTrack()
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == first.id)
        #expect(player.queueManager.currentIndex == 0)
        #expect(backend.loadCalls.last?.id == first.id)
        player.clearForSignOut()
    }

    @Test("Repeat Off chuyển sang occurrence tiếp theo ngay sau ended đầu tiên")
    func repeatOffAdvancesAfterFirstEnd() async {
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
        player.playQueue(songs: [first, second])
        await player.waitForPendingAudioOperation()
        let generation = backend.loadCalls.last?.generation ?? 0
        #expect(player.repeatMode == .off)
        backend.onPlaybackStateChange?(1, generation, first.id)
        backend.onTrackEnded?(generation, first.id)
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == second.id)
        #expect(player.queueManager.currentIndex == 1)
        #expect(backend.loadCalls.count == 2)
        player.clearForSignOut()
    }

    @Test("Ended đến trước khi engine xác nhận phát lại bị bỏ qua")
    func endedBeforeReplayStartsIsIgnored() async {
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
        player.playQueue(songs: [first, second])
        await player.waitForPendingAudioOperation()
        let load = backend.loadCalls.last
        backend.onPlaybackStateChange?(1, load?.generation ?? 1, first.id)
        player.toggleRepeat()
        player.toggleRepeat()

        backend.onTrackEnded?(load?.generation ?? 1, first.id)
        await player.waitForPendingAudioOperation()
        #expect(backend.loadCalls.count == 2)
        let replay = backend.loadCalls.last

        // Generation mới chưa playing; ended trễ bị loại bỏ.
        backend.onTrackEnded?(replay?.generation ?? 0, first.id)
        await player.waitForPendingAudioOperation()
        #expect(backend.loadCalls.count == 2)
        player.clearForSignOut()
    }

    @Test("Home giả lập → play → pause/resume → next/previous → seek → Search giả lập")
    func playbackVerticalSlice() async {
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
        player.playQueue(songs: [first, second])
        await player.waitForPendingAudioOperation()
        backend.onPlaybackStateChange?(1, 1, first.id)
        #expect(player.currentSong?.artist == first.artist)
        #expect(player.isPlaying)
        player.pause()
        backend.onPlaybackStateChange?(2, 1, first.id)
        player.resume()
        await player.waitForPendingAudioOperation()
        #expect(backend.playCount == 1)
        player.next()
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == second.id)
        backend.onPlaybackStateChange?(1, 2, second.id)
        player.previous()
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == first.id)
        player.seek(to: 50)
        #expect(backend.seekCalls.last == 50)
        player.play(song: second)
        await player.waitForPendingAudioOperation()
        backend.onPlaybackStateChange?(1, 1, first.id)
        #expect(player.currentSong?.id == second.id)
        player.isExpanded = true
        player.isExpanded = false
        #expect(backend.resetCount == 0)
        player.clearForSignOut()
    }

    @Test("Response album cũ không giành lại bài mới")
    func staleAlbumCannotReplaceSong() async {
        let catalog = DeferredCatalog()
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(
            backend: backend, audioSession: TestAudioSession(), catalog: catalog, updatesSystemNowPlaying: false
        )
        player.playAlbum(browseId: "MPRE_album")
        await catalog.waitForRequest()
        player.play(song: second)
        await player.waitForPendingAudioOperation()
        await catalog.finish(Album(id: "MPRE_album", title: "Album", artist: "Artist", songs: [first]))
        for _ in 0..<10 { await Task.yield() }
        #expect(player.currentSong?.id == second.id)
        #expect(backend.loadCalls.count == 1)
        player.clearForSignOut()
    }
}

actor DeferredRadioCatalog: PlaybackCatalog {
    private var request: CheckedContinuation<[Song], Never>?
    private var result: [Song]?

    func fetchAlbumDetail(browseId: String) async throws -> Album { throw URLError(.unsupportedURL) }
    func fetchPlaylistSongs(playlistId: String) async throws -> [Song] { [] }
    func fetchUpNextQueue(videoId: String) async throws -> [Song] {
        if let result { return result }
        return await withCheckedContinuation { request = $0 }
    }

    func finish(with songs: [Song]) {
        result = songs
        request?.resume(returning: songs)
        request = nil
    }
}

@MainActor
extension PlaybackRepairTests {
    @Test("Radio nghệ sĩ chỉ nối bài khi người nghe còn muốn phát", arguments: [false, true])
    func artistRadioWaitsAtQueueEnd(pausesWhileWaiting: Bool) async throws {
        let catalog = DeferredRadioCatalog()
        let backend = MockPlaybackBackend()
        let player = PlayerViewModel(
            backend: backend, audioSession: TestAudioSession(), catalog: catalog, updatesSystemNowPlaying: false
        )
        player.playQueue(songs: [first], continuesWithRadio: true)
        let radio = try #require(player.radioLoadTask)
        await player.waitForPendingAudioOperation()
        let load = try #require(backend.loadCalls.last)

        backend.onPlaybackStateChange?(1, load.generation, load.id)
        backend.onTrackEnded?(load.generation, load.id)
        #expect(player.artistRadioEndGeneration == load.generation)
        #expect(backend.loadCalls.map(\.id) == [first.id])

        if pausesWhileWaiting { player.pause() }
        await catalog.finish(with: [first, second, second])
        await radio.value
        await player.waitForPendingAudioOperation()

        #expect(player.artistRadioEndGeneration == nil)
        let expected = pausesWhileWaiting ? [first.id] : [first.id, second.id]
        #expect(backend.loadCalls.map(\.id) == expected)
        #expect(player.queueManager.items.map(\.song.id) == expected)
        player.clearForSignOut()
    }
}

@Test("Thay đổi Shuffle và Repeat phát thông báo cho giao diện")
@MainActor
func queueControlsNotifyObservation() async {
    let queue = QueueManager()
    queue.setQueue(songs: [
        Song(id: "first", title: "First", artist: "Artist"),
        Song(id: "second", title: "Second", artist: "Artist")
    ])
    let vm = PlayerViewModel(
        queueManager: queue, backend: MockPlaybackBackend(),
        audioSession: TestAudioSession(), updatesSystemNowPlaying: false
    )
    await confirmation("Shuffle đổi trạng thái quan sát được") { changed in
        withObservationTracking {
            #expect(!vm.isShuffleEnabled)
        } onChange: {
            changed()
        }
        vm.toggleShuffle()
        await Task { @MainActor in }.value
    }
    #expect(vm.isShuffleEnabled)
    await confirmation("Repeat đổi trạng thái quan sát được") { changed in
        withObservationTracking {
            #expect(vm.repeatMode == .off)
        } onChange: {
            changed()
        }
        vm.toggleRepeat()
        await Task { @MainActor in }.value
    }
    #expect(vm.repeatMode == .all)
    vm.toggleRepeat()
    #expect(vm.repeatMode == .one)
    vm.toggleRepeat()
    #expect(vm.repeatMode == .off)
}

#if DEBUG && OTO_STREAM_PROBE
struct ProbeAudioDurationTests {
    @Test("Dừng tại thời lượng nguồn khi timeline audio gần gấp đôi")
    @MainActor
    func doubledTimeline() {
        #expect(LocalMusicPlaybackRouter.probeAudioEndTime(itemDuration: 442.35, sourceDuration: 221) == 221)
    }

    @Test("Giữ timeline bình thường hoặc khi thiếu thời lượng nguồn")
    @MainActor
    func unchangedTimeline() {
        #expect(LocalMusicPlaybackRouter.probeAudioEndTime(itemDuration: 221.35, sourceDuration: 221) == nil)
        #expect(LocalMusicPlaybackRouter.probeAudioEndTime(itemDuration: 260, sourceDuration: 221) == nil)
        #expect(LocalMusicPlaybackRouter.probeAudioEndTime(itemDuration: 442.35, sourceDuration: nil) == nil)
        #expect(LocalMusicPlaybackRouter.probeAudioEndTime(itemDuration: .nan, sourceDuration: 221) == nil)
    }
}
#endif
