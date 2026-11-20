import Foundation
import OtoCore
import Testing
@testable import Oto

struct SpeedDialTests {
    @Test("Ảnh thẻ nhỏ dùng biến thể vừa đủ và giữ URL gốc khi không hỗ trợ")
    func artworkURLUsesDisplaySize() {
        let artwork = URL(string: "https://lh3.googleusercontent.com/cover=w800-h800-l90-rj")
        let thumbnail = OtoArtworkURL.forDisplay(artwork, points: 44, scale: 3)
        let card = OtoArtworkURL.forDisplay(artwork, points: 144, scale: 3)
        let largeTile = OtoArtworkURL.forDisplay(artwork, points: 347, scale: 2)
        #expect(thumbnail?.absoluteString == "https://lh3.googleusercontent.com/cover=w160-h160-l90-rj")
        #expect(card?.absoluteString == "https://lh3.googleusercontent.com/cover=w512-h512-l90-rj")
        #expect(largeTile == artwork)

        let square = URL(string: "https://lh3.googleusercontent.com/cover=s800-c")
        #expect(OtoArtworkURL.forDisplay(square, points: 100, scale: 2)?.absoluteString
                == "https://lh3.googleusercontent.com/cover=s256-c")

        let other = URL(string: "https://example.com/cover.jpg")
        #expect(OtoArtworkURL.forDisplay(other, points: 44, scale: 3) == other)
    }

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

    @Test("Home giữ Nghe lại và Chọn nhanh ở đúng mục của máy chủ")
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

        #expect(homeContent.speedDial.isEmpty)
        #expect(homeContent.sections.map(\.title) == ["Nghe lại", "Chọn nhanh"])
        #expect(homeContent.sections.first?.items.map(\.id) == ["fav_song_1", "RDCLAK5uy_custom_mix"])
        #expect(homeContent.quickPicks.map(\.id) == ["quick_radio_1"])
    }

    @Test("SpeedDialPinStore ghim và đưa mục ghim lên đầu danh sách Speed dial")
    @MainActor
    func testSpeedDialPinning() {
        let pinStore = SpeedDialPinStore.shared
        pinStore.clear()
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
        pinStore.clear()
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

    @Test("parseLibraryPlaylists phân tích được danh sách phát cá nhân từ FEmusic_liked_playlists")
    func testLibraryPlaylistsParsing() throws {
        let playlistItem = Self.makeTwoRowItem(playlistId: "PL_custom_user_1", title: "My User Playlist")
        let fixture: [String: Any] = [
            "contents": [
                "singleColumnBrowseResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [
                                        [
                                            "gridRenderer": [
                                                "items": [playlistItem]
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
        let playlists = try YTMusicParsers.parseLibraryPlaylists(from: data)
        #expect(playlists.count == 1)
        #expect(playlists.first?.id == "PL_custom_user_1")
        #expect(playlists.first?.title == "My User Playlist")
    }
}
