import Testing
import Foundation
@testable import Oto
@testable import OtoCore

/// Giả lập PlaybackBackend để kiểm thử độc lập PlayerViewModel mà không cần nạp WebKit DOM thật.
@MainActor
final class MockPlaybackBackend: PlaybackBackend {
    struct LoadCall: Equatable {
        let id: String
        let startSeconds: TimeInterval
        let generation: Int
        let shouldPlay: Bool
    }

    var loadCalls: [LoadCall] = []
    var playCount = 0
    var pauseCount = 0
    var seekCalls: [TimeInterval] = []
    var resetCount = 0

    var onTrackActivated: ((_ trackId: String, _ generation: Int) -> Void)?
    var onPlaybackStateChange: ((_ state: Int, _ generation: Int, _ trackId: String) -> Void)?
    var onPositionUpdate: ((
        _ current: TimeInterval,
        _ duration: TimeInterval,
        _ generation: Int,
        _ trackId: String
    ) -> Void)?
    var onTrackEnded: ((_ generation: Int, _ trackId: String) -> Void)?
    var onError: ((_ code: Int, _ generation: Int, _ trackId: String) -> Void)?
    var onRecoveryRequired: (() -> Void)?

    func loadVideo(id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool) {
        loadCalls.append(LoadCall(id: id, startSeconds: startSeconds, generation: generation, shouldPlay: shouldPlay))
    }

    func play() {
        playCount += 1
    }

    func pause() {
        pauseCount += 1
    }

    func seek(to position: TimeInterval) {
        seekCalls.append(position)
    }

    func resetForSignOut() {
        resetCount += 1
    }
}

@Suite("PlayerViewModel & Fake Backend Integration Tests")
struct PlayerViewModelTests {
    private let testSong = Song(id: "test_track_1", title: "Test Song", artist: "Artist", duration: 180)

    @Test("play song triggers backend loadVideo with generation 1 and shouldPlay true")
    @MainActor
    func testPlaySongLoadsBackend() {
        let mock = MockPlaybackBackend()
        let vm = PlayerViewModel(backend: mock)

        vm.play(song: testSong)

        #expect(mock.loadCalls.count == 1)
        #expect(mock.loadCalls.first?.id == "test_track_1")
        #expect(mock.loadCalls.first?.generation == 1)
        #expect(mock.loadCalls.first?.startSeconds == 0)
        #expect(mock.loadCalls.first?.shouldPlay == true)
        #expect(vm.isBuffering == true)

        // Backend báo engine đang phát
        mock.onPlaybackStateChange?(1, 1, testSong.id)
        #expect(vm.isPlaying == true)
    }

    @Test("crash recovery while playing mints generation 2 and requests play")
    @MainActor
    func testCrashRecoveryWhilePlaying() {
        let mock = MockPlaybackBackend()
        let vm = PlayerViewModel(backend: mock)

        vm.play(song: testSong)
        mock.onPlaybackStateChange?(1, 1, testSong.id)
        mock.onPositionUpdate?(45.0, 180.0, 1, testSong.id)

        #expect(vm.currentPosition == 45.0)
        #expect(vm.isPlaying == true)

        // WebContent process terminates -> báo recovery required
        mock.onRecoveryRequired?()

        // Backend nhận lệnh nạp lại bài với generation 2 và vị trí 45s, shouldPlay true
        #expect(mock.loadCalls.count == 2)
        let recoveryCall = mock.loadCalls[1]
        #expect(recoveryCall.id == "test_track_1")
        #expect(recoveryCall.generation == 2)
        #expect(recoveryCall.startSeconds == 45.0)
        #expect(recoveryCall.shouldPlay == true)

        // Callback từ generation 1 bị từ chối, state giữ nguyên .buffering
        mock.onPlaybackStateChange?(2, 1, testSong.id)
        #expect(vm.playbackState.isBuffering == true)
        #expect(vm.isPlaying == false)

        // Callback từ generation 2 được tiếp nhận
        mock.onPlaybackStateChange?(1, 2, testSong.id)
        #expect(vm.isPlaying == true)
    }

    @Test("crash recovery while paused mints generation 2 without auto-resume")
    @MainActor
    func testCrashRecoveryWhilePaused() {
        let mock = MockPlaybackBackend()
        let vm = PlayerViewModel(backend: mock)

        vm.play(song: testSong)
        mock.onPlaybackStateChange?(1, 1, testSong.id)
        mock.onPositionUpdate?(60.0, 180.0, 1, testSong.id)

        // Người dùng chủ động tạm dừng
        vm.pause()
        mock.onPlaybackStateChange?(2, 1, testSong.id)
        #expect(vm.isPlaying == false)

        // WebContent process crash khi đang paused
        mock.onRecoveryRequired?()

        #expect(mock.loadCalls.count == 2)
        let recoveryCall = mock.loadCalls[1]
        #expect(recoveryCall.id == "test_track_1")
        #expect(recoveryCall.generation == 2)
        #expect(recoveryCall.startSeconds == 60.0)
        #expect(recoveryCall.shouldPlay == false) // Bắt buộc false!
    }

    @Test("stale error callback from old generation is ignored")
    @MainActor
    func testStaleErrorIgnored() {
        let mock = MockPlaybackBackend()
        let vm = PlayerViewModel(backend: mock)

        vm.play(song: testSong)
        #expect(mock.loadCalls.first?.generation == 1)

        let secondSong = Song(id: "test_track_2", title: "Second", artist: "Artist", duration: 200)
        vm.play(song: secondSong)
        #expect(mock.loadCalls.last?.generation == 2)

        // Lỗi từ generation 1 cũ (bài 1)
        mock.onError?(150, 1, "test_track_1")
        // Bài hiện tại vẫn là secondSong (không bị skip bậy bạ)
        #expect(vm.currentSong?.id == "test_track_2")
    }

    @Test("callback cùng generation nhưng sai track identity bị bỏ qua")
    @MainActor
    func testWrongTrackIdentityIgnored() {
        let mock = MockPlaybackBackend()
        let vm = PlayerViewModel(backend: mock)

        vm.play(song: testSong)
        #expect(vm.isBuffering == true)

        mock.onPlaybackStateChange?(1, 1, "old_track")
        mock.onPositionUpdate?(90, 180, 1, "old_track")
        #expect(vm.isBuffering == true)
        #expect(vm.currentPosition == 0)

        mock.onPlaybackStateChange?(1, 1, testSong.id)
        mock.onPositionUpdate?(15, 180, 1, testSong.id)
        #expect(vm.isPlaying == true)
        #expect(vm.currentPosition == 15)
    }

    @Test("seek cập nhật UI và gửi đúng vị trí cho backend ngay lập tức")
    @MainActor
    func testSeekUpdatesImmediately() {
        let mock = MockPlaybackBackend()
        let vm = PlayerViewModel(backend: mock)

        vm.play(song: testSong)
        vm.seek(to: 72.5)

        #expect(vm.currentPosition == 72.5)
        #expect(mock.seekCalls == [72.5])
    }
}

@Suite("YTMusic Home Parser Tests")
struct YTMusicHomeParserTests {
    @Test("Home parser tìm carousel trong wrapper mới nhưng không lấy shelf không rõ nghĩa")
    func testNestedHomeCarousel() throws {
        let quickPick = Self.carousel(title: "Lựa chọn nhanh", id: "quick_1")
        let unrelated = Self.carousel(title: "Bảng xếp hạng", id: "chart_1")
        let fixture: [String: Any] = [
            "contents": [
                "newWrapperRenderer": [
                    "nested": [
                        ["musicCarouselShelfRenderer": quickPick],
                        ["musicCarouselShelfRenderer": unrelated]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture)

        let result = try YTMusicParsers.parseHomeSections(from: data)

        #expect(result.quickPicks.map(\.id) == ["quick_1"])
        #expect(result.listenAgain.isEmpty)
    }

    private static func carousel(title: String, id: String) -> [String: Any] {
        [
            "header": [
                "musicCarouselShelfBasicHeaderRenderer": [
                    "title": ["runs": [["text": title]]]
                ]
            ],
            "contents": [[
                "musicTwoRowItemRenderer": [
                    "navigationEndpoint": ["watchEndpoint": ["videoId": id]],
                    "title": ["runs": [["text": "Bài hát"]]],
                    "subtitle": ["runs": [["text": "Nghệ sĩ"]]]
                ]
            ]]
        ]
    }
}
