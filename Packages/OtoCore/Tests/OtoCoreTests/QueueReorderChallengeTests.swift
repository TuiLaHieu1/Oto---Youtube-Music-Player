import Testing
import Foundation
import os
@testable import OtoCore

@Suite("Queue Reorder Stress and Invariance Challenge Tests")
struct QueueReorderChallengeTests {

    @Test("Reorder Up Next from start to end preserves currently playing track at index 0")
    func testReorderStartToEnd() {
        let queue = QueueManager()
        let songs = (0..<5).map { Song(id: "s\($0)", title: "Song \($0)", artist: "Artist", duration: 100) }
        queue.setQueue(songs: songs, startIndex: 0)

        #expect(queue.currentSong?.id == "s0")
        #expect(queue.currentIndex == 0)

        // Up Next items:
        // local 0 (s1, fullIndex 1), local 1 (s2, fullIndex 2),
        // local 2 (s3, fullIndex 3), local 3 (s4, fullIndex 4)
        // Move local 0 (s1) to end (local 3):
        // fullSource = (currentIndex + 1) + 0 = 1
        // fullDest = (currentIndex + 1) + 3 + 1 = 5
        queue.moveItem(from: 1, to: 5)

        // Invariant checks
        #expect(queue.currentSong?.id == "s0")
        #expect(queue.currentIndex == 0)
        #expect(queue.items[0].song.id == "s0")

        let expectedOrder = ["s0", "s2", "s3", "s4", "s1"]
        #expect(queue.items.map(\.song.id) == expectedOrder)
        #expect(queue.items.count == 5)
    }

    @Test("Reorder Up Next from end to start preserves currently playing track at index 0")
    func testReorderEndToStart() {
        let queue = QueueManager()
        let songs = (0..<5).map { Song(id: "s\($0)", title: "Song \($0)", artist: "Artist", duration: 100) }
        queue.setQueue(songs: songs, startIndex: 0)

        // Move local 3 (s4, fullIndex 4) to local 0 (s1, fullIndex 1):
        // fullSource = (currentIndex + 1) + 3 = 4
        // fullDest = (currentIndex + 1) + 0 = 1
        queue.moveItem(from: 4, to: 1)

        // Invariant checks
        #expect(queue.currentSong?.id == "s0")
        #expect(queue.currentIndex == 0)
        #expect(queue.items[0].song.id == "s0")

        let expectedOrder = ["s0", "s4", "s1", "s2", "s3"]
        #expect(queue.items.map(\.song.id) == expectedOrder)
        #expect(queue.items.count == 5)
    }

    @Test("Reorder when Up Next has only 1 element does not corrupt or alter queue")
    func testReorderSingleUpcomingElement() {
        let queue = QueueManager()
        let s0 = Song(id: "s0", title: "Song 0", artist: "Artist")
        let s1 = Song(id: "s1", title: "Song 1", artist: "Artist")
        queue.setQueue(songs: [s0, s1], startIndex: 0)

        #expect(queue.remainingCount == 1)
        let originalItemIDs = queue.items.map(\.id)

        // Moving to same index or within bounds
        queue.moveItem(from: 1, to: 1)
        #expect(queue.items.map(\.song.id) == ["s0", "s1"])
        #expect(queue.currentSong?.id == "s0")
        #expect(queue.currentIndex == 0)
        #expect(queue.items.map(\.id) == originalItemIDs)

        queue.moveItem(from: 1, to: 2)
        #expect(queue.items.map(\.song.id) == ["s0", "s1"])
        #expect(queue.currentSong?.id == "s0")
        #expect(queue.currentIndex == 0)
        #expect(queue.items.map(\.id) == originalItemIDs)
    }

    @Test("Reorder when Up Next is empty safely handles out-of-bounds without crash or mutation")
    func testReorderEmptyUpcoming() {
        let queue = QueueManager()
        let s0 = Song(id: "s0", title: "Song 0", artist: "Artist")
        queue.setQueue(songs: [s0], startIndex: 0)

        #expect(queue.remainingCount == 0)

        // Attempting to move non-existent upcoming element at index 1
        queue.moveItem(from: 1, to: 0)
        #expect(queue.items.count == 1)
        #expect(queue.items[0].song.id == "s0")
        #expect(queue.currentIndex == 0)

        queue.moveItem(from: 1, to: 2)
        #expect(queue.items.count == 1)
        #expect(queue.items[0].song.id == "s0")
        #expect(queue.currentIndex == 0)
    }

    @Test("Reorder when queue is completely empty safely handles calls")
    func testReorderCompletelyEmptyQueue() {
        let queue = QueueManager()
        #expect(queue.items.isEmpty)
        #expect(queue.currentIndex == nil)

        queue.moveItem(from: 0, to: 0)
        queue.moveItem(from: 1, to: 2)
        queue.moveItem(from: -1, to: 5)

        #expect(queue.items.isEmpty)
        #expect(queue.currentIndex == nil)
    }

    @Test("Reorder preserves currently playing song when currentIndex > 0")
    func testReorderNonZeroCurrentIndex() {
        let queue = QueueManager()
        let songs = (0..<6).map { Song(id: "s\($0)", title: "Song \($0)", artist: "Artist") }
        queue.setQueue(songs: songs, startIndex: 2) // s2 is playing (currentIndex = 2)

        #expect(queue.currentSong?.id == "s2")
        #expect(queue.currentIndex == 2)
        #expect(queue.remainingCount == 3) // s3, s4, s5

        // Move s3 (fullIndex 3) to after s5 (fullIndex 6)
        queue.moveItem(from: 3, to: 6)

        #expect(queue.currentSong?.id == "s2")
        #expect(queue.currentIndex == 2)
        #expect(queue.items[2].song.id == "s2")
        #expect(queue.items[0].song.id == "s0")
        #expect(queue.items[1].song.id == "s1")

        let expectedOrder = ["s0", "s1", "s2", "s4", "s5", "s3"]
        #expect(queue.items.map(\.song.id) == expectedOrder)
    }

    @Test("Adversarial inputs: negative indices and large out-of-bound indices do not corrupt queue")
    func testAdversarialInvalidIndices() {
        let queue = QueueManager()
        let songs = (0..<4).map { Song(id: "s\($0)", title: "Song \($0)", artist: "Artist") }
        queue.setQueue(songs: songs, startIndex: 1)

        let originalIDs = queue.items.map(\.id)

        // Invalid source
        queue.moveItem(from: -1, to: 2)
        queue.moveItem(from: -999, to: 1)
        queue.moveItem(from: 4, to: 2)
        queue.moveItem(from: 100, to: 2)

        // Invalid destination
        queue.moveItem(from: 2, to: -1)
        queue.moveItem(from: 2, to: -50)
        queue.moveItem(from: 2, to: 5) // count is 4, dest can be up to 4 (append at end), 5 is invalid
        queue.moveItem(from: 2, to: 100)

        #expect(queue.items.map(\.id) == originalIDs)
        #expect(queue.currentIndex == 1)
        #expect(queue.currentSong?.id == "s1")
    }

    @Test("Stress test: 100 items, 1000 random Up Next reorders preserve invariant at index 10")
    func testQueueReorderStressHarness() {
        let queue = QueueManager()
        let totalItems = 100
        let currentIndex = 10
        let songs = (0..<totalItems).map { Song(id: "song_\($0)", title: "Track \($0)", artist: "Artist \($0)") }
        queue.setQueue(songs: songs, startIndex: currentIndex)

        let initialCurrentSongID = queue.currentSong?.id
        let initialHistorySongIDs = queue.items[0...currentIndex].map(\.song.id)
        let initialUpcomingSongIDs = Set(queue.items[(currentIndex + 1)...].map(\.song.id))

        // Deterministic pseudo-random sequence for repeatability
        var seed: UInt64 = 0xDEADBEEFCAFE
        func pseudoRandom(max: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1
            let val = Int((seed >> 32) % UInt64(max))
            return abs(val)
        }

        let upcomingRange = (currentIndex + 1)..<totalItems
        let upcomingCount = upcomingRange.count // 89 items

        for _ in 0..<1000 {
            let fromOffset = pseudoRandom(max: upcomingCount)
            let toOffset = pseudoRandom(max: upcomingCount + 1)
            let source = (currentIndex + 1) + fromOffset
            let dest = (currentIndex + 1) + toOffset

            queue.moveItem(from: source, to: dest)

            // Rigorous oracle assertion on every step
            #expect(queue.items.count == totalItems)
            #expect(queue.currentIndex == currentIndex)
            #expect(queue.currentSong?.id == initialCurrentSongID)
        }

        // Final invariant checks
        #expect(queue.items[0...currentIndex].map(\.song.id) == initialHistorySongIDs)
        let finalUpcomingSongIDs = Set(queue.items[(currentIndex + 1)...].map(\.song.id))
        #expect(finalUpcomingSongIDs == initialUpcomingSongIDs)
        #expect(Set(queue.items.map(\.id)).count == totalItems) // all unique UUIDs preserved
    }

    @Test("Reorder while shuffle is off survives shuffle toggle on and off restoration")
    func testReorderSurvivesShuffleToggleCycle() {
        let queue = QueueManager()
        let songs = (0..<5).map { Song(id: "s\($0)", title: "Song \($0)", artist: "Artist") }
        queue.setQueue(songs: songs, startIndex: 0)

        // Ban đầu: [s0, s1, s2, s3, s4], current = s0 (idx 0)
        // Di chuyển s4 lên sau s0: source 4, dest 1 -> [s0, s4, s1, s2, s3]
        queue.moveItem(from: 4, to: 1)
        #expect(queue.items.map(\.song.id) == ["s0", "s4", "s1", "s2", "s3"])
        #expect(queue.currentSong?.id == "s0")
        #expect(queue.currentIndex == 0)

        // Bật shuffle
        queue.toggleShuffle()
        #expect(queue.isShuffleEnabled == true)
        #expect(queue.currentSong?.id == "s0")

        // Tắt shuffle -> Thứ tự đã reorder trước đó phải được bảo toàn chính xác!
        queue.toggleShuffle()
        #expect(queue.isShuffleEnabled == false)
        #expect(queue.items.map(\.song.id) == ["s0", "s4", "s1", "s2", "s3"])
        #expect(queue.currentSong?.id == "s0")
        #expect(queue.currentIndex == 0)
    }

    @Test("Turning shuffle off keeps played history and queues every unplayed track")
    func disablingShuffleKeepsPlayedHistoryAndUnplayedTracks() {
        let queue = QueueManager()
        let songs = (0..<8).map { Song(id: "history_\($0)", title: "Song \($0)", artist: "A") }
        queue.setQueue(songs: songs)
        queue.toggleShuffle()
        _ = queue.next(userInitiated: true)
        _ = queue.next(userInitiated: true)

        let shuffledItems = queue.items
        guard let currentIndex = queue.currentIndex else {
            #expect(Bool(false))
            return
        }
        let playedItems = Array(shuffledItems.prefix(currentIndex + 1))
        let playedIDs = Set(playedItems.map(\.id))
        let expectedUpcomingIDs = queue.snapshot().originalItems
            .filter { !playedIDs.contains($0.id) }
            .map(\.id)

        queue.toggleShuffle()

        #expect(queue.items.prefix(playedItems.count).map(\.id) == playedItems.map(\.id))
        #expect(queue.items.dropFirst(playedItems.count).map(\.id) == expectedUpcomingIDs)
        #expect(queue.currentIndex == playedItems.count - 1)
        #expect(queue.currentSong?.id == playedItems.last?.song.id)
    }

    @Test("insertNext remains next after shuffle is enabled and disabled")
    func insertNextSurvivesShuffleCycle() {
        let queue = QueueManager()
        let songs = (0..<5).map { Song(id: "shuffle_\($0)", title: "Song \($0)", artist: "A") }
        queue.setQueue(songs: songs, startIndex: 2)
        queue.toggleShuffle()
        queue.insertNext(song: Song(id: "play_next", title: "Play Next", artist: "A"))
        let upcomingSongID: (QueueManager) -> String? = { queue in
            guard let index = queue.currentIndex,
                  queue.items.indices.contains(index + 1) else { return nil }
            return queue.items[index + 1].song.id
        }

        #expect(upcomingSongID(queue) == "play_next")
        queue.toggleShuffle()
        #expect(queue.currentSong?.id == "shuffle_2")
        #expect(upcomingSongID(queue) == "play_next")
        #expect(queue.next()?.id == "play_next")
    }

    @Test("Reordering current track preserves current track identity and updates currentIndex")
    func testReorderCurrentTrackPreservesIdentity() {
        let queue = QueueManager()
        let songs = (0..<5).map { Song(id: "s\($0)", title: "Song \($0)", artist: "Artist") }
        queue.setQueue(songs: songs, startIndex: 2) // s2 đang phát, currentIndex = 2

        #expect(queue.currentSong?.id == "s2")
        #expect(queue.currentIndex == 2)

        // Di chuyển s2 từ index 2 tới cuối (index 5)
        queue.moveItem(from: 2, to: 5)
        // Order mới: [s0, s1, s3, s4, s2]
        #expect(queue.items.map(\.song.id) == ["s0", "s1", "s3", "s4", "s2"])
        #expect(queue.currentSong?.id == "s2")
        #expect(queue.currentIndex == 4)

        // Di chuyển s2 từ index 4 về đầu (index 0)
        queue.moveItem(from: 4, to: 0)
        // Order mới: [s2, s0, s1, s3, s4]
        #expect(queue.items.map(\.song.id) == ["s2", "s0", "s1", "s3", "s4"])
        #expect(queue.currentSong?.id == "s2")
        #expect(queue.currentIndex == 0)
    }

    @Test("onQueueChanged callback is triggered on mutations")
    func testOnQueueChangedTriggers() {
        let queue = QueueManager()
        let counter = OSAllocatedUnfairLock(initialState: 0)
        queue.onQueueChanged = {
            counter.withLock { $0 += 1 }
        }

        let s1 = Song(id: "s1", title: "S1", artist: "A")
        let s2 = Song(id: "s2", title: "S2", artist: "A")

        queue.setQueue(songs: [s1, s2], startIndex: 0)
        #expect(counter.withLock { $0 } == 1)

        _ = queue.next()
        #expect(counter.withLock { $0 } == 2)

        queue.insertNext(song: Song(id: "s3", title: "S3", artist: "A"))
        #expect(counter.withLock { $0 } == 3)

        queue.moveItem(from: 2, to: 0)
        #expect(counter.withLock { $0 } == 4)

        queue.toggleRepeat()
        #expect(counter.withLock { $0 } == 5)

        queue.toggleShuffle()
        #expect(counter.withLock { $0 } == 6)
    }
}
