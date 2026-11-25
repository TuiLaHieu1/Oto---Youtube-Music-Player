import Foundation
import Testing
@testable import Oto

struct MusicSearchTests {
    @Test("Chỉ bật video cho đúng ID có loại video")
    func exactVideoIdentity() {
        let data = Data("""
        {"rows":[
          {"watchEndpoint":{"videoId":"clip","watchEndpointMusicSupportedConfigs":{
            "watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_OMV"}}}},
          {"watchEndpoint":{"videoId":"audio","watchEndpointMusicSupportedConfigs":{
            "watchEndpointMusicConfig":{"musicVideoType":"MUSIC_VIDEO_TYPE_ATV"}}}}
        ]}
        """.utf8)
        #expect(YTMusicParsers.supportsVideo(in: data, id: "clip"))
        #expect(!YTMusicParsers.supportsVideo(in: data, id: "audio"))
        #expect(!YTMusicParsers.supportsVideo(in: data, id: "missing"))
    }

    @Test("Search Tất cả giữ thẻ hàng đầu và bỏ hàng trùng")
    func topResult() throws {
        let card: [String: Any] = [
            "title": ["runs": [["text": "Nghệ sĩ mẫu"]]],
            "onTap": ["browseEndpoint": ["browseId": "UC_mock"]]
        ]
        let rows = [Self.row(id: "UC_mock"), Self.row(id: "MPRE_mock"), Self.row(id: "VLPL_mock")]
        let data = try Self.firstPage(rows, card: card)
        let page = try YTMusicParsers.parseMusicSearch(from: data, scope: .all)
        #expect(page.topResult?.id == "artist:UC_mock")
        #expect(page.results.map(\.id) == ["album:MPRE_mock", "playlist:PL_mock"])
    }

    @Test("Search đọc đúng loại và giữ token của trang tiếp theo")
    func filteredContinuation() throws {
        let shelf: [String: Any] = [
            "contents": [Self.row(id: "MPRE_mock"), Self.row(id: "VLPL_mock"), Self.row(id: "VLPL_mock")],
            "continuations": [["nextContinuationData": ["continuation": "mock-token"]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: [
            "continuationContents": ["musicShelfContinuation": shelf]
        ])
        let page = try YTMusicParsers.parseMusicSearch(from: data, scope: .playlists, isContinuation: true)
        #expect(page.results.map(\.id) == ["playlist:PL_mock"])
        #expect(page.nextToken == "mock-token")
        #expect(page.topResult == nil)
    }

    @Test("Search dùng thông tin dòng bài hát khi trùng thẻ hàng đầu")
    func songTopResult() throws {
        let card: [String: Any] = [
            "title": ["runs": [["text": "Bài hát mẫu"]]],
            "onTap": ["watchEndpoint": ["videoId": "mock-track"]]
        ]
        let song: [String: Any] = [
            "musicResponsiveListItemRenderer": [
                "playlistItemData": ["videoId": "mock-track"],
                "flexColumns": [Self.column("Bài hát mẫu"), Self.column("Nghệ sĩ mẫu")]
            ]
        ]
        let data = try Self.firstPage([song], card: card)
        let page = try YTMusicParsers.parseMusicSearch(from: data, scope: .all)
        guard case .song(let top) = page.topResult else {
            Issue.record("Thiếu bài hát hàng đầu")
            return
        }
        #expect(top.artist == "Nghệ sĩ mẫu")
        #expect(page.results.isEmpty)
    }

    @Test("Search Video giữ ID trên endpoint của hàng và hỗ trợ trang kế")
    func videoSearchAndPagination() throws {
        let clip: [String: Any] = [
            "musicResponsiveListItemRenderer": [
                "navigationEndpoint": ["watchEndpoint": ["videoId": "mock-video"]],
                "flexColumns": [Self.column("Video mẫu"), Self.column("Nghệ sĩ mẫu")]
            ]
        ]
        let first = try Self.firstPage([clip], card: [:])
        let continuation = try JSONSerialization.data(withJSONObject: [
            "continuationContents": ["musicShelfContinuation": ["contents": [clip]]]
        ])
        let initialPage = try YTMusicParsers.parseMusicSearch(from: first, scope: .videos)
        let nextPage = try YTMusicParsers.parseMusicSearch(from: continuation, scope: .videos, isContinuation: true)
        for page in [initialPage, nextPage] {
            guard case .video(let song) = page.results.first else {
                Issue.record("Thiếu kết quả video")
                continue
            }
            #expect(song.id == "mock-video")
        }
    }

    @Test("Album dùng credit có ID và loại nhãn đĩa nhạc khỏi tên nghệ sĩ")
    func albumArtistCredits() throws {
        func credit(_ name: String, id: String) -> [String: Any] {
            ["text": name, "navigationEndpoint": ["browseEndpoint": ["browseId": id]]]
        }
        func track(_ id: String, credits: [[String: Any]]) -> [String: Any] {
            ["musicResponsiveListItemRenderer": [
                "playlistItemData": ["videoId": id],
                "flexColumns": [Self.column(id), [
                    "musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": credits]]
                ]]
            ]]
        }
        let header: [String: Any] = [
            "title": ["runs": [["text": "Album mẫu"]]],
            "subtitle": ["runs": [["text": "Đĩa nhạc"]]],
            "straplineTextOne": ["runs": [credit("Nghệ sĩ A", id: "UC_artist_a")]]
        ]
        let data = try JSONSerialization.data(withJSONObject: [
            "header": ["musicResponsiveHeaderRenderer": header],
            "tracks": [
                track("solo", credits: [["text": "Đĩa nhạc"]]),
                track("duet", credits: [credit("Nghệ sĩ B", id: "UC_artist_b"), credit("Nghệ sĩ C", id: "UC_artist_c")])
            ]
        ])
        let album = try YTMusicParsers.parseAlbumDetail(browseId: "MPRE_demo", from: data)
        #expect(album.songs.first(where: { $0.id == "solo" })?.artists.map(\.browseId) == ["UC_artist_a"])
        let duet = album.songs.first { $0.id == "duet" }
        #expect(duet?.artists.map(\.browseId) == ["UC_artist_b", "UC_artist_c"])
        #expect(album.songs.allSatisfy { $0.artist != "Đĩa nhạc" })
    }

    @Test("Tìm gần đây giữ tối đa sáu từ khóa và không tạo mục trùng")
    @MainActor
    func recentQueriesAreBoundedAndDeduplicated() {
        let vm = SearchViewModel()
        for index in 1...7 {
            vm.query = "Bài \(index)"
            vm.recordCurrentQuery()
        }
        vm.query = "  bài 4  "
        vm.recordCurrentQuery()
        vm.clear()
        #expect(vm.recentQueries == ["bài 4", "Bài 7", "Bài 6", "Bài 5", "Bài 3", "Bài 2"])
        vm.clearRecentQueries()
        #expect(vm.recentQueries.isEmpty)
    }

    private static func firstPage(_ rows: [[String: Any]], card: [String: Any]) throws -> Data {
        let contents: [[String: Any]] = [
            ["musicCardShelfRenderer": card], ["musicShelfRenderer": ["contents": rows]]
        ]
        return try JSONSerialization.data(withJSONObject: [
            "contents": ["sectionListRenderer": ["contents": contents]]
        ])
    }

    private static func column(_ title: String) -> [String: Any] {
        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": title]]]]]
    }

    private static func row(id: String) -> [String: Any] {
        ["musicResponsiveListItemRenderer": [
            "navigationEndpoint": ["browseEndpoint": ["browseId": id]],
            "flexColumns": [Self.column("Kết quả mẫu")]
        ]]
    }
}

@Suite("Hàng đợi Up Next không lặp bài có MV")
struct UpNextWrapperTests {
    private static func video(_ id: String, _ title: String, type: String) -> [String: Any] {
        [
            "videoId": id,
            "title": ["runs": [["text": title]]],
            "longBylineText": ["runs": [["text": "Nghệ sĩ"]]],
            "lengthText": ["runs": [["text": "3:30"]]],
            "navigationEndpoint": ["watchEndpoint": [
                "videoId": id,
                "watchEndpointMusicSupportedConfigs": ["watchEndpointMusicConfig": ["musicVideoType": type]]
            ]]
        ]
    }

    @Test("Mục bọc audio/MV chỉ lấy bản chính, giữ thứ tự và mục thường")
    func wrapperKeepsPrimaryOnly() throws {
        let wrapped: [String: Any] = ["playlistPanelVideoWrapperRenderer": [
            "primaryRenderer": [
                "playlistPanelVideoRenderer": Self.video("audio_2", "Bài hai", type: "MUSIC_VIDEO_TYPE_ATV")
            ],
            "counterpart": [[
                "counterpartRenderer": [
                    "playlistPanelVideoRenderer": Self.video("mv_2", "Bài hai", type: "MUSIC_VIDEO_TYPE_OMV")
                ]
            ]]
        ]]
        let fixture: [String: Any] = ["contents": ["singleColumnMusicWatchNextResultsRenderer": [
            "playlist": ["playlistPanelRenderer": ["contents": [
                ["playlistPanelVideoRenderer": Self.video("audio_1", "Bài một", type: "MUSIC_VIDEO_TYPE_ATV")],
                wrapped,
                ["playlistPanelVideoRenderer": Self.video("audio_3", "Bài ba", type: "MUSIC_VIDEO_TYPE_ATV")]
            ]]]
        ]]]
        let songs = try YTMusicParsers.parseUpNextQueue(from: JSONSerialization.data(withJSONObject: fixture))
        #expect(songs.map(\.id) == ["audio_1", "audio_2", "audio_3"])
    }

    @Test("Bài đang phát là MV: mục bọc có bản còn lại là bài đó thì lấy đúng ID bài đang phát")
    func wrapperPrefersSeedCounterpart() throws {
        let seedPair: [String: Any] = ["playlistPanelVideoWrapperRenderer": [
            "primaryRenderer": [
                "playlistPanelVideoRenderer": Self.video("audio_1", "Bài một", type: "MUSIC_VIDEO_TYPE_ATV")
            ],
            "counterpart": [[
                "counterpartRenderer": [
                    "playlistPanelVideoRenderer": Self.video("mv_1", "Bài một", type: "MUSIC_VIDEO_TYPE_OMV")
                ]
            ]]
        ]]
        let fixture: [String: Any] = ["contents": ["singleColumnMusicWatchNextResultsRenderer": [
            "playlist": ["playlistPanelRenderer": ["contents": [
                seedPair,
                ["playlistPanelVideoRenderer": Self.video("audio_2", "Bài hai", type: "MUSIC_VIDEO_TYPE_ATV")]
            ]]]
        ]]]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        #expect(try YTMusicParsers.parseUpNextQueue(from: data, seedID: "mv_1").map(\.id) == ["mv_1", "audio_2"])
        #expect(try YTMusicParsers.parseUpNextQueue(from: data).map(\.id) == ["audio_1", "audio_2"])
    }
}
