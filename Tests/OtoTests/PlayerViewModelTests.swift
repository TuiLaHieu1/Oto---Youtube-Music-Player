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
    var onRemoteCommand: ((PlaybackRemoteCommand) -> Void)?
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

    @Test("togglePlayPause during buffering pauses immediately without requiring second tap")
    @MainActor
    func testTogglePlayPauseDuringBuffering() {
        let mock = MockPlaybackBackend()
        let vm = PlayerViewModel(backend: mock)

        vm.play(song: testSong)
        #expect(vm.isBuffering == true)
        #expect(vm.isPlaying == false)
        #expect(vm.shouldShowPauseButton == true)

        // User taps pause button while buffering
        vm.togglePlayPause()

        #expect(mock.pauseCount == 1)
        #expect(vm.shouldShowPauseButton == false)
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

    @Test("Media Session command từ AirPods điều khiển đúng PlayerViewModel")
    @MainActor
    func testMediaSessionRemoteCommands() {
        let mock = MockPlaybackBackend()
        let vm = PlayerViewModel(backend: mock)
        let secondSong = Song(id: "test_track_2", title: "Second", artist: "Artist", duration: 200)
        vm.playQueue(songs: [testSong, secondSong])

        mock.onRemoteCommand?(.pause)
        #expect(mock.pauseCount == 1)

        mock.onRemoteCommand?(.play)
        #expect(mock.playCount == 1)

        mock.onRemoteCommand?(.next)
        #expect(vm.currentSong?.id == secondSong.id)
        #expect(mock.loadCalls.last?.id == secondSong.id)

        mock.onRemoteCommand?(.seek(42))
        #expect(mock.seekCalls.last == 42)
        #expect(vm.currentPosition == 42)
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

    @Test("Home parser phân tích musicSpeedDialShelfRenderer chuẩn YouTube Music")
    func testSpeedDialShelf() throws {
        let speedDialItem: [String: Any] = [
            "musicSpeedDialItemRenderer": [
                "navigationEndpoint": ["watchEndpoint": ["videoId": "speed_1"]],
                "title": ["runs": [["text": "Speed Song"]]],
                "subtitle": ["runs": [["text": "Speed Artist"]]],
                "thumbnail": ["thumbnails": [["url": "https://yt3.ggpht.com/thumb=w120-h120"]]]
            ]
        ]
        let fixture: [String: Any] = [
            "contents": [
                "singleColumnBrowseResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [[
                                        "musicSpeedDialShelfRenderer": [
                                            "header": [
                                                "musicCarouselShelfBasicHeaderRenderer": [
                                                    "title": ["runs": [["text": "Speed dial"]]]
                                                ]
                                            ],
                                            "contents": [speedDialItem]
                                        ]
                                    ]]
                                ]
                            ]
                        ]
                    ]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        let result = try YTMusicParsers.parseHomeSections(from: data)
        #expect(result.quickPicks.first?.id == "speed_1")
        #expect(result.quickPicks.first?.artworkURL?.absoluteString.contains("=w800-h800-l90-rj") == true)
    }

    @Test("upgradeThumbnailURL nâng cấp độ phân giải ảnh thumbnail chuẩn nét")
    func testUpgradeThumbnailURL() {
        let lowRes = "https://lh3.googleusercontent.com/abc=w120-h120-l90-rj"
        let upgraded = YTMusicParsers.upgradeThumbnailURLString(lowRes)
        #expect(upgraded == "https://lh3.googleusercontent.com/abc=w800-h800-l90-rj")

        let sFormat = "https://lh3.googleusercontent.com/xyz=s60"
        let upgradedS = YTMusicParsers.upgradeThumbnailURLString(sFormat)
        #expect(upgradedS == "https://lh3.googleusercontent.com/xyz=s800-c")

        let ytImg = "https://i.ytimg.com/vi/Hn9Uo8Mswa4/hqdefault.jpg"
            + "?sqp=-oaymwEWCJADEOEBIAQqCggAEOADGC0guwJIWg&rs=AMzJL3kBwh"
        let upgradedYt = YTMusicParsers.upgradeThumbnailURLString(ytImg)
        #expect(upgradedYt == "https://i.ytimg.com/vi/Hn9Uo8Mswa4/hqdefault.jpg")

        let ytDefault = "https://i.ytimg.com/vi/xyz123/default.jpg"
        let upgradedDefault = YTMusicParsers.upgradeThumbnailURLString(ytDefault)
        #expect(upgradedDefault == "https://i.ytimg.com/vi/xyz123/hqdefault.jpg")
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

@Suite("YTMusic Up Next Parser Tests")
struct YTMusicUpNextParserTests {
    @Test("UpNext parser parses playlistPanelVideoRenderer correctly")
    func testParseUpNext() throws {
        let renderer: [String: Any] = [
            "playlistPanelVideoRenderer": [
                "videoId": "radio_track_1",
                "title": ["runs": [["text": "Radio Song 1"]]],
                "longBylineText": ["runs": [["text": "Artist 1"], ["text": " • "], ["text": "Album 1"]]],
                "lengthText": ["runs": [["text": "3:45"]]]
            ]
        ]
        let fixture: [String: Any] = [
            "contents": [
                "singleColumnMusicWatchNextResultsRenderer": [
                    "tabbedRenderer": [
                        "watchNextTabbedResultsRenderer": [
                            "tabs": [[
                                "tabRenderer": [
                                    "content": [
                                        "musicQueueRenderer": [
                                            "content": [
                                                "playlistPanelRenderer": [
                                                    "contents": [renderer]
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        let songs = try YTMusicParsers.parseUpNextQueue(from: data)
        #expect(songs.count == 1)
        #expect(songs.first?.id == "radio_track_1")
        #expect(songs.first?.title == "Radio Song 1")
        #expect(songs.first?.artist == "Artist 1")
        #expect(songs.first?.album == "Album 1")
        #expect(songs.first?.duration == 225)
    }
}
