import Foundation
import Testing
import OtoCore
@testable import Oto

struct AuthAndSpeedDialRegressionTests {
}

private extension AuthAndSpeedDialRegressionTests {
    static func makeTwoRowItem(videoId: String, title: String) -> [String: Any] {
        [
            "musicTwoRowItemRenderer": [
                "title": ["runs": [["text": title]]],
                "subtitle": ["runs": [["text": "Artist"]]],
                "navigationEndpoint": ["watchEndpoint": ["videoId": videoId]],
                "thumbnailRenderer": [
                    "musicThumbnailRenderer": [
                        "thumbnail": ["thumbnails": [["url": "https://yt3.ggpht.com/thumb"]]]
                    ]
                ]
            ]
        ]
    }

    static func makeShelf(title: String, items: [[String: Any]]) -> [String: Any] {
        [
            "musicCarouselShelfRenderer": [
                "header": [
                    "musicCarouselShelfBasicHeaderRenderer": [
                        "title": ["runs": [["text": title]]]
                    ]
                ],
                "contents": items
            ]
        ]
    }

    static func wrapInBrowseResponse(shelves: [[String: Any]]) -> Data {
        let json: [String: Any] = [
            "contents": [
                "singleColumnBrowseResultsRenderer": [
                    "tabs": [
                        [
                            "tabRenderer": [
                                "content": [
                                    "sectionListRenderer": [
                                        "contents": shelves
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
}

extension AuthAndSpeedDialRegressionTests {

    @Test("Khi response không có Speed Dial, parser phải để speedDial rỗng và không cướp section đầu tiên")
    func missingSpeedDialMustNotStealFirstSection() throws {
        let shelf1 = Self.makeShelf(
            title: "Today's Hits TOP TUNES RIGHT NOW",
            items: [
                Self.makeTwoRowItem(videoId: "v1", title: "Song 1"),
                Self.makeTwoRowItem(videoId: "v2", title: "Song 2")
            ]
        )
        let shelf2 = Self.makeShelf(
            title: "Shorts Featured Section VN",
            items: [
                Self.makeTwoRowItem(videoId: "v3", title: "Song 3")
            ]
        )

        let data = Self.wrapInBrowseResponse(shelves: [shelf1, shelf2])
        let content = try YTMusicParsers.parseHomeFeed(from: data)

        // BẰNG CHỨNG HÀNH VI:
        // Nếu response chỉ là guest feed (không có Speed Dial), parser KHÔNG ĐƯỢC
        // lấy "Today's Hits" làm Speed Dial giả.
        // speedDial phải rỗng để view biết là không có speed dial cá nhân hóa,
        // và sections phải giữ nguyên 2 section gốc.
        #expect(content.speedDial.isEmpty, "Speed Dial phải rỗng khi response không có shelf Speed Dial")
        #expect(content.sections.count == 2, "Sections phải giữ nguyên cả 2 shelf, không bị lấy mất shelf đầu")
        #expect(content.sections.first?.title == "Today's Hits TOP TUNES RIGHT NOW")
    }

    @Test("musicSpeedDialShelfRenderer với title ở root level phải parse đúng title và items")
    func speedDialRootTitleRenderer() throws {
        let speedDialShelf: [String: Any] = [
            "musicSpeedDialShelfRenderer": [
                "title": ["runs": [["text": "Gợi ý nhanh"]]],
                "contents": [
                    Self.makeTwoRowItem(videoId: "sd1", title: "Speed Dial Song 1"),
                    Self.makeTwoRowItem(videoId: "sd2", title: "Speed Dial Song 2")
                ]
            ]
        ]
        let normalShelf = Self.makeShelf(
            title: "Nghe lại",
            items: [Self.makeTwoRowItem(videoId: "rec1", title: "Recent Song")]
        )

        let data = Self.wrapInBrowseResponse(shelves: [speedDialShelf, normalShelf])
        let content = try YTMusicParsers.parseHomeFeed(from: data)

        #expect(content.speedDial.count == 2)
        #expect(content.speedDial.first?.title == "Speed Dial Song 1")
        #expect(content.sections.count == 1)
        #expect(content.sections.first?.title == "Nghe lại")
    }

    @Test("Cookie domain scoping: Không gửi google.com cookies tới music.youtube.com")
    func cookieDomainScoping() {
        let googleCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "google_secret",
            .domain: ".google.com",
            .path: "/"
        ])
        let accountsCookie = HTTPCookie(properties: [
            .name: "SSID",
            .value: "accounts_secret",
            .domain: "accounts.google.com",
            .path: "/"
        ])
        let ytCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "yt_secret",
            .domain: ".youtube.com",
            .path: "/"
        ])
        let musicYTCookie = HTTPCookie(properties: [
            .name: "VISITOR_INFO1_LIVE",
            .value: "visitor_val",
            .domain: "music.youtube.com",
            .path: "/"
        ])
        let maliciousCookie = HTTPCookie(properties: [
            .name: "MALICIOUS",
            .value: "hacked",
            .domain: "notyoutube.com",
            .path: "/"
        ])
        let attackerSubdomain = HTTPCookie(properties: [
            .name: "ATTACK",
            .value: "evil",
            .domain: "youtube.com.attacker.com",
            .path: "/"
        ])

        guard let googleCookie, let accountsCookie, let ytCookie,
              let musicYTCookie, let maliciousCookie, let attackerSubdomain else {
            Issue.record("Không thể tạo fixture HTTPCookie")
            return
        }

        #expect(!CookieStorage.matchesHost(googleCookie, host: "music.youtube.com"))
        #expect(!CookieStorage.matchesHost(accountsCookie, host: "music.youtube.com"))
        #expect(CookieStorage.matchesHost(ytCookie, host: "music.youtube.com"))
        #expect(CookieStorage.matchesHost(musicYTCookie, host: "music.youtube.com"))
        #expect(!CookieStorage.matchesHost(maliciousCookie, host: "music.youtube.com"))
        #expect(!CookieStorage.matchesHost(attackerSubdomain, host: "music.youtube.com"))

        let header = YTMusicClient.buildCookieHeader(
            cookies: [googleCookie, accountsCookie, ytCookie, musicYTCookie, maliciousCookie],
            targetHost: "music.youtube.com"
        )
        #expect(!header.contains("google_secret"))
        #expect(!header.contains("accounts_secret"))
        #expect(!header.contains("MALICIOUS"))
        #expect(header.contains("SAPISID=yt_secret"))
        #expect(header.contains("VISITOR_INFO1_LIVE=visitor_val"))
    }

    @Test("Duplicate cookie precedence: Host cụ thể (music.youtube.com) ưu tiên hơn wildcard (.youtube.com)")
    func duplicateCookiePrecedence() {
        let wildcardCookie = HTTPCookie(properties: [
            .name: "PREF",
            .value: "f1=general",
            .domain: ".youtube.com",
            .path: "/"
        ])
        let specificCookie = HTTPCookie(properties: [
            .name: "PREF",
            .value: "f1=music_specific",
            .domain: "music.youtube.com",
            .path: "/"
        ])
        let otherCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "secret",
            .domain: ".youtube.com",
            .path: "/"
        ])

        guard let wildcardCookie, let specificCookie, let otherCookie else {
            Issue.record("Không thể tạo fixture HTTPCookie")
            return
        }

        let header = YTMusicClient.buildCookieHeader(
            cookies: [wildcardCookie, specificCookie, otherCookie],
            targetHost: "music.youtube.com"
        )
        #expect(header.contains("PREF=f1=music_specific"))
        #expect(!header.contains("PREF=f1=general"))
        #expect(header.contains("SAPISID=secret"))
    }

    @Test("Authorization header: Chỉ dùng SAPISIDHASH đơn và từ chối nếu chỉ có Google cookie")
    func authorizationHeaderFormat() {
        let googleCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "google_val",
            .domain: ".google.com",
            .path: "/"
        ])
        let ytCookie = HTTPCookie(properties: [
            .name: "__Secure-3PAPISID",
            .value: "yt_3papisid_val",
            .domain: ".youtube.com",
            .path: "/"
        ])

        guard let googleCookie, let ytCookie else {
            Issue.record("Không thể tạo fixture HTTPCookie")
            return
        }

        let googleAuth = YTMusicClient.buildAuthorizationHeader(
            cookies: [googleCookie],
            origin: "https://music.youtube.com",
            timestamp: 1_700_000_000
        )
        #expect(googleAuth == nil)

        let ytAuth = YTMusicClient.buildAuthorizationHeader(
            cookies: [ytCookie],
            origin: "https://music.youtube.com",
            timestamp: 1_700_000_000
        )
        #expect(ytAuth != nil)
        #expect(ytAuth?.hasPrefix("SAPISIDHASH 1700000000_") == true)
        #expect(ytAuth?.contains("SAPISID1PHASH") == false)
        #expect(ytAuth?.contains("SAPISID3PHASH") == false)
    }

    @Test("hasValidYouTubeSession: Từ chối phiên nếu chỉ có Google cookie")
    func falsePositiveSessionCheck() {
        let googleCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "google_val",
            .domain: ".google.com",
            .path: "/"
        ])
        let ytCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "yt_val",
            .domain: ".youtube.com",
            .path: "/"
        ])

        guard let googleCookie, let ytCookie else {
            Issue.record("Không thể tạo fixture HTTPCookie")
            return
        }

        #expect(!CookieStorage.hasValidYouTubeSession(cookies: [googleCookie]))
        #expect(CookieStorage.hasValidYouTubeSession(cookies: [ytCookie]))
    }

    @Test("Domain validation: Từ chối các host lạ và chấp nhận host YouTube/Google chuẩn")
    func strictDomainValidation() {
        #expect(CookieStorage.isYouTubeDomain("youtube.com"))
        #expect(CookieStorage.isYouTubeDomain(".youtube.com"))
        #expect(CookieStorage.isYouTubeDomain("music.youtube.com"))
        #expect(CookieStorage.isYouTubeDomain(".music.youtube.com"))
        #expect(!CookieStorage.isYouTubeDomain("notyoutube.com"))
        #expect(!CookieStorage.isYouTubeDomain("youtube.com.attacker.com"))
        #expect(!CookieStorage.isYouTubeDomain("fakeyoutube.com"))
        #expect(!CookieStorage.isYouTubeDomain("google.com"))

        #expect(CookieStorage.isGoogleDomain("google.com"))
        #expect(CookieStorage.isGoogleDomain(".google.com"))
        #expect(CookieStorage.isGoogleDomain("accounts.google.com"))
        #expect(!CookieStorage.isGoogleDomain("notgoogle.com"))
        #expect(!CookieStorage.isGoogleDomain("google.com.attacker.com"))
    }

    @Test("Album và Artist parser báo schema error khi response thiếu header bắt buộc")
    func detailParsersRejectMissingHeaders() {
        let data = Data("{\"contents\": []}".utf8)

        #expect(throws: YTMusicError.self) {
            try YTMusicParsers.parseAlbumDetail(browseId: "album-id", from: data)
        }
        #expect(throws: YTMusicError.self) {
            try YTMusicParsers.parseArtistDetail(browseId: "artist-id", from: data)
        }
    }

    @Test("Home cache rejects records missing required fields")
    func homeCacheRejectsIncompleteRecord() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CachedHomeFeed.self, from: Data("{}".utf8))
        }
    }
}
// MARK: - Repeat One & Loop Guard Regression Suite

@Suite("Repeat One & Loop Guard Regression Tests")
struct RepeatOneAndLoopGuardRegressionTests {
    private let testTrack = Song(id: "loop_track_1", title: "Loop Song", artist: "Artist", duration: 200)

    @Test("Repeat One: PlayerViewModel lặp lại bài hát cũ và tăng generation mới cho backend")
    @MainActor
    func repeatOneViewModelLoopsSong() async {
        let mock = MockPlaybackBackend()
        let vm = makeTestPlayer(backend: mock)

        vm.play(song: testTrack)
        await waitForAudioSessionOperation(vm)
        #expect(mock.loadCalls.count == 1)
        #expect(mock.loadCalls.first?.generation == 1)
        #expect(mock.loadCalls.first?.id == testTrack.id)

        // Bật repeat one (toggle: off -> all -> one)
        vm.toggleRepeat()
        #expect(vm.repeatMode == .all)
        vm.toggleRepeat()
        #expect(vm.repeatMode == .one)

        // Backend báo engine đang phát
        mock.onPlaybackStateChange?(1, 1, testTrack.id)
        #expect(vm.isPlaying == true)

        // Track ended lần 1 (hết bài)
        mock.onTrackEnded?(1, testTrack.id)
        await waitForAudioSessionOperation(vm)

        // Backend phải nhận lệnh phát lại đúng bài testTrack với generation 2 và startSeconds = 0
        #expect(mock.loadCalls.count == 2)
        guard mock.loadCalls.count >= 2 else { return }
        let secondLoad = mock.loadCalls[1]
        #expect(secondLoad.id == testTrack.id)
        #expect(secondLoad.generation == 2)
        #expect(secondLoad.startSeconds == 0)
        #expect(secondLoad.shouldPlay == true)

        // Duplicate callback từ generation 1 cũ bị state machine và VM chặn
        mock.onTrackEnded?(1, testTrack.id)
        #expect(mock.loadCalls.count == 2, "Duplicate callback của gen cũ không được nạp thêm")

        // Track ended lần 2 (hết bài vòng 2)
        mock.onPlaybackStateChange?(1, 2, testTrack.id)
        mock.onTrackEnded?(2, testTrack.id)
        await waitForAudioSessionOperation(vm)

        // Backend tiếp tục nạp vòng 3 với generation 3
        #expect(mock.loadCalls.count == 3)
        guard mock.loadCalls.count >= 3 else { return }
        let thirdLoad = mock.loadCalls[2]
        #expect(thirdLoad.id == testTrack.id)
        #expect(thirdLoad.generation == 3)
    }

    @Test("PlayerBridgeScript: Script JS chứa logic reset __otoTrackEndedFired = false")
    func playerBridgeScriptContainsResetGuard() {
        let script = PlayerBridgeScript.source

        // Kiểm tra reset flag trong các hàm quan trọng
        #expect(script.contains("boundVideo.__otoTrackEndedFired = false"))
        #expect(script.contains("v.__otoTrackEndedFired = false"))
        #expect(script.contains("if (!v.__otoTrackEndedFired)"))
        #expect(script.contains("v.__otoTrackEndedFired = true"))
    }

    @Test("Track ended khi user đã pause: Không tự động chuyển bài tiếp theo")
    @MainActor
    func trackEndedWhilePausedDoesNotAdvance() async {
        let mock = MockPlaybackBackend()
        let vm = makeTestPlayer(backend: mock)

        vm.play(song: testTrack)
        await waitForAudioSessionOperation(vm)
        #expect(mock.loadCalls.count == 1)

        vm.pause()
        mock.onPlaybackStateChange?(2, 1, testTrack.id)
        #expect(vm.isPlaying == false)
        mock.onTrackEnded?(1, testTrack.id)

        #expect(mock.loadCalls.count == 1)
        #expect(vm.isPlaying == false)
    }
}
