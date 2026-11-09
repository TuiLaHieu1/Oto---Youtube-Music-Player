import Testing
import Foundation
@testable import OtoCore

@Suite("Player Queue and Clock Tests")
struct PlayerTests {
    @Test("InterpolatedClock calculates elapsed time and pauses accurately")
    func testInterpolatedClock() async throws {
        let clock = InterpolatedClock(initialPosition: 10.0, initialRate: 1.0)
        #expect(clock.currentPosition() >= 10.0)

        // Sleep briefly to simulate playback
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let runningPos = clock.currentPosition()
        #expect(runningPos > 10.0)

        clock.pause()
        let pausedPos = clock.currentPosition()
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(clock.currentPosition() == pausedPos)

        clock.seek(to: 45.0)
        #expect(clock.currentPosition() == 45.0)
    }

    @Test("QueueManager basic next and previous navigation")
    func testQueueNavigation() {
        let queue = QueueManager()
        let songs = [
            Song(id: "s1", title: "Song 1", artist: "Artist", duration: 100),
            Song(id: "s2", title: "Song 2", artist: "Artist", duration: 200),
            Song(id: "s3", title: "Song 3", artist: "Artist", duration: 300)
        ]
        queue.setQueue(songs: songs, startIndex: 0)

        #expect(queue.currentSong?.id == "s1")
        #expect(queue.next()?.id == "s2")
        #expect(queue.next()?.id == "s3")
        #expect(queue.next() == nil) // End of queue with repeat off

        #expect(queue.previous()?.id == "s2")
        #expect(queue.previous()?.id == "s1")
    }

    @Test("QueueManager repeat modes (off, all, one)")
    func testRepeatModes() {
        let queue = QueueManager()
        let songs = [
            Song(id: "s1", title: "Song 1", artist: "Artist", duration: 100),
            Song(id: "s2", title: "Song 2", artist: "Artist", duration: 200)
        ]
        queue.setQueue(songs: songs, startIndex: 1)

        // 1. Repeat Off -> at end returns nil
        #expect(queue.next() == nil)

        // 2. Repeat All -> at end wraps to index 0
        queue.toggleRepeat() // .all
        #expect(queue.repeatMode == .all)
        #expect(queue.next()?.id == "s1")

        // 3. Repeat One -> next() always returns current song
        queue.toggleRepeat() // .one
        #expect(queue.repeatMode == .one)
        #expect(queue.next()?.id == "s1")
        #expect(queue.next()?.id == "s1")
    }

    @Test("QueueManager shuffle preserves current track and restores original order")
    func testShuffle() {
        let queue = QueueManager()
        let songs = (1...10).map {
            Song(id: "s\($0)", title: "Song \($0)", artist: "Artist", duration: 100)
        }
        queue.setQueue(songs: songs, startIndex: 4) // Song 5
        #expect(queue.currentSong?.id == "s5")

        queue.toggleShuffle()
        #expect(queue.isShuffleEnabled == true)
        #expect(queue.currentSong?.id == "s5")
        #expect(queue.currentIndex == 0)

        // Toggle shuffle off -> restores original list
        queue.toggleShuffle()
        #expect(queue.isShuffleEnabled == false)
        #expect(queue.currentSong?.id == "s5")
        #expect(queue.currentIndex == 4)
    }

    @Test("QueueManager insertNext places track immediately after current track")
    func testInsertNext() {
        let queue = QueueManager()
        let song1 = Song(id: "s1", title: "Song 1", artist: "A", duration: 100)
        let song2 = Song(id: "s2", title: "Song 2", artist: "A", duration: 100)
        let specialSong = Song(id: "special", title: "Special", artist: "A", duration: 100)

        queue.setQueue(songs: [song1, song2], startIndex: 0)
        queue.insertNext(song: specialSong)

        #expect(queue.next()?.id == "special")
        #expect(queue.next()?.id == "s2")
    }

    @Test("QueueManager skipToIndex jumps to designated index and updates currentIndex")
    func testSkipToIndex() {
        let queue = QueueManager()
        let songs = [
            Song(id: "s1", title: "Song 1", artist: "A", duration: 100),
            Song(id: "s2", title: "Song 2", artist: "A", duration: 100),
            Song(id: "s3", title: "Song 3", artist: "A", duration: 100)
        ]
        queue.setQueue(songs: songs, startIndex: 0)
        #expect(queue.currentIndex == 0)

        let target = queue.skipToIndex(2)
        #expect(target?.id == "s3")
        #expect(queue.currentIndex == 2)
        #expect(queue.currentSong?.id == "s3")

        #expect(queue.next() == nil)
        #expect(queue.previous()?.id == "s2")
    }

    @Test("QueueManager giữ đúng queue item khi bài hát bị trùng metadata")
    func testSkipToDuplicateQueueItem() {
        let queue = QueueManager()
        let duplicate = Song(id: "same", title: "Same", artist: "Artist", duration: 100)
        queue.setQueue(songs: [duplicate, duplicate, duplicate], startIndex: 0)

        let itemIDs = queue.items.map(\.id)
        #expect(Set(itemIDs).count == 3)

        #expect(queue.skipToIndex(1)?.id == "same")
        #expect(queue.currentIndex == 1)
        #expect(queue.items[queue.currentIndex ?? 0].id == itemIDs[1])
        #expect(queue.next()?.id == "same")
        #expect(queue.currentIndex == 2)
    }

    @Test("QueueManager không đổi vị trí khi index không hợp lệ")
    func testSkipToInvalidIndex() {
        let queue = QueueManager()
        let songs = [
            Song(id: "s1", title: "Song 1", artist: "A"),
            Song(id: "s2", title: "Song 2", artist: "A")
        ]
        queue.setQueue(songs: songs, startIndex: 1)

        #expect(queue.skipToIndex(-1) == nil)
        #expect(queue.currentIndex == 1)
        #expect(queue.skipToIndex(2) == nil)
        #expect(queue.currentIndex == 1)
    }
}
