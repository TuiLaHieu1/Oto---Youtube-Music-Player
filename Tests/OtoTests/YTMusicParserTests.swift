import Testing
import Foundation
@testable import Oto
@testable import OtoCore

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

@Suite("YTMusic Phase 1 Task 2 Regression Tests")
struct YTMusicPhase1Task2RegressionTests {
    @Test("Thẻ hai hàng có cả browseId MPRE và nút phát videoId phải giải quyết thành .album với id album")
    func testAlbumWithPlayButtonOverlayResolvesToAlbum() throws {
        let renderer: [String: Any] = [
            "navigationEndpoint": [
                "browseEndpoint": [
                    "browseId": "MPREb_album123"
                ]
            ],
            "title": [
                "runs": [["text": "Chúng Ta Của Tương Lai"]]
            ],
            "subtitle": [
                "runs": [
                    ["text": "Album"],
                    ["text": " • "],
                    ["text": "Sơn Tùng M-TP"],
                    ["text": " • "],
                    ["text": "2024"]
                ]
            ],
            "thumbnailRenderer": [
                "musicThumbnailRenderer": [
                    "thumbnail": [
                        "thumbnails": [["url": "https://lh3.googleusercontent.com/album=w544-h544"]]
                    ]
                ]
            ],
            "thumbnailOverlay": [
                "musicItemThumbnailOverlayRenderer": [
                    "content": [
                        "musicPlayButtonRenderer": [
                            "playNavigationEndpoint": [
                                "watchEndpoint": [
                                    "videoId": "trk_song_in_album_456"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let item = try #require(YTMusicParsers.parseTwoRowSpeedDialItem(renderer))
        #expect(item.kind == .album)
        #expect(item.id == "MPREb_album123")
        #expect(item.title == "Chúng Ta Của Tương Lai")
        #expect(item.subtitle == "Sơn Tùng M-TP")
        #expect(item.asSong == nil)
    }

    @Test("Trích xuất tên nghệ sĩ chuẩn xác, lọc bỏ nhãn 'Album', dấu phân cách và năm '2024'")
    func testSubtitleArtistExtractionFilteringLabelsAndYears() {
        let subtitleObj: [String: Any] = [
            "runs": [
                ["text": "Album"],
                ["text": " • "],
                ["text": "Sơn Tùng M-TP"],
                ["text": " • "],
                ["text": "2024"]
            ]
        ]
        let artist = YTMusicParsers.extractArtist(from: subtitleObj)
        #expect(artist == "Sơn Tùng M-TP")

        // Kiểm tra trường hợp có kênh nghệ sĩ browseEndpoint UC...
        let channelSubtitle: [String: Any] = [
            "runs": [
                ["text": "Bài hát"],
                ["text": " • "],
                [
                    "text": "Đen",
                    "navigationEndpoint": [
                        "browseEndpoint": ["browseId": "UCchannel_den"]
                    ]
                ],
                ["text": " • "],
                ["text": "2023"]
            ]
        ]
        let artistFromChannel = YTMusicParsers.extractArtist(from: channelSubtitle)
        #expect(artistFromChannel == "Đen")
    }

    @Test("HomeFeedContent.quickPicks lọc bỏ các mục album và chỉ giữ lại bài hát (.song)")
    func testQuickPicksFiltersOutAlbums() {
        let songItem = SpeedDialItem(
            id: "song_1",
            title: "Bài Hát 1",
            subtitle: "Ca Sĩ 1",
            kind: .song
        )
        let albumItem = SpeedDialItem(
            id: "MPREb_album_1",
            title: "Album 1",
            subtitle: "Ca Sĩ 2",
            kind: .album
        )
        let playlistItem = SpeedDialItem(
            id: "PL_123",
            title: "Playlist 1",
            subtitle: "Danh sách phát",
            kind: .playlist
        )

        let section = HomeSection(
            id: "1_quick_picks",
            title: "Lựa chọn nhanh",
            items: [songItem, albumItem, playlistItem]
        )

        let content = YTMusicParsers.HomeFeedContent(
            speedDial: [songItem, albumItem],
            sections: [section]
        )

        let picks = content.quickPicks
        #expect(picks.count == 1)
        #expect(picks.first?.id == "song_1")
        #expect(picks.first?.title == "Bài Hát 1")
    }

    @Test("HomeCache schemaVersion 2 tự động vô hiệu hoá dữ liệu cũ không có schemaVersion 2")
    func testCacheSchemaVersion2Migration() throws {
        // Dữ liệu cache cũ (legacy version 1, không có trường schemaVersion)
        let legacyJSON = """
        {
            "speedDial": [
                {
                    "id": "MPREb_corrupted",
                    "title": "Corrupted Album",
                    "subtitle": "Album",
                    "kind": "song",
                    "isPinned": false
                }
            ],
            "sections": [],
            "quickPicks": [],
            "listenAgain": [],
            "timestamp": \(Date().timeIntervalSince1970)
        }
        """
        let legacyData = Data(legacyJSON.utf8)
        let decodedLegacy = try JSONDecoder().decode(CachedHomeFeed.self, from: legacyData)
        #expect(decodedLegacy.schemaVersion == 1)
        #expect(decodedLegacy.schemaVersion != CachedHomeFeed.schemaVersion)

        // Dữ liệu cache mới (schemaVersion = 2)
        let newFeed = CachedHomeFeed(
            schemaVersion: 2,
            speedDial: [],
            sections: [],
            quickPicks: [],
            listenAgain: []
        )
        let newData = try JSONEncoder().encode(newFeed)
        let decodedNew = try JSONDecoder().decode(CachedHomeFeed.self, from: newData)
        #expect(decodedNew.schemaVersion == 2)
        #expect(decodedNew.schemaVersion == CachedHomeFeed.schemaVersion)
    }

    @Test("SpeedDialPinStore tự động sửa các mục ghim có tiền tố MPRE thành .album")
    func testSpeedDialPinStoreAutoCorrectsAlbumKind() throws {
        let legacyPinnedItem = SpeedDialItem(
            id: "MPREb_saved_as_song",
            title: "Tên Album",
            subtitle: "Tên Ca Sĩ",
            kind: .song,
            isPinned: true
        )
        #expect(legacyPinnedItem.kind == .song)

        let data = try JSONEncoder().encode([legacyPinnedItem])
        let store = SpeedDialPinStore.shared
        UserDefaults.standard.set(data, forKey: "oto_speed_dial_pins_guest")
        defer {
            UserDefaults.standard.removeObject(forKey: "oto_speed_dial_pins_guest")
        }

        let loaded = store.loadPinnedItems()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "MPREb_saved_as_song")
        #expect(loaded.first?.kind == .album)
    }
}
