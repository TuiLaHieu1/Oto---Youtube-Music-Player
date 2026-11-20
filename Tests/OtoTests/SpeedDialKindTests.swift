import Testing
import OtoCore
@testable import Oto

@Suite("Speed dial item type parsing")
struct SpeedDialKindTests {
    @Test("browse IDs phân biệt artist, album và playlist")
    func browseItemKinds() {
        let cases: [(String, SpeedDialItem.Kind)] = [
            ("UC_artist", .artist),
            ("MPREb_album", .album),
            ("VL_playlist", .playlist)
        ]

        for (browseId, expectedKind) in cases {
            let fixture: [String: Any] = [
                "musicSpeedDialItemRenderer": [
                    "navigationEndpoint": ["browseEndpoint": ["browseId": browseId]],
                    "title": ["runs": [["text": "Item"]]]
                ]
            ]

            let item = YTMusicParsers.parseSpeedDialItem(fixture)
            #expect(item?.kind == expectedKind)
            #expect(item?.id == browseId)
        }
    }
}
