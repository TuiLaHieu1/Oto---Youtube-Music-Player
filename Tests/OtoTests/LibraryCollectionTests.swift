import Foundation
import Testing
@testable import Oto

struct LibraryCollectionTests {
    @Test("Library đọc album từ grid và bỏ hàng trùng")
    func albumGrid() throws {
        let data = Data("""
        {
          "contents": {"singleColumnBrowseResultsRenderer": {"tabs": [{"tabRenderer": {"content": {
            "sectionListRenderer": {"contents": [{"gridRenderer": {
              "items": [
                {"musicTwoRowItemRenderer": {"title": {"runs": [{
                  "text": "Album mẫu", "navigationEndpoint": {"browseEndpoint": {"browseId": "MPRE_mock"}}
                }]}}},
                {"musicTwoRowItemRenderer": {"title": {"runs": [{
                  "text": "Album trùng", "navigationEndpoint": {"browseEndpoint": {"browseId": "MPRE_mock"}}
                }]}}}
              ],
              "continuations": [{"nextContinuationData": {"continuation": "mock-token"}}]
            }}]}
          }}}]}}
        }
        """.utf8)
        let page = try YTMusicParsers.parseLibraryCollection(data, collection: .albums, continued: false)
        #expect(page.items.map(\.id) == ["MPRE_mock"])
        #expect(page.items.map(\.title) == ["Album mẫu"])
        #expect(page.nextToken == "mock-token")
    }

    @Test("Library đọc trang tiếp theo của nghệ sĩ")
    func artistContinuation() throws {
        let data = Data("""
        {"continuationContents": {"musicShelfContinuation": {"contents": [
          {"musicResponsiveListItemRenderer": {
            "navigationEndpoint": {"browseEndpoint": {"browseId": "UC_mock"}},
            "flexColumns": [{"musicResponsiveListItemFlexColumnRenderer": {
              "text": {"runs": [{"text": "Nghệ sĩ mẫu"}]}
            }}]
          }}
        ]}}}
        """.utf8)
        let page = try YTMusicParsers.parseLibraryCollection(data, collection: .artists, continued: true)
        #expect(page.items.map(\.id) == ["UC_mock"])
        #expect(page.items.map(\.title) == ["Nghệ sĩ mẫu"])
        #expect(page.nextToken == nil)
    }

    @Test("Library báo lỗi khi trang tiếp theo sai cấu trúc")
    func invalidContinuation() {
        let data = Data(#"{"continuationContents":{"gridContinuation":{"items":[]}}}"#.utf8)
        #expect(throws: YTMusicError.self) {
            try YTMusicParsers.parseLibraryCollection(data, collection: .artists, continued: true)
        }
    }
}
