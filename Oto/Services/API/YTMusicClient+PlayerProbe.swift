#if DEBUG && OTO_STREAM_PROBE
import Foundation
import OSLog

/// Khảo sát M2: gọi endpoint `player` bằng phiên đăng nhập sẵn có, chỉ đọc.
/// Không lưu hay ghi log phản hồi; chỉ trả về bản tóm tắt và giữ URL HLS trong bộ nhớ.
extension YTMusicClient {
    static let safariMacUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func isValidVideoID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    func makePlayerProbeRequest(videoId: String, variant: StreamProbeVariant) throws -> URLRequest {
        guard Self.isValidVideoID(videoId),
              let url = URL(string: "https://music.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }
        var request = self.makeBaseRequest(url: url)
        if variant == .safariMac {
            request.setValue(Self.safariMacUserAgent, forHTTPHeaderField: "User-Agent")
        }
        let body: [String: Any] = ["context": self.clientContext, "videoId": videoId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func probePlayer(videoId: String, variant: StreamProbeVariant, now: Date = Date()) async -> StreamProbeResult {
        let result: StreamProbeResult
        do {
            let request = try self.makePlayerProbeRequest(videoId: videoId, variant: variant)
            let data = try await self.perform(request, operation: "player-probe")
            result = YTMusicParsers.parseStreamProbe(from: data, now: now)
        } catch {
            result = StreamProbeResult(summary: .failure(.requestError(StreamProbeRequestError(error))), hlsURL: nil)
        }
        let line = result.summary.logLine(variant: variant)
        Logger(subsystem: "com.oto.music", category: "StreamProbe").notice("\(line, privacy: .public)")
        return result
    }
}
#endif
