import Foundation
import Testing
import OtoCore
@testable import Oto

@Suite("Nguồn lyrics YouTube Music")
struct YTMusicLyricsProviderTests {
    @Test("Đọc lyrics đồng bộ từ next với mốc mili giây")
    func timedLyrics() {
        let data = Data("""
        {"contents":{"tab":{"timedLyricsModel":{"lyricsData":[
          {"lyricLine":"Dòng hai","startTimeMs":"2500","durationMs":"1000"},
          {"lyricLine":"Dòng một","startTimeMs":"1000","durationMs":"1200"}
        ]}}}}
        """.utf8)

        let document = YTMusicLyricsParser.parseTimed(from: data)
        #expect(document?.type == .synced)
        #expect(document?.lines.map(\.text) == ["Dòng một", "Dòng hai"])
        #expect(document?.lines.first?.startTime == 1.0)
        #expect(document?.lines.first?.endTime == 2.2)
    }

    @Test("Chỉ lấy browse ID của tab lyrics")
    func browseID() {
        let data = Data("""
        {"tabs":[
          {"browseEndpoint":{"browseId":"MPRE_album"}},
          {"browseEndpoint":{"browseId":"MPLYt_lyrics"}}
        ]}
        """.utf8)
        #expect(YTMusicLyricsParser.lyricsBrowseID(from: data) == "MPLYt_lyrics")
    }

    @Test("Đọc lời tĩnh và giữ nguồn ghi công")
    func plainLyrics() {
        let data = Data("""
        {"contents":{"sectionListRenderer":{"contents":[
          {"musicDescriptionShelfRenderer":{
            "description":{"runs":[{"text":"Dòng A\\n"},{"text":"Dòng B"}]},
            "footer":{"runs":[{"text":"Nguồn kiểm thử"}]}
          }}
        ]}}}
        """.utf8)
        let document = YTMusicLyricsParser.parsePlain(from: data)
        #expect(document?.type == .plain)
        #expect(document?.plainLyrics == "Dòng A\nDòng B")
        #expect(document?.source.contains("Nguồn kiểm thử") == true)
    }
}
