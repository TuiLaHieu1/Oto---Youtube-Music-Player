#if OTO_STREAM_PROBE
import Foundation
import os
import Testing
@testable import Oto

/// URLProtocol giả: không ra mạng, ghi lại request cuối và trả phản hồi định sẵn.
final class PlayerProbeURLProtocol: URLProtocol {
    struct Stub: Sendable {
        let status: Int
        let body: Data
        let failure: URLError.Code?
    }
    struct Captured: Sendable {
        let url: URL?
        let userAgent: String?
        let body: Data?
    }
    static let stub = OSAllocatedUnfairLock<Stub?>(initialState: nil)
    static let captured = OSAllocatedUnfairLock<Captured?>(initialState: nil)

    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        let body = self.request.httpBody ?? self.request.httpBodyStream.map(Self.read)
        let snapshot = Captured(
            url: self.request.url, userAgent: self.request.value(forHTTPHeaderField: "User-Agent"), body: body
        )
        Self.captured.withLock { $0 = snapshot }
        guard let stub = Self.stub.withLock({ $0 }), let url = self.request.url else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        if let failure = stub.failure {
            self.client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: nil)
        if let response { self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        self.client?.urlProtocol(self, didLoad: stub.body)
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite("Khảo sát stream: request player native", .serialized)
struct PlayerProbeClientTests {
    private let videoID = "AbCdEfGhIjK"

    private func makeClient(_ stub: PlayerProbeURLProtocol.Stub) -> YTMusicClient {
        PlayerProbeURLProtocol.stub.withLock { $0 = stub }
        PlayerProbeURLProtocol.captured.withLock { $0 = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlayerProbeURLProtocol.self]
        return YTMusicClient(session: URLSession(configuration: config))
    }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    @Test("Gửi đúng endpoint player, đúng videoId và đổi user-agent theo biến thể")
    func requestShape() async throws {
        let ok = json(["playabilityStatus": ["status": "OK"]])
        let client = self.makeClient(.init(status: 200, body: ok, failure: nil))
        _ = await client.probePlayer(videoId: self.videoID, variant: .safariMac)
        let captured = try #require(PlayerProbeURLProtocol.captured.withLock { $0 })
        #expect(captured.url?.path == "/youtubei/v1/player")
        #expect(captured.userAgent == YTMusicClient.safariMacUserAgent)
        let body = try #require(captured.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["videoId"] as? String == self.videoID)
        let context = try #require(object["context"] as? [String: Any])
        let clientInfo = try #require(context["client"] as? [String: Any])
        #expect(clientInfo["clientName"] as? String == "WEB_REMIX")

        _ = await client.probePlayer(videoId: self.videoID, variant: .iphone)
        let iphone = try #require(PlayerProbeURLProtocol.captured.withLock { $0 })
        #expect(iphone.userAgent != YTMusicClient.safariMacUserAgent)
    }

    @Test("Phản hồi có HLS trả về hasHLS và URL chỉ nằm trong kết quả")
    func hasHLSResponse() async {
        let body = json([
            "playabilityStatus": ["status": "OK"],
            "streamingData": ["hlsManifestUrl": "https://manifest.example.invalid/expire/9999999999/index.m3u8"]
        ])
        let client = self.makeClient(.init(status: 200, body: body, failure: nil))
        let result = await client.probePlayer(videoId: self.videoID, variant: .iphone)
        #expect(result.summary.outcome == .hasHLS)
        #expect(result.hlsURL != nil)
        #expect(!result.summary.logLine(variant: .iphone).contains("example.invalid"))
    }

    @Test("401, 403, 429, 5xx và lỗi mạng ra đúng loại lỗi request")
    func requestErrorKinds() async {
        let cases: [(PlayerProbeURLProtocol.Stub, StreamProbeRequestError)] = [
            (.init(status: 401, body: Data(), failure: nil), .unauthorized),
            (.init(status: 403, body: Data(), failure: nil), .forbidden),
            (.init(status: 429, body: Data(), failure: nil), .rateLimited),
            (.init(status: 503, body: Data(), failure: nil), .server),
            (.init(status: 200, body: Data(), failure: .notConnectedToInternet), .transport)
        ]
        for (stub, expected) in cases {
            let client = self.makeClient(stub)
            let result = await client.probePlayer(videoId: self.videoID, variant: .iphone)
            #expect(result.summary.outcome == .requestError(expected))
            #expect(result.hlsURL == nil)
        }
    }

    @Test("Video ID sai định dạng không gửi request")
    func invalidVideoIDSkipsNetwork() async {
        let client = self.makeClient(.init(status: 200, body: Data(), failure: nil))
        let result = await client.probePlayer(videoId: "bad id", variant: .iphone)
        #expect(result.summary.outcome == .requestError(.other))
        #expect(PlayerProbeURLProtocol.captured.withLock { $0 } == nil)
    }

    @Test("Phản hồi HTML thay vì JSON là sai cấu trúc, không phải lỗi request")
    func htmlIsSchemaMismatch() async {
        let client = self.makeClient(.init(status: 200, body: Data("<html>".utf8), failure: nil))
        let result = await client.probePlayer(videoId: self.videoID, variant: .iphone)
        #expect(result.summary.outcome == .schemaMismatch)
    }
}
#endif
