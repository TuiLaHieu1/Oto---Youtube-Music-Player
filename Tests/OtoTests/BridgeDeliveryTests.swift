import Foundation
import Testing
@testable import Oto

@Suite("Pending command và acknowledgement WebKit")
@MainActor
struct BridgeDeliveryTests {
    @Test("Ready trễ, pause/seek và callback cũ không làm mất command")
    func delayedReadyAndStaleDelivery() {
        let player = SingletonPlayerWebView(forTesting: true)
        var callbacks: [@MainActor (Result<Any, Error>) -> Void] = []
        var calls: [[String: Any]] = []
        player.commandExecutor = { _, arguments, completion in
            calls.append(arguments)
            callbacks.append(completion)
        }
        player.bridgeURLForTesting = SingletonPlayerWebView.watchURL(for: "first")
        player.loadVideo(id: "first", generation: 1)
        player.pause()
        player.seek(to: 35.5)
        #expect(calls.isEmpty)
        #expect(player.pendingLoad?.shouldPlay == false)
        player.handleMessageBody([:], type: "ready")
        #expect(calls.first?["method"] as? String == "adoptLoadedVideo")
        #expect(calls.first?["startSeconds"] as? Double == 35.5)
        #expect(calls.first?["shouldPlay"] as? Bool == false)
        #expect(player.pendingLoad != nil)
        player.loadVideo(id: "second", generation: 2)
        callbacks[0](.success(true))
        #expect(player.pendingLoad?.id == "second")
        #expect(calls.last?["method"] as? String == "loadVideo")
        callbacks[1](.success(true))
        #expect(player.pendingLoad == nil)
    }

    @Test("JS lỗi giữ pending và báo lỗi đúng bài để retry")
    func failedDeliveryKeepsPending() {
        let player = SingletonPlayerWebView(forTesting: true)
        var errorTrack: String?
        player.commandExecutor = { _, _, completion in completion(.failure(URLError(.unknown))) }
        player.onError = { _, _, track in errorTrack = track }
        player.loadVideo(id: "first", generation: 1)
        player.handleMessageBody([:], type: "ready")
        #expect(player.pendingLoad?.id == "first")
        #expect(!player.isBridgeReady)
        #expect(errorTrack == "first")
    }
}
