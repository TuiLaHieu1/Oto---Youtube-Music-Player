import Foundation
import OtoCore
import Testing
@testable import Oto

struct SpeedDialTests {
    private static func makeTwoRowItem(
        videoId: String? = nil,
        playlistId: String? = nil,
        title: String
    ) -> [String: Any] {
        var renderer: [String: Any] = [
            "title": ["runs": [["text": title]]],
            "subtitle": ["runs": [["text": "Artist"]]],
            "thumbnailRenderer": [
                "musicThumbnailRenderer": [
                    "thumbnail": ["thumbnails": [["url": "https://yt3.ggpht.com/thumb=w120-h120"]]]
                ]
            ]
        ]
        if let videoId {
            renderer["navigationEndpoint"] = ["watchEndpoint": ["videoId": videoId]]
        } else if let playlistId {
            renderer["thumbnailOverlay"] = [
                "musicItemThumbnailOverlayRenderer": [
                    "content": [
                        "musicPlayButtonRenderer": [
                            "playNavigationEndpoint": [
                                "watchPlaylistEndpoint": ["playlistId": playlistId]
                            ]
                        ]
                    ]
                ]
            ]
        }
        return ["musicTwoRowItemRenderer": renderer]
    }

    private static func makeResponsiveItem(videoId: String, title: String) -> [String: Any] {
        return [
            "musicResponsiveListItemRenderer": [
                "playlistItemData": ["videoId": videoId],
                "flexColumns": [
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": title]]]]],
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Quick Artist"]]]]]
                ]
            ]
        ]
    }

    @Test("Home parser phân biệt chuẩn Speed dial (Nghe lại) và Quick picks (Chọn nhanh)")
    func testParseHomeFeedSeparation() throws {
        let listenAgainItem = Self.makeTwoRowItem(videoId: "fav_song_1", title: "Favorite Track")
        let playlistItem = Self.makeTwoRowItem(playlistId: "RDCLAK5uy_custom_mix", title: "My Custom Mix")
        let quickPickItem = Self.makeResponsiveItem(videoId: "quick_radio_1", title: "Radio Seed Track")

        let fixture: [String: Any] = [
            "contents": [
                "singleColumnBrowseResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [
                                        [
                                            "musicCarouselShelfRenderer": [
                                                "header": [
                                                    "musicCarouselShelfBasicHeaderRenderer": [
                                                        "title": ["runs": [["text": "Nghe lại"]]]
                                                    ]
                                                ],
                                                "contents": [listenAgainItem, playlistItem]
                                            ]
                                        ],
                                        [
                                            "musicCarouselShelfRenderer": [
                                                "header": [
                                                    "musicCarouselShelfBasicHeaderRenderer": [
                                                        "title": ["runs": [["text": "Chọn nhanh"]]]
                                                    ]
                                                ],
                                                "contents": [quickPickItem]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: fixture)
        let homeContent = try YTMusicParsers.parseHomeFeed(from: data)

        #expect(homeContent.speedDial.count == 2)
        #expect(homeContent.speedDial[0].id == "fav_song_1")
        #expect(homeContent.speedDial[0].kind == .song)
        #expect(homeContent.speedDial[1].id == "RDCLAK5uy_custom_mix")
        #expect(homeContent.speedDial[1].kind == .playlist)

        #expect(homeContent.quickPicks.count == 1)
        #expect(homeContent.quickPicks[0].id == "quick_radio_1")
    }

    @Test("SpeedDialPinStore ghim và đưa mục ghim lên đầu danh sách Speed dial")
    @MainActor
    func testSpeedDialPinning() {
        let pinStore = SpeedDialPinStore.shared
        let item1 = SpeedDialItem(id: "song_1", title: "Song 1", subtitle: "Artist 1")
        let item2 = SpeedDialItem(id: "song_2", title: "Song 2", subtitle: "Artist 2")
        let item3 = SpeedDialItem(id: "song_3", title: "Song 3", subtitle: "Artist 3")

        pinStore.togglePin(item3)
        #expect(pinStore.isPinned(id: "song_3") == true)

        let merged = pinStore.mergePinned(with: [item1, item2, item3])
        #expect(merged.first?.id == "song_3")
        #expect(merged.first?.isPinned == true)
        #expect(merged.count == 3)

        pinStore.togglePin(item3)
        #expect(pinStore.isPinned(id: "song_3") == false)
    }

    @Test("parsePlaylistOrShelfSongs phân tích được danh sách bài từ twoColumnBrowseResultsRenderer")
    func testTwoColumnPlaylistParsing() throws {
        let playlistItem = Self.makeResponsiveItem(videoId: "playlist_track_1", title: "Playlist Track 1")
        let fixture: [String: Any] = [
            "contents": [
                "twoColumnBrowseResultsRenderer": [
                    "secondaryContents": [
                        "sectionListRenderer": [
                            "contents": [
                                [
                                    "musicPlaylistShelfRenderer": [
                                        "contents": [playlistItem]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        let songs = try YTMusicParsers.parsePlaylistOrShelfSongs(from: data)
        #expect(songs.count == 1)
        #expect(songs[0].id == "playlist_track_1")
        #expect(songs[0].title == "Playlist Track 1")
    }
}
