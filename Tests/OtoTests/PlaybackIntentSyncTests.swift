import Foundation
import Testing
import OtoCore
@testable import Oto

@Suite("Ý định dừng được giữ khi quay lại app")
@MainActor
struct PlaybackIntentSyncTests {
    let song = Song(id: "intent_sync_song", title: "Song", artist: "Artist", duration: 180)

    private func makePlayer(_ backend: MockPlaybackBackend) -> PlayerViewModel {
        PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
    }

    @Test("Mở lại giữ đúng lượt bài và vị trí nhưng đợi Play")
    func restoresPausedQueueAndPosition() async {
        let key = "test.playback.resume.\(UUID())"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let first = self.makePlayer(MockPlaybackBackend())
        first.restorePlaybackResumePoint(storageKey: key)
        first.playQueue(songs: [self.song, self.song], startIndex: 1, sourceTitle: "Album")
        await first.waitForPendingAudioOperation()
        first.seek(to: 102)
        first.pause()

        let backend = MockPlaybackBackend()
        let restored = self.makePlayer(backend)
        restored.restorePlaybackResumePoint(storageKey: key)
        #expect(restored.currentSong == self.song)
        #expect(restored.queueSnapshot.currentIndex == 1)
        #expect(restored.currentPosition == 102)
        #expect(restored.playbackSourceTitle == "Album")
        #expect(!restored.shouldShowPauseButton)
        #expect(backend.loadCalls.isEmpty)
        #expect(backend.playCount == 0)

        restored.resume()
        await restored.waitForPendingAudioOperation()
        #expect(backend.loadCalls.first?.startSeconds == 102)
        #expect(backend.loadCalls.first?.shouldPlay == true)
        restored.clearPlaybackResumePoint()
        #expect(UserDefaults.standard.data(forKey: key) == nil)
    }

    @Test("Đã dừng thì quay lại foreground sẽ bảo engine dừng, không phát lại")
    func foregroundKeepsPausedIntent() async {
        let backend = MockPlaybackBackend()
        let player = makePlayer(backend)
        player.play(song: song)
        await player.waitForPendingAudioOperation()
        backend.onPlaybackStateChange?(1, 1, song.id)
        player.pause()
        let pausesBefore = backend.pauseCount
        let playsBefore = backend.playCount

        player.syncIntentAfterForeground()
        #expect(backend.pauseCount == pausesBefore + 1)
        #expect(backend.playCount == playsBefore)
        #expect(!player.isPlaying)
        player.clearForSignOut()
    }

    @Test("Đang phát thì quay lại foreground không bị dừng")
    func foregroundDoesNotPausePlayingIntent() async {
        let backend = MockPlaybackBackend()
        let player = makePlayer(backend)
        player.play(song: song)
        await player.waitForPendingAudioOperation()
        backend.onPlaybackStateChange?(1, 1, song.id)
        let pausesBefore = backend.pauseCount

        player.syncIntentAfterForeground()
        #expect(backend.pauseCount == pausesBefore)
        player.clearForSignOut()
    }

    @Test("Chưa có bài nào thì quay lại foreground không làm gì")
    func foregroundWithoutSongDoesNothing() {
        let backend = MockPlaybackBackend()
        let player = makePlayer(backend)
        player.syncIntentAfterForeground()
        #expect(backend.pauseCount == 0)
        #expect(backend.playCount == 0)
    }
}
