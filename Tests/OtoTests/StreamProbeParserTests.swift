#if DEBUG && OTO_STREAM_PROBE
import Foundation
import Testing
@testable import Oto

/// Fixture tự tạo, không chứa dữ liệu tài khoản hay URL thật.
@Suite("Khảo sát stream: tóm tắt player response")
struct StreamProbeParserTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fakeHLS = "https://manifest.example.invalid/api/manifest/hls_variant"
        + "/expire/1800021600/ei/abc/file/index.m3u8"

    private func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test("Có HLS: phân loại hasHLS, đếm định dạng và tính số giây còn hạn")
    func hasHLS() throws {
        let body: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": [
                "hlsManifestUrl": fakeHLS,
                "formats": [["itag": 18]],
                "adaptiveFormats": [["itag": 140], ["itag": 251]]
            ]
        ]
        let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
        #expect(result.summary.outcome == .hasHLS)
        #expect(result.summary.formatCount == 1)
        #expect(result.summary.adaptiveFormatCount == 2)
        #expect(!result.summary.hasSABR)
        #expect(result.summary.secondsUntilExpiry == 21_600)
        #expect(result.hlsURL?.absoluteString == fakeHLS)
    }

    @Test("Hạn đọc từ tham số query expire")
    func expiryFromQuery() throws {
        let url = "https://manifest.example.invalid/index.m3u8?expire=1800000600&sig=x"
        let body: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": ["hlsManifestUrl": url]
        ]
        let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
        #expect(result.summary.secondsUntilExpiry == 600)
    }

    @Test("Hạn dự phòng từ expiresInSeconds khi URL không có expire")
    func expiryFallback() throws {
        let body: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": [
                "hlsManifestUrl": "https://manifest.example.invalid/index.m3u8", "expiresInSeconds": "300"
            ]
        ]
        let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
        #expect(result.summary.secondsUntilExpiry == 300)
    }

    @Test("expire sai hoặc thiếu thì không có số giây còn hạn")
    func invalidExpiry() throws {
        let body: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": ["hlsManifestUrl": "https://manifest.example.invalid/expire/abc/index.m3u8"]
        ]
        let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
        #expect(result.summary.outcome == .hasHLS)
        #expect(result.summary.secondsUntilExpiry == nil)
    }

    @Test("expire vô cực, tràn số hoặc số thực không làm crash và không có hạn")
    func hostileExpiry() throws {
        for value in ["inf", "1e400", "1e300", "nan", "-5", "99999999999999999999", "1800000600.5"] {
            let body: [String: Any] = [
                "playabilityStatus": ["status": "OK"],
                "streamingData": ["hlsManifestUrl": "https://manifest.example.invalid/index.m3u8?expire=\(value)"]
            ]
            let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
            #expect(result.summary.outcome == .hasHLS)
            #expect(result.summary.secondsUntilExpiry == nil)
        }
    }

    @Test("streamingData null là thiếu; URL HLS không phải https hợp lệ là sai cấu trúc")
    func nullAndInvalidHLS() throws {
        let null = try YTMusicParsers.parseStreamProbe(
            from: data(["playabilityStatus": ["status": "OK"], "streamingData": NSNull()]), now: now
        )
        #expect(null.summary.outcome == .validNoHLS)
        for bad in ["not a url", "http://manifest.example.invalid/x.m3u8", "file:///tmp/x.m3u8"] {
            let body: [String: Any] = ["playabilityStatus": ["status": "OK"], "streamingData": ["hlsManifestUrl": bad]]
            let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
            #expect(result.summary.outcome == .schemaMismatch)
            #expect(result.hlsURL == nil)
        }
    }

    @Test("Chỉ có SABR: hợp lệ nhưng không có HLS")
    func sabrOnly() throws {
        let body: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": [
                "serverAbrStreamingUrl": "https://example.invalid/sabr", "adaptiveFormats": [["itag": 140]]
            ]
        ]
        let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
        #expect(result.summary.outcome == .validNoHLS)
        #expect(result.summary.hasSABR)
        #expect(result.summary.adaptiveFormatCount == 1)
        #expect(result.hlsURL == nil)
    }

    @Test("Trạng thái OK nhưng không có streamingData: hợp lệ, không có HLS")
    func okWithoutStreamingData() throws {
        let body: [String: Any] = ["playabilityStatus": ["status": "OK"]]
        let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
        #expect(result.summary.outcome == .validNoHLS)
        #expect(result.summary.formatCount == 0)
    }

    @Test("UNPLAYABLE và trạng thái lạ được phân loại, không lộ chuỗi tùy ý")
    func unplayable() throws {
        let first = try YTMusicParsers.parseStreamProbe(
            from: data(["playabilityStatus": ["status": "UNPLAYABLE", "reason": "secret text"]]), now: now
        )
        #expect(first.summary.outcome == .unplayable(.unplayable))
        let second = try YTMusicParsers.parseStreamProbe(
            from: data(["playabilityStatus": ["status": "SOMETHING_NEW"]]), now: now
        )
        #expect(second.summary.outcome == .unplayable(.other))
        #expect(!second.summary.description.contains("secret"))
    }

    @Test("JSON sai cấu trúc tách riêng khỏi trường hợp không có HLS")
    func schemaMismatch() throws {
        let cases: [Any] = [
            ["streamingData": ["hlsManifestUrl": "x"]],
            ["playabilityStatus": "OK"],
            ["playabilityStatus": ["status": 1]],
            ["playabilityStatus": ["status": "OK"], "streamingData": "bad"],
            ["playabilityStatus": ["status": "OK"], "streamingData": ["formats": "bad"]],
            ["playabilityStatus": ["status": "OK"], "streamingData": ["hlsManifestUrl": 3]]
        ]
        for body in cases {
            let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
            #expect(result.summary.outcome == .schemaMismatch)
            #expect(result.hlsURL == nil)
        }
        let notJSON = YTMusicParsers.parseStreamProbe(from: Data("<html>".utf8), now: now)
        #expect(notJSON.summary.outcome == .schemaMismatch)
    }

    @Test("Đếm audio theo container và cách giao URL, chọn M4A trực tiếp bitrate cao nhất")
    func audioCounts() throws {
        let low = "https://audio.example.invalid/videoplayback?expire=1800003600&itag=139&n=abc"
        let high = "https://audio.example.invalid/videoplayback?expire=1800007200&itag=140"
        let body: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": [
                "formats": [
                    ["itag": 18, "mimeType": "video/mp4; codecs=\"avc1\"", "url": "https://v.example.invalid/x"]
                ],
                "adaptiveFormats": [
                    ["itag": 139, "mimeType": "audio/mp4; codecs=\"mp4a.40.5\"", "bitrate": 48_000, "url": low],
                    ["itag": 140, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 130_000, "url": high],
                    ["itag": 141, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "signatureCipher": "s=x&url=y"],
                    [
                        "itag": 251, "mimeType": "audio/webm; codecs=\"opus\"",
                        "url": "https://audio.example.invalid/w?n=q"
                    ],
                    ["itag": 250, "mimeType": "audio/webm; codecs=\"opus\"", "cipher": "s=x"],
                    ["itag": 600, "mimeType": "audio/ogg"],
                    ["itag": 137, "mimeType": "video/mp4"],
                    ["itag": 1]
                ]
            ]
        ]
        let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
        let audio = result.summary.audio
        #expect(result.summary.outcome == .validNoHLS)
        #expect(audio.mp4Direct == 2)
        #expect(audio.mp4Cipher == 1)
        #expect(audio.webmDirect == 1)
        #expect(audio.webmCipher == 1)
        #expect(audio.otherAudio == 1)
        #expect(audio.directWithN == 2)
        #expect(result.audioURL?.absoluteString == high)
        #expect(audio.secondsUntilExpiry == 7_200)
        for text in [result.summary.description, String(describing: result)] {
            #expect(!text.contains("example.invalid"))
            #expect(!text.contains("s=x"))
        }
    }

    @Test("Không có audio M4A trực tiếp thì không có audioURL; phần tử định dạng sai kiểu là sai cấu trúc")
    func audioWithoutDirectMP4() throws {
        let cipherOnly: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": ["adaptiveFormats": [
                ["itag": 140, "mimeType": "audio/mp4", "signatureCipher": "s=x"],
                ["itag": 140, "mimeType": "audio/mp4", "url": "http://insecure.example.invalid/x"]
            ]]
        ]
        let result = try YTMusicParsers.parseStreamProbe(from: data(cipherOnly), now: now)
        #expect(result.audioURL == nil)
        #expect(result.summary.audio.mp4Cipher == 1)
        #expect(result.summary.audio.otherAudio == 1)
        let broken: [String: Any] = [
            "playabilityStatus": ["status": "OK"], "streamingData": ["adaptiveFormats": ["bad"]]
        ]
        #expect(try YTMusicParsers.parseStreamProbe(from: data(broken), now: now).summary.outcome == .schemaMismatch)
    }

    @Test("Mô tả và log của kết quả không chứa URL")
    func descriptionHasNoURL() throws {
        let body: [String: Any] = [
            "playabilityStatus": ["status": "OK"],
            "streamingData": ["hlsManifestUrl": fakeHLS]
        ]
        let result = try YTMusicParsers.parseStreamProbe(from: data(body), now: now)
        for text in [result.summary.description, String(describing: result), result.summary.logLine(variant: .iphone)] {
            #expect(!text.contains("http"))
            #expect(!text.contains("manifest"))
            #expect(!text.contains("1800021600"))
        }
    }

    @Test("Lỗi request phân loại theo mã")
    func requestErrors() {
        #expect(StreamProbeRequestError(YTMusicError.authenticationExpired) == .unauthorized)
        #expect(StreamProbeRequestError(YTMusicError.permissionDenied) == .forbidden)
        #expect(StreamProbeRequestError(YTMusicError.rateLimited(retryAfter: 3)) == .rateLimited)
        #expect(StreamProbeRequestError(YTMusicError.transport("x")) == .transport)
        #expect(StreamProbeRequestError(YTMusicError.serverError(statusCode: 503)) == .server)
        #expect(StreamProbeRequestError(YTMusicError.invalidResponse) == .httpOther)
        #expect(StreamProbeRequestError(YTMusicError.invalidURL) == .invalidInput)
        #expect(StreamProbeRequestError(URLError(.timedOut)) == .transport)
        #expect(StreamProbeRequestError(CancellationError()) == .cancelled)
    }
}
#endif
