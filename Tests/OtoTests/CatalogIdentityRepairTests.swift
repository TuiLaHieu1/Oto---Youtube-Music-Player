import Foundation
import Testing
import OtoCore
@testable import Oto

@Suite("Phân biệt nội dung Home với context phát")
struct CatalogIdentityRepairTests {
    @Test("watch video với playlist context vẫn là Song")
    func songInPlaylist() {
        let item = YTMusicParsers.parseSpeedDialItem([
            "musicTwoRowItemRenderer": [
                "title": ["runs": [["text": "Track"]]],
                "subtitle": ["runs": [["text": "Artist"]]],
                "navigationEndpoint": ["watchEndpoint": ["videoId": "track", "playlistId": "RD_context"]]
            ]
        ])
        #expect(item?.kind == .song)
        #expect(item?.id == "track")
        #expect(item?.asSong?.artist == "Artist")
    }

    @Test("Album browse có Play overlay không biến thành bài hát")
    func albumWithOverlay() {
        let item = YTMusicParsers.parseSpeedDialItem([
            "musicTwoRowItemRenderer": [
                "title": ["runs": [["text": "Album title"]]],
                "subtitle": ["runs": [["text": "Album"], ["text": " • "], ["text": "Artist"]]],
                "navigationEndpoint": ["browseEndpoint": ["browseId": "MPRE_album"]],
                "thumbnailOverlay": ["musicItemThumbnailOverlayRenderer": ["content": [
                    "musicPlayButtonRenderer": ["playNavigationEndpoint": [
                        "watchEndpoint": ["videoId": "first_track", "playlistId": "album_queue"]
                    ]]
                ]]]
            ]
        ])
        #expect(item?.kind == .album)
        #expect(item?.id == "MPRE_album")
        #expect(item?.subtitle == "Artist")
        #expect(item?.asSong == nil)
    }

    @Test("Trang nghệ sĩ đọc header thật và chỉ giữ album")
    func artistDetailKeepsAlbums() throws {
        let fixture: [String: Any] = [
            "contents": [
                "musicImmersiveHeaderRenderer": [
                    "title": ["runs": [["text": "Nghệ sĩ A"]]],
                    "description": ["runs": [["text": "Tiểu sử"]]]
                ],
                "sections": [
                    ["musicTwoRowItemRenderer": [
                        "title": ["runs": [["text": "Album A"]]],
                        "navigationEndpoint": ["browseEndpoint": ["browseId": "MPRE_album_a"]]
                    ]],
                    ["musicTwoRowItemRenderer": [
                        "title": ["runs": [["text": "Playlist A"]]],
                        "navigationEndpoint": ["browseEndpoint": ["browseId": "VLPL_playlist_a"]]
                    ]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        let detail = try YTMusicParsers.parseArtistDetail(browseId: "UC_artist_a", from: data)

        #expect(detail.name == "Nghệ sĩ A")
        #expect(detail.description == "Tiểu sử")
        #expect(detail.albums.map(\.id) == ["MPRE_album_a"])
    }

    @Test("Trang nghệ sĩ giữ thứ tự và loại nội dung của từng shelf")
    func artistDetailKeepsSections() throws {
        let album: [String: Any] = ["musicTwoRowItemRenderer": [
            "title": ["runs": [["text": "Album A"]]],
            "navigationEndpoint": ["browseEndpoint": ["browseId": "MPRE_album_a"]]
        ]]
        let playlist: [String: Any] = ["musicTwoRowItemRenderer": [
            "title": ["runs": [["text": "Mix A"]]],
            "navigationEndpoint": ["browseEndpoint": ["browseId": "VLPL_mix_a"]]
        ]]
        let relatedArtist: [String: Any] = ["musicTwoRowItemRenderer": [
            "title": ["runs": [["text": "Nghệ sĩ B"]]],
            "navigationEndpoint": ["browseEndpoint": ["browseId": "UC_artist_b"]]
        ]]
        let song: [String: Any] = ["musicResponsiveListItemRenderer": [
            "playlistItemData": ["videoId": "video_a"],
            "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": [
                "text": ["runs": [["text": "Bài A"]]]
            ]]]
        ]]
        let secondSong: [String: Any] = ["musicResponsiveListItemRenderer": [
            "playlistItemData": ["videoId": "video_b"],
            "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": [
                "text": ["runs": [["text": "Bài B"]]]
            ]]]
        ]]
        let shelves: [[String: Any]] = [
            ["musicShelfRenderer": ["contents": [song]]],
            ["musicShelfRenderer": ["contents": [secondSong]]],
            ["musicCarouselShelfRenderer": [
                "header": ["musicCarouselShelfBasicHeaderRenderer": [
                    "title": ["runs": [["text": "Album và đĩa đơn"]]]
                ]],
                "contents": [album, playlist]
            ]],
            ["musicCarouselShelfRenderer": [
                "header": ["musicCarouselShelfBasicHeaderRenderer": [
                    "title": ["runs": [["text": "Nghệ sĩ liên quan"]]]
                ]],
                "contents": [relatedArtist]
            ]]
        ]
        let tabContent: [String: Any] = ["sectionListRenderer": ["contents": shelves]]
        let tab: [String: Any] = ["tabRenderer": ["content": tabContent]]
        let column: [String: Any] = [
            "tabs": [tab],
            "header": ["musicImmersiveHeaderRenderer": ["title": ["runs": [["text": "Nghệ sĩ A"]]]]]
        ]
        let fixture: [String: Any] = ["contents": ["singleColumnBrowseResultsRenderer": column]]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        let detail = try YTMusicParsers.parseArtistDetail(browseId: "UC_artist_a", from: data)

        #expect(detail.songs.map(\.id) == ["video_a", "video_b"])
        #expect(detail.sections.map(\.title) == ["Album và đĩa đơn", "Nghệ sĩ liên quan"])
        #expect(detail.sections[0].items.map(\.kind) == [.album, .playlist])
        #expect(detail.sections[1].items.map(\.kind) == [.artist])
    }

    @Test("Home shelf giữ tên, mô tả và thứ tự nội dung từ server")
    func homeShelfMetadata() {
        let shelf: [String: Any] = [
            "header": ["musicCarouselShelfBasicHeaderRenderer": [
                "title": ["runs": [["text": "Fresh finds / old favorites"]]],
                "strapline": ["runs": [["text": "Made for you"]]]
            ]],
            "contents": [
                ["musicTwoRowItemRenderer": [
                    "title": ["runs": [["text": "First"]]],
                    "subtitle": ["runs": [["text": "Artist A"]]],
                    "navigationEndpoint": ["watchEndpoint": ["videoId": "first"]]
                ]],
                ["musicTwoRowItemRenderer": [
                    "title": ["runs": [["text": "Second"]]],
                    "subtitle": ["runs": [["text": "Artist B"]]],
                    "navigationEndpoint": ["watchEndpoint": ["videoId": "second"]]
                ]]
            ]
        ]
        let parsed = YTMusicParsers.parseCarouselShelf(shelf)
        #expect(parsed.title == "Fresh finds / old favorites")
        #expect(parsed.subtitle == "Made for you")
        #expect(parsed.items.map(\.id) == ["first", "second"])
    }

    @Test("Home đọc continuation của section list và giữ shelf ở trang sau")
    func homeContinuation() throws {
        let initial: [String: Any] = ["contents": ["singleColumnBrowseResultsRenderer": [
            "tabs": [["tabRenderer": ["content": ["sectionListRenderer": [
                "contents": [],
                "continuations": [["nextContinuationData": ["continuation": "mock-page-2"]]]
            ]]]]]
        ]]]
        let next: [String: Any] = ["continuationContents": ["sectionListContinuation": [
            "contents": [["musicCarouselShelfRenderer": [
                "header": ["musicCarouselShelfBasicHeaderRenderer": [
                    "title": ["runs": [["text": "New releases"]]],
                    "strapline": ["runs": [["text": "For you"]]]
                ]],
                "contents": [["musicTwoRowItemRenderer": [
                    "title": ["runs": [["text": "Song A"]]],
                    "subtitle": ["runs": [["text": "Artist A"]]],
                    "navigationEndpoint": ["watchEndpoint": ["videoId": "song-a"]]
                ]]]
            ]]],
            "continuations": [["nextContinuationData": ["continuation": "mock-page-3"]]]
        ]]]
        let initialData = try JSONSerialization.data(withJSONObject: initial)
        let nextData = try JSONSerialization.data(withJSONObject: next)

        #expect(try YTMusicParsers.homeContinuationToken(from: initialData) == "mock-page-2")
        let page = try YTMusicParsers.parseHomeContinuationPage(from: nextData)
        #expect(page.sections.map(\.title) == ["New releases"])
        #expect(page.sections.first?.subtitle == "For you")
        #expect(page.sections.first?.items.map(\.id) == ["song-a"])
        #expect(page.nextToken == "mock-page-3")
    }

}

extension CatalogIdentityRepairTests {
    @Test("Radio bỏ cặp audio/video trùng và giữ bản live cùng các mục người dùng đã chọn")
    @MainActor
    func radioDeduplicatesAudioAndVideo() async throws {
        let catalog = DeferredRadioCatalog()
        let player = PlayerViewModel(
            backend: MockPlaybackBackend(), audioSession: TestAudioSession(),
            catalog: catalog, updatesSystemNowPlaying: false
        )
        let seed = Song(id: "seed", title: "Bài đầu", artist: "Nghệ sĩ")
        let ranked = Song(id: "audio", title: "Bài kế", artist: "Nghệ sĩ", duration: 180)
        let live = Song(id: "live", title: "Bài kế (Live)", artist: "Nghệ sĩ", duration: 181)
        let ambiguousVideo = Song(id: "amb-video", title: "Bài khác (Official Video)", artist: "Nghệ sĩ", duration: 201)
        let ambiguousAudio = [200, 202].map {
            Song(id: "amb-\($0)", title: "Bài khác", artist: "Nghệ sĩ", duration: Double($0))
        }
        let candidates = [
            Song(id: seed.id, title: seed.title, artist: seed.artist, duration: 210),
            Song(id: "seed-video", title: "Bài đầu (Official Video)", artist: seed.artist, duration: 211),
            Song(id: "video", title: "BÀI KẾ [Official Music Video]", artist: ranked.artist, duration: 182),
            ranked, ranked, live, ambiguousVideo
        ] + ambiguousAudio
        let ambiguousIDs = [ambiguousVideo.id] + ambiguousAudio.map(\.id)

        player.playWithRadio(song: seed)
        let radio = try #require(player.radioLoadTask)
        await catalog.finish(with: candidates)
        await radio.value
        #expect(player.queueManager.items.map(\.song.id) == [seed.id, ranked.id, live.id] + ambiguousIDs)

        player.playQueue(songs: [ranked, ranked], continuesWithRadio: true)
        let continuation = try #require(player.radioLoadTask)
        await continuation.value
        #expect(player.queueManager.items.map(\.song.id) == [ranked.id, ranked.id, seed.id, live.id] + ambiguousIDs)
        player.clearForSignOut()
    }
}
