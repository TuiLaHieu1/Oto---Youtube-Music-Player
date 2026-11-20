import Foundation
import Testing
import OtoCore
@testable import Oto

/// Đếm số lần đọc cache và gọi mạng của Home; không dùng network thật.
actor HomeLoadCounter {
    var feedFetches = 0
    var continuationFetches = 0
    var cacheLoads = 0
    var saves = 0
    var clears = 0
    var cachedFeed: CachedHomeFeed?

    func nextFeed() -> YTMusicParsers.HomeFeedContent {
        feedFetches += 1
        return YTMusicParsers.HomeFeedContent(
            sections: [
                HomeSection(
                    id: "section_\(feedFetches)",
                    title: "Gợi ý \(feedFetches)"
                )
            ]
        )
    }

    func seed(_ feed: CachedHomeFeed) {
        cachedFeed = feed
    }

    func loadCache() -> CachedHomeFeed? {
        cacheLoads += 1
        return cachedFeed
    }

    func save(_ feed: CachedHomeFeed) {
        saves += 1
        cachedFeed = feed
    }
}

extension SharedSessionStateTests {
@Suite("Home chỉ nạp mạng khi cần", .serialized)
@MainActor
struct HomeFeedLoadTests {
    private func makeSource(_ counter: HomeLoadCounter) -> HomeFeedSource {
        HomeFeedSource(
            loadCachedFeed: { await counter.loadCache() },
            fetchFeed: { await counter.nextFeed() },
            fetchContinuation: { _ in
                await counter.recordContinuation()
                return YTMusicParsers.HomeContinuationPage(sections: [], nextToken: nil)
            },
            saveFeed: { await counter.save($0) },
            clearCache: { await counter.recordClear() }
        )
    }

    @Test("Quay lại Home có cache thì không gọi mạng")
    func cachedFeedSkipsNetworkOnReturn() async {
        let counter = HomeLoadCounter()
        await counter.seed(
            CachedHomeFeed(sections: [HomeSection(id: "cached", title: "Đã lưu")])
        )
        let vm = HomeViewModel(source: makeSource(counter))

        await vm.loadIfNeeded()
        #expect(vm.hasContent)
        #expect(await counter.cacheLoads == 1)
        #expect(await counter.feedFetches == 0)

        // Tab Home xuất hiện lại hoặc view bị tạo lại.
        await vm.loadIfNeeded()
        #expect(await counter.feedFetches == 0)
        #expect(await counter.cacheLoads == 1)
    }

    @Test("Chưa có cache mới gọi mạng, sau đó không lặp lại")
    func emptyCacheFetchesOnce() async {
        let counter = HomeLoadCounter()
        let vm = HomeViewModel(source: makeSource(counter))

        await vm.loadIfNeeded()
        #expect(vm.hasContent)
        #expect(await counter.feedFetches == 1)

        await vm.loadIfNeeded()
        #expect(await counter.feedFetches == 1)
    }

    @Test("Người dùng refresh hoặc đổi ngôn ngữ luôn gọi mạng")
    func explicitRefreshFetchesAgain() async {
        let counter = HomeLoadCounter()
        let vm = HomeViewModel(source: makeSource(counter))

        await vm.loadIfNeeded()
        #expect(await counter.feedFetches == 1)

        await vm.refresh()
        #expect(await counter.feedFetches == 2)
    }

    @Test("Speed Dial thật giữ nguyên vị trí sau mục Nghe lại")
    func serverSpeedDialKeepsOrder() throws {
        let source = """
        {"contents":{"singleColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{
          "sectionListRenderer":{"contents":[
            {"musicCarouselShelfRenderer":{"title":{"runs":[{"text":"Nghe lại"}]},"contents":[
              {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Bài cũ"}]},
               "navigationEndpoint":{"watchEndpoint":{"videoId":"old"}}}}
            ]}},
            {"musicSpeedDialShelfRenderer":{"title":{"runs":[{"text":"Truy cập nhanh"}]},"contents":[
              {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Bài ghim mẫu"}]},
               "navigationEndpoint":{"watchEndpoint":{"videoId":"pinned"}}}}
            ]}}
          ]}
        }}}]}}}
        """
        let feed = try YTMusicParsers.parseHomeFeed(from: Data(source.utf8))
        #expect(feed.sections.map(\.title) == ["Nghe lại", "Truy cập nhanh"])
        #expect(feed.sections.last?.id.hasPrefix("server_speed_dial_") == true)
        #expect(feed.speedDial.map(\.id) == ["pinned"])

        let regularOnly = source
            .replacingOccurrences(of: "musicSpeedDialShelfRenderer", with: "musicCarouselShelfRenderer")
        let feedWithoutSpeedDial = try YTMusicParsers.parseHomeFeed(from: Data(regularOnly.utf8))
        #expect(feedWithoutSpeedDial.speedDial.isEmpty)
        #expect(feedWithoutSpeedDial.sections.map(\.title) == ["Nghe lại", "Truy cập nhanh"])
    }

    @Test("Tìm được Speed Dial khi YouTube Music gửi ở trang kế")
    func continuationPreservesSpeedDial() throws {
        let data = Data("""
        {"continuationContents":{"sectionListContinuation":{"contents":[
          {"musicSpeedDialShelfRenderer":{"title":{"runs":[{"text":"Speed dial"}]},"contents":[
            {"musicTwoRowItemRenderer":{"title":{"runs":[{"text":"Đã ghim mẫu"}]},
             "navigationEndpoint":{"watchEndpoint":{"videoId":"sample"}}}}
          ]}}
        ]}}}
        """.utf8)
        let page = try YTMusicParsers.parseHomeContinuationPage(from: data)
        #expect(page.sections.first?.id.hasPrefix("server_speed_dial_") == true)
        #expect(page.sections.first?.items.map(\.id) == ["sample"])
    }

    @Test("Phản hồi continuation có tab rỗng kết thúc Home bình thường")
    func verifiedEmptyTabEndsContinuation() throws {
        let terminal = Data("""
        {"responseContext":{},"contents":{"singleColumnBrowseResultsRenderer":{
          "tabs":[{"tabRenderer":{}}]
        }}}
        """.utf8)
        let page = try YTMusicParsers.parseHomeContinuationPage(from: terminal)
        #expect(page.sections.isEmpty)
        #expect(page.nextToken == nil)
        #expect(throws: YTMusicError.self) {
            try YTMusicParsers.parseHomeContinuationPage(from: Data(#"{"alerts":[]}"#.utf8))
        }
    }

    @Test("Trang tiếp theo lỗi không thay Home đang đầy đủ bằng trang đầu")
    func refreshFailureKeepsExistingFeed() async {
        let counter = HomeLoadCounter()
        let source = HomeFeedSource(
            loadCachedFeed: { nil },
            fetchFeed: {
                YTMusicParsers.HomeFeedContent(
                    sections: [HomeSection(id: "fresh", title: "Gợi ý mới")],
                    continuationToken: "mock-next"
                )
            },
            fetchContinuation: { _ in
                await counter.recordContinuation()
                throw URLError(.timedOut)
            },
            saveFeed: { await counter.save($0) },
            clearCache: {}
        )
        let vm = HomeViewModel(source: source)
        vm.sections = [HomeSection(id: "previous", title: "Gợi ý cũ")]
        await vm.refresh()

        #expect(vm.sections.map(\.id) == ["previous"])
        #expect(vm.refreshIncomplete)
        #expect(!vm.isLoading)
        #expect(await counter.saves == 0)
        #expect(await counter.continuationFetches == 2)
    }

    @Test("Trang cuối sai cấu trúc vẫn hiển thị các nhóm đã tải")
    func unsupportedContinuationShowsNewPartialFeed() async {
        let counter = HomeLoadCounter()
        let source = HomeFeedSource(
            loadCachedFeed: { nil },
            fetchFeed: {
                YTMusicParsers.HomeFeedContent(
                    sections: [HomeSection(id: "fresh", title: "Gợi ý mới")],
                    continuationToken: "mock-next"
                )
            },
            fetchContinuation: { token in
                guard token == "mock-next" else { throw YTMusicError.parsingError }
                return YTMusicParsers.HomeContinuationPage(
                    sections: [HomeSection(id: "more", title: "Gợi ý trang giữa")], nextToken: "mock-last"
                )
            },
            saveFeed: { await counter.save($0) },
            clearCache: {}
        )
        let vm = HomeViewModel(source: source)
        vm.sections = [HomeSection(id: "previous", title: "Gợi ý cũ")]
        await vm.refresh()
        #expect(vm.sections.map(\.title) == ["Gợi ý mới", "Gợi ý trang giữa"])
        #expect(vm.moreRecommendationsUnavailable)
        #expect(!vm.refreshIncomplete)
        #expect(await counter.saves == 0)
    }

    @Test("Xóa phiên buộc lần vào Home sau đọc lại cache")
    func clearSessionResetsCacheLookup() async {
        let counter = HomeLoadCounter()
        let vm = HomeViewModel(source: makeSource(counter))
        await vm.loadIfNeeded()
        #expect(await counter.cacheLoads == 1)

        vm.clearSessionData()
        await vm.loadIfNeeded()
        #expect(await counter.cacheLoads == 2)
        #expect(await counter.feedFetches == 1)
    }
}

}
extension HomeLoadCounter {
    func recordContinuation() {
        continuationFetches += 1
    }

    func recordClear() {
        clears += 1
    }
}
