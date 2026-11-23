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

    @Test("Radio bỏ cặp audio/video trùng và giữ bản live cùng các mục người dùng đã chọn")
    @MainActor
    func radioDeduplicatesAudioAndVideo() async throws {
        let catalog = DeferredRadioCatalog()
        let player = PlayerViewModel(
            backend: MockPlaybackBackend(), audioSession: TestAudioSession(),
            catalog: catalog, updatesSystemNowPlaying: false
        )
        let seed = Song(id: "seed", title: "Bài đầu", artist: "Nghệ sĩ")
        let ranked = Song(id: "audio", title: "Bài kế", artist: "Nghệ sĩ", duration: 180)
        let live = Song(id: "live", title: "Bài kế (Live)", artist: "Nghệ sĩ", duration: 181)
        let ambiguousVideo = Song(id: "amb-video", title: "Bài khác (Official Video)", artist: "Nghệ sĩ", duration: 201)
        let ambiguousAudio = [200, 202].map {
            Song(id: "amb-\($0)", title: "Bài khác", artist: "Nghệ sĩ", duration: Double($0))
        }
        let candidates = [
            Song(id: seed.id, title: seed.title, artist: seed.artist, duration: 210),
            Song(id: "seed-video", title: "Bài đầu (Official Video)", artist: seed.artist, duration: 211),
            Song(id: "video", title: "BÀI KẾ [Official Music Video]", artist: ranked.artist, duration: 182),
            ranked, ranked, live, ambiguousVideo
        ] + ambiguousAudio
        let ambiguousIDs = [ambiguousVideo.id] + ambiguousAudio.map(\.id)

        player.playWithRadio(song: seed)
        let radio = try #require(player.radioLoadTask)
        await catalog.finish(with: candidates)
        await radio.value
        #expect(player.queueManager.items.map(\.song.id) == [seed.id, ranked.id, live.id] + ambiguousIDs)

        player.playQueue(songs: [ranked, ranked], continuesWithRadio: true)
        let continuation = try #require(player.radioLoadTask)
        await continuation.value
        #expect(player.queueManager.items.map(\.song.id) == [ranked.id, ranked.id, seed.id, live.id] + ambiguousIDs)
        player.clearForSignOut()
    }
}
