import Testing
import OtoCore
@testable import Oto

@Suite("Playback sign-out cleanup")
struct PlayerSignOutTests {
    @Test("sign-out clears queue, current track and stale playback callbacks")
    @MainActor
    func signOutClearsPlaybackState() async {
        let song = Song(id: "test_track_signout", title: "Test Song", artist: "Artist", duration: 180)
        let mock = MockPlaybackBackend()
        let vm = makeTestPlayer(backend: mock)

        vm.play(song: song)
        await waitForAudioSessionOperation(vm)
        vm.isExpanded = true
        vm.showLyrics = true
        vm.showQueue = true
        vm.showAuth = true
        let previousGeneration = mock.loadCalls.last?.generation
        vm.clearForSignOut()

        #expect(vm.currentSong == nil)
        #expect(vm.queueItems.isEmpty)
        #expect(vm.playbackState == .idle)
        #expect(vm.currentPosition == 0)
        #expect(!vm.isExpanded)
        #expect(!vm.showLyrics)
        #expect(!vm.showQueue)
        #expect(!vm.showAuth)
        #expect(mock.resetCount == 1)

        mock.onPlaybackStateChange?(1, previousGeneration ?? 0, song.id)
        #expect(vm.currentSong == nil)
        #expect(vm.playbackState == .idle)
    }
}
