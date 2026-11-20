import Foundation
import MediaPlayer
import Testing
import UIKit
import OtoCore
@testable import Oto

private actor ArtworkFetchGate {
    private(set) var requestCount = 0
    private(set) var cancelledCount = 0
    private var pending: [CheckedContinuation<Data, Error>] = []

    func fetch(_ url: URL) async throws -> Data {
        requestCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending.append($0) }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    private func recordCancellation() {
        cancelledCount += 1
    }

    func waitForRequest(count: Int = 1) async -> Bool {
        for _ in 0..<200 {
            if requestCount >= count { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    func failRequest() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(throwing: URLError(.cannotLoadFromNetwork))
    }

    func finishRequest(with data: Data) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: data)
    }
}

@Suite("Ảnh Lock Screen", .serialized)
@MainActor
struct NowPlayingArtworkTests {
    @Test("Cập nhật tiến độ không tải lại ảnh đang chờ")
    func artworkFetchStaysSingleDuringProgressUpdates() async {
        let gate = ArtworkFetchGate()
        let manager = NowPlayingManager(
            fetchArtwork: { url in try await gate.fetch(url) },
            registerRemoteCommands: false
        )
        let song = Song(
            id: "artwork-test", title: "Test", artist: "Artist", duration: 180,
            artworkURL: URL(string: "https://example.invalid/artwork.png")
        )

        manager.updateNowPlaying(song: song, isPlaying: true, currentTime: 0)
        #expect(await gate.waitForRequest())
        for second in 1...20 {
            manager.updateNowPlaying(song: song, isPlaying: true, currentTime: Double(second))
        }
        #expect(await gate.requestCount == 1)

        await gate.failRequest()
        for _ in 0..<10 { await Task.yield() }
        manager.updateNowPlaying(song: song, isPlaying: true, currentTime: 21)
        #expect(await gate.requestCount == 1)
        manager.updateNowPlaying(song: nil, isPlaying: false, currentTime: 0)
    }

    @Test("Quay lại bài có ảnh cache hủy ảnh bài khác đang tải")
    func cachedArtworkCancelsOtherSong() async {
        let gate = ArtworkFetchGate()
        let manager = NowPlayingManager(
            fetchArtwork: { url in try await gate.fetch(url) },
            registerRemoteCommands: false
        )
        let redImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        guard let redData = redImage.pngData() else {
            Issue.record("Không tạo được ảnh thử")
            return
        }
        let first = Song(
            id: "artwork-a", title: "A", artist: "Artist",
            artworkURL: URL(string: "https://example.invalid/a.png")
        )
        let second = Song(
            id: "artwork-b", title: "B", artist: "Artist",
            artworkURL: URL(string: "https://example.invalid/b.png")
        )

        manager.updateNowPlaying(song: first, isPlaying: true, currentTime: 0)
        #expect(await gate.waitForRequest())
        await gate.finishRequest(with: redData)
        for _ in 0..<1_000 {
            if MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] != nil { break }
            await Task.yield()
        }
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] != nil)

        manager.updateNowPlaying(song: second, isPlaying: true, currentTime: 1)
        #expect(await gate.waitForRequest(count: 2))
        manager.updateNowPlaying(song: first, isPlaying: true, currentTime: 2)
        for _ in 0..<1_000 {
            if await gate.cancelledCount > 0 { break }
            await Task.yield()
        }
        #expect(await gate.cancelledCount == 1)
        await gate.finishRequest(with: redData)
        for _ in 0..<1_000 {
            let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
            let hasTitle = current?[MPMediaItemPropertyTitle] as? String == "A"
            if hasTitle, current?[MPMediaItemPropertyArtwork] != nil { break }
            await Task.yield()
        }
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "A")
        let artwork = info?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
        #expect(artwork != nil)
        manager.updateNowPlaying(song: nil, isPlaying: false, currentTime: 0)
    }

    @Test("Ảnh lỗi tự thử lại khi bài tạm dừng")
    func failedArtworkRetriesWhilePaused() async {
        let gate = ArtworkFetchGate()
        let manager = NowPlayingManager(
            fetchArtwork: { url in try await gate.fetch(url) },
            registerRemoteCommands: false,
            retryArtworkDelayNanoseconds: 1_000_000
        )
        let song = Song(
            id: "artwork-retry", title: "Retry", artist: "Artist",
            artworkURL: URL(string: "https://example.invalid/retry.png")
        )
        manager.updateNowPlaying(song: song, isPlaying: false, currentTime: 0)
        #expect(await gate.waitForRequest())
        await gate.failRequest()
        #expect(await gate.waitForRequest(count: 2))
        #expect(await gate.requestCount == 2)
        manager.updateNowPlaying(song: nil, isPlaying: false, currentTime: 0)
        await gate.failRequest()
    }

    @Test("Lỗi muộn của request đã hủy không chặn ảnh request mới")
    func cancelledFailureCannotReplaceNewRequest() async {
        let gate = ArtworkFetchGate()
        let manager = NowPlayingManager(
            fetchArtwork: { url in try await gate.fetch(url) },
            registerRemoteCommands: false
        )
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        guard let data = image.pngData() else {
            Issue.record("Không tạo được ảnh thử")
            return
        }
        let first = Song(
            id: "pending-a", title: "A", artist: "Artist",
            artworkURL: URL(string: "https://example.invalid/pending-a.png")
        )
        let second = Song(
            id: "pending-b", title: "B", artist: "Artist",
            artworkURL: URL(string: "https://example.invalid/pending-b.png")
        )

        manager.updateNowPlaying(song: first, isPlaying: true, currentTime: 0)
        #expect(await gate.waitForRequest())
        manager.updateNowPlaying(song: second, isPlaying: true, currentTime: 1)
        #expect(await gate.waitForRequest(count: 2))
        manager.updateNowPlaying(song: first, isPlaying: true, currentTime: 2)
        #expect(await gate.waitForRequest(count: 3))
        await gate.failRequest()
        await gate.finishRequest(with: data)
        await gate.finishRequest(with: data)
        for _ in 0..<1_000 {
            if MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] != nil { break }
            await Task.yield()
        }
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "A")
        #expect(info?[MPMediaItemPropertyArtwork] != nil)
        #expect(await gate.requestCount == 3)
        manager.updateNowPlaying(song: nil, isPlaying: false, currentTime: 0)
    }
}
