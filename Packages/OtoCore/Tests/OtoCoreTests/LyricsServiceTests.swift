import Testing
import Foundation
@testable import OtoCore

final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    var handler: (@Sendable (URLRequest) throws -> (Data, URLResponse))?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let handler = handler else {
            throw URLError(.badServerResponse)
        }
        return try handler(request)
    }
}

@Suite("Multi-Source Lyrics Engine Tests")
struct LyricsServiceTests {
    @Test("LRCLibProvider fetches and parses synced lyrics successfully")
    func testLRCLibSyncedLyrics() async throws {
        let mockTransport = MockHTTPTransport()
        let sampleJSONString = """
        {
            "id": 12345,
            "trackName": "See You Again",
            "artistName": "Wiz Khalifa",
            "albumName": "Furious 7",
            "duration": 229,
            "instrumental": false,
            "plainLyrics": "It's been a long day without you my friend",
            "syncedLyrics": "[00:01.50]It's been a long day without you\\n[00:06.00]And I'll tell you all about it"
        }
        """
        let sampleJSON = Data(sampleJSONString.utf8)

        mockTransport.handler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                fatalError("Invalid URL")
            }
            return (sampleJSON, response)
        }

        let provider = LRCLibProvider(transport: mockTransport)
        let song = Song(id: "wiz1", title: "See You Again (Official Video)", artist: "Wiz Khalifa", duration: 229)

        let doc = try await provider.fetchLyrics(for: song)
        #expect(doc != nil)
        #expect(doc?.type == .synced)
        #expect(doc?.lines.count == 2)
        #expect(doc?.lines[0].text == "It's been a long day without you")
    }

    @Test("LRCLibProvider falls back to search endpoint on 404")
    func testLRCLibSearchFallback() async throws {
        let mockTransport = MockHTTPTransport()
        let searchResultsString = """
        [
            {
                "id": 999,
                "trackName": "Counting Stars",
                "artistName": "OneRepublic",
                "duration": 257,
                "instrumental": false,
                "syncedLyrics": "[00:10.00]Lately I been, I been losing sleep"
            }
        ]
        """
        let searchResultsJSON = Data(searchResultsString.utf8)

        mockTransport.handler = { request in
            guard let url = request.url else { fatalError("Missing URL") }
            if url.path.contains("/api/get") {
                let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            } else {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (searchResultsJSON, response)
            }
        }

        let provider = LRCLibProvider(transport: mockTransport)
        let song = Song(id: "1r", title: "Counting Stars", artist: "OneRepublic", duration: 257)

        let doc = try await provider.fetchLyrics(for: song)
        #expect(doc != nil)
        #expect(doc?.type == .synced)
        #expect(doc?.lines[0].text == "Lately I been, I been losing sleep")
    }

    @Test("LRCLibProvider rejects mismatched search results")
    func testLRCLibRejectsMismatchedSearch() async throws {
        let mockTransport = MockHTTPTransport()
        let mismatchedJSON = """
        [
            {
                "id": 888,
                "trackName": "Entirely Different Song",
                "artistName": "Random Artist",
                "duration": 500,
                "syncedLyrics": "[00:10.00]Wrong lyrics"
            }
        ]
        """
        mockTransport.handler = { request in
            guard let url = request.url else { fatalError("Missing URL") }
            if url.path.contains("/api/get") {
                let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            } else {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(mismatchedJSON.utf8), response)
            }
        }

        let provider = LRCLibProvider(transport: mockTransport)
        let song = Song(id: "target", title: "Counting Stars", artist: "OneRepublic", duration: 257)

        let doc = try await provider.fetchLyrics(for: song)
        #expect(doc == nil)
    }

    @Test("MultiSourceLyricsService prioritizes synced lyrics over plain lyrics")
    func testPriorityPipeline() async {
        final class PlainProvider: LyricsProvider, @unchecked Sendable {
            let providerName = "PlainProvider"
            func fetchLyrics(for song: Song) async throws -> LyricsDocument? {
                LyricsDocument(type: .plain, plainLyrics: "Plain text lyrics", source: providerName)
            }
        }

        final class SyncedProvider: LyricsProvider, @unchecked Sendable {
            let providerName = "SyncedProvider"
            func fetchLyrics(for song: Song) async throws -> LyricsDocument? {
                let line = LyricsLine(startTime: 1.0, text: "Synced line")
                return LyricsDocument(type: .synced, lines: [line], source: providerName)
            }
        }

        // Even if PlainProvider is listed first, SyncedProvider's synced lyrics must be chosen
        let service = MultiSourceLyricsService(providers: [PlainProvider(), SyncedProvider()])
        let song = Song(id: "p1", title: "Test", artist: "Artist", duration: 100)

        let doc = await service.resolveLyrics(for: song)
        #expect(doc.type == .synced)
        #expect(doc.lines.count == 1)
        #expect(doc.source == "SyncedProvider")
    }

    @Test("MultiSourceLyricsService returns none when all providers return nil")
    func testAllProvidersEmpty() async {
        final class EmptyProvider: LyricsProvider, @unchecked Sendable {
            let providerName = "Empty"
            func fetchLyrics(for song: Song) async throws -> LyricsDocument? { nil }
        }

        let service = MultiSourceLyricsService(providers: [EmptyProvider()])
        let song = Song(id: "empty", title: "No Lyrics", artist: "Nobody", duration: 100)

        let doc = await service.resolveLyrics(for: song)
        #expect(doc.type == .none)
        #expect(doc.lines.isEmpty)
    }
}
