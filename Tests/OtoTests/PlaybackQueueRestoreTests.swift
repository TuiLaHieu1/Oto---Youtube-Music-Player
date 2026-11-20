import Foundation
import Testing
import OtoCore
@testable import Oto

@Suite("Playback queue restoration")
struct PlaybackQueueRestoreTests {
    @Test("mở lại app khôi phục queue ở trạng thái pause và chỉ load khi bấm play")
    @MainActor
    func restoresQueuePausedUntilUserResumes() async {
        let suiteName = "PlaybackQueueStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false))
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let song = Song(id: "restored_track", title: "Restored", artist: "Artist", duration: 180)
        let store = PlaybackQueueStore(defaults: defaults, accountId: { "account-a" })
        let queue = QueueManager()
        queue.setQueue(songs: [song])
        store.save(PlaybackSessionSnapshot(queue: queue.snapshot(), currentPosition: 42))

        let mock = MockPlaybackBackend()
        let player = makeTestPlayer(backend: mock, queueStore: store)

        #expect(player.currentSong?.id == song.id)
        #expect(player.currentPosition == 42)
        #expect(!player.isPlaying)
        #expect(mock.loadCalls.isEmpty)

        player.resume()
        await waitForAudioSessionOperation(player)

        #expect(mock.loadCalls.count == 1)
        #expect(mock.loadCalls.first?.id == song.id)
        #expect(mock.loadCalls.first?.startSeconds == 42)
        #expect(mock.loadCalls.first?.shouldPlay == true)
    }

    @Test("không lưu snapshot có vị trí phát không hợp lệ")
    @MainActor
    func rejectsInvalidPlaybackPosition() {
        let suiteName = "PlaybackQueueInvalidStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false))
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PlaybackQueueStore(defaults: defaults, accountId: { "account-a" })
        let queue = QueueManager()
        queue.setQueue(songs: [Song(id: "invalid_position", title: "Song", artist: "Artist")])

        store.save(PlaybackSessionSnapshot(queue: queue.snapshot(), currentPosition: .infinity))

        #expect(store.load() == nil)
    }
}
