import Foundation
import Testing
import OtoCore
@testable import Oto

@Suite("Video không phát được: báo rõ và chuyển bài")
@MainActor
struct PlaybackUnavailableTests {
    let first = Song(id: "unavail_first", title: "First", artist: "Artist", duration: 180)
    let second = Song(id: "unavail_second", title: "Second", artist: "Artist", duration: 200)

    private func makePlayer(_ backend: MockPlaybackBackend) -> PlayerViewModel {
        PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
    }

    @Test("Engine báo playing chưa làm đồng hồ chạy nếu vị trí media vẫn đứng")
    func clockFollowsOnlyMediaPosition() async throws {
        let backend = MockPlaybackBackend()
        let player = self.makePlayer(backend)
        defer { player.clearForSignOut() }
        player.play(song: self.first)
        await player.waitForPendingAudioOperation()
        let load = try #require(backend.loadCalls.last)

        backend.onPlaybackStateChange?(1, load.generation, load.id)
        backend.onPositionUpdate?(0, 180, load.generation, load.id)
        try await Task.sleep(for: .milliseconds(250))
        #expect(player.currentPosition == 0)
        #expect(player.clock.currentPosition() == 0)

        backend.onPositionUpdate?(0.25, 180, load.generation, load.id)
        try await Task.sleep(for: .milliseconds(250))
        #expect(player.currentPosition == 0.25)
        #expect(player.clock.currentPosition() == 0.25)

        backend.onPositionUpdate?(0.75, 180, load.generation, load.id)
        #expect(player.currentPosition == 0.75)
        #expect(player.clock.currentPosition() == 0.75)
        player.pause()
        #expect(!player.clock.isPlaying)
        #expect(player.currentPosition == 0.75)
    }

    @Test("Mã 150 (không phát được) khi còn bài kế thì tự chuyển bài")
    func unavailableErrorSkipsToNextTrack() async {
        let backend = MockPlaybackBackend()
        let player = makePlayer(backend)
        player.playQueue(songs: [first, second])
        await player.waitForPendingAudioOperation()
        backend.onError?(150, 1, first.id)
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == second.id)
        #expect(backend.loadCalls.last?.id == second.id)
        player.clearForSignOut()
    }

    @Test("Mã 150 ở bài cuối thì báo lỗi rõ và dừng, không chuyển bài")
    func unavailableErrorOnLastTrackShowsMessage() async {
        let backend = MockPlaybackBackend()
        let player = makePlayer(backend)
        player.playQueue(songs: [first])
        await player.waitForPendingAudioOperation()
        backend.onError?(150, 1, first.id)
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == first.id)
        #expect(player.playbackErrorMessage != nil)
        #expect(!player.isPlaying)
        player.clearForSignOut()
    }

    @Test("Lỗi của bài cũ (generation cũ) không làm chuyển bài mới")
    func staleUnavailableErrorIsIgnored() async {
        let backend = MockPlaybackBackend()
        let player = makePlayer(backend)
        player.playQueue(songs: [first, second])
        await player.waitForPendingAudioOperation()
        player.next()
        await player.waitForPendingAudioOperation()
        backend.onError?(150, 1, first.id)
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == second.id)
        #expect(player.playbackErrorMessage == nil)
        player.clearForSignOut()
    }
}
