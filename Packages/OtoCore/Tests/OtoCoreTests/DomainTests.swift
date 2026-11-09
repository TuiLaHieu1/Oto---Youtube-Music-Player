import Testing
import Foundation
@testable import OtoCore

@Suite("Domain Models Tests")
struct DomainTests {
    @Test("Song initialization and equality")
    func testSongProperties() {
        let song1 = Song(
            id: "vid123",
            title: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            duration: 185.0,
            isExplicit: false
        )
        let song2 = Song(
            id: "vid123",
            title: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            duration: 185.0,
            isExplicit: false
        )

        #expect(song1 == song2)
        #expect(song1.id == "vid123")
        #expect(song1.duration == 185.0)
    }

    @Test("QueueItem maintains unique identity for duplicate songs")
    func testQueueItemUniqueness() {
        let song = Song(id: "s1", title: "Track", artist: "Artist", duration: 120)
        let item1 = QueueItem(song: song)
        let item2 = QueueItem(song: song)

        #expect(item1.id != item2.id)
        #expect(item1.song == item2.song)
    }

    @Test("PlaybackState computed properties")
    func testPlaybackState() {
        let song = Song(id: "s1", title: "Track", artist: "Artist", duration: 120)

        let idle = PlaybackState.idle
        #expect(idle.isPlaying == false)
        #expect(idle.currentSong == nil)
        #expect(idle.currentPosition == 0)

        let playing = PlaybackState.playing(song: song, position: 45.5)
        #expect(playing.isPlaying == true)
        #expect(playing.currentSong?.id == "s1")
        #expect(playing.currentPosition == 45.5)

        let paused = PlaybackState.paused(song: song, position: 45.5)
        #expect(paused.isPlaying == false)
        #expect(paused.currentSong?.id == "s1")
    }
}
