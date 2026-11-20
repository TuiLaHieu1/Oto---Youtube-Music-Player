import Foundation
import Testing
import OtoCore
@testable import Oto

@Suite("Repeat One tắt khi người dùng đổi bài")
@MainActor
struct RepeatOneSelectionTests {
    let first = Song(id: "repeat_sel_first", title: "First", artist: "Artist", duration: 180)
    let second = Song(id: "repeat_sel_second", title: "Second", artist: "Other Artist", duration: 200)

    private func makePlayer(_ backend: MockPlaybackBackend) -> PlayerViewModel {
        PlayerViewModel(backend: backend, audioSession: TestAudioSession(), updatesSystemNowPlaying: false)
    }

    @Test("Vuốt Mini Player và chọn bài mới đều tắt Repeat One")
    func swipeAndNewSelectionLeaveRepeatOne() async {
        let backend = MockPlaybackBackend()
        let player = makePlayer(backend)
        player.playQueue(songs: [first, second], startIndex: 1)
        await player.waitForPendingAudioOperation()
        player.toggleRepeat()
        player.toggleRepeat()
        #expect(player.repeatMode == .one)
        player.swipeToPreviousTrack()
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == first.id)
        #expect(player.repeatMode == .off)

        player.toggleRepeat()
        player.toggleRepeat()
        #expect(player.repeatMode == .one)
        player.play(song: second)
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == second.id)
        #expect(player.repeatMode == .off)
        player.clearForSignOut()
    }

    @Test("Chọn bài trong hàng đợi tắt Repeat One, Previous chỉ tua thì giữ nguyên")
    func queueSelectionLeavesRepeatOneButSeekKeepsIt() async {
        let backend = MockPlaybackBackend()
        let player = makePlayer(backend)
        player.playQueue(songs: [first, second])
        await player.waitForPendingAudioOperation()
        player.toggleRepeat()
        player.toggleRepeat()
        player.seek(to: 20)
        player.previous()
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == first.id)
        #expect(player.repeatMode == .one)

        player.playQueueItem(at: 1)
        await player.waitForPendingAudioOperation()
        #expect(player.currentSong?.id == second.id)
        #expect(player.repeatMode == .off)
        player.clearForSignOut()
    }
}
