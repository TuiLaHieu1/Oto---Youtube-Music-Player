#if DEBUG && OTO_STREAM_PROBE
import Foundation

/// Trạng thái playability đã lọc qua danh sách cho phép; không giữ chuỗi `reason` của YouTube.
enum StreamProbePlayability: String, Sendable, Equatable {
    case unplayable = "UNPLAYABLE"
    case loginRequired = "LOGIN_REQUIRED"
    case error = "ERROR"
    case contentCheckRequired = "CONTENT_CHECK_REQUIRED"
    case ageCheckRequired = "AGE_CHECK_REQUIRED"
    case liveStreamOffline = "LIVE_STREAM_OFFLINE"
    case other = "OTHER"
}

/// Lỗi request được tách riêng từng loại để không gộp 401/403/429 thành một.
/// Mã HTTP khác 401/403/429/5xx gộp vào `httpOther`;
/// mã cụ thể nằm trong log `operation=player-probe` của YTMusicClient.
enum StreamProbeRequestError: String, Sendable, Equatable {
    case unauthorized, forbidden, rateLimited, server, httpOther, transport, invalidInput, cancelled, other

    init(_ error: any Error) {
        switch error {
        case is CancellationError: self = .cancelled
        case is URLError: self = .transport
        case let api as YTMusicError:
            switch api {
            case .authenticationExpired: self = .unauthorized
            case .permissionDenied: self = .forbidden
            case .rateLimited: self = .rateLimited
            case .serverError: self = .server
            case .transport: self = .transport
            case .invalidResponse: self = .httpOther
            case .invalidURL: self = .invalidInput
            case .parsingError: self = .other
            }
        default: self = .other
        }
    }
}

enum StreamProbeOutcome: Sendable, Equatable {
    case hasHLS
    case validNoHLS
    case unplayable(StreamProbePlayability)
    case schemaMismatch
    /// Chỉ dùng cho M1: trang chưa có player API, API lỗi, hoặc response không thuộc bài đang yêu cầu.
    case notObserved
    case requestError(StreamProbeRequestError)

    var label: String {
        switch self {
        case .hasHLS: return "hasHLS"
        case .validNoHLS: return "validNoHLS"
        case .unplayable(let status): return "unplayable(\(status.rawValue))"
        case .schemaMismatch: return "schemaMismatch"
        case .notObserved: return "notObserved"
        case .requestError(let kind): return "requestError(\(kind.rawValue))"
        }
    }
}

/// Biến thể request dùng để so sánh; chỉ là nhãn, không chứa dữ liệu.
enum StreamProbeVariant: String, Sendable, CaseIterable {
    case iphone
    case safariMac
    case page
}

/// Đếm định dạng audio theo container và cách giao URL. Chỉ số đếm, không có URL.
/// `direct`: có trường `url`; `cipher`: chỉ có `signatureCipher`/`cipher` (cần giải mã, đang bị cấm).
/// `directWithN`: URL trực tiếp có tham số `n` (YouTube có thể bóp tốc độ nếu không biến đổi; không biến đổi ở đây).
struct StreamProbeAudioCounts: Sendable, Equatable {
    var mp4Direct = 0
    var mp4Cipher = 0
    var webmDirect = 0
    var webmCipher = 0
    var otherAudio = 0
    var directWithN = 0
    var secondsUntilExpiry: Int?

    static let empty = StreamProbeAudioCounts()

    var description: String {
        let expiry = self.secondsUntilExpiry.map(String.init) ?? "nil"
        return "mp4Direct=\(self.mp4Direct) mp4Cipher=\(self.mp4Cipher) webmDirect=\(self.webmDirect) "
            + "webmCipher=\(self.webmCipher) otherAudio=\(self.otherAudio) directWithN=\(self.directWithN) "
            + "audioExpiresIn=\(expiry)"
    }
}

/// Chỉ gồm enum, số đếm và cờ; an toàn để ghi log.
struct StreamProbeSummary: Sendable, Equatable, CustomStringConvertible {
    let outcome: StreamProbeOutcome
    let formatCount: Int
    let adaptiveFormatCount: Int
    let hasSABR: Bool
    let secondsUntilExpiry: Int?
    var audio = StreamProbeAudioCounts.empty

    static func failure(_ outcome: StreamProbeOutcome) -> StreamProbeSummary {
        StreamProbeSummary(
            outcome: outcome, formatCount: 0, adaptiveFormatCount: 0, hasSABR: false, secondsUntilExpiry: nil
        )
    }

    var description: String {
        let expiry = self.secondsUntilExpiry.map(String.init) ?? "nil"
        return "outcome=\(self.outcome.label) formats=\(self.formatCount) adaptive=\(self.adaptiveFormatCount) "
            + "sabr=\(self.hasSABR) expiresIn=\(expiry) \(self.audio.description)"
    }

    func logLine(variant: StreamProbeVariant) -> String {
        "StreamProbe variant=\(variant.rawValue) \(self.description)"
    }
}

/// URL chỉ giữ trong bộ nhớ cho phép thử phát; mô tả không bao giờ in URL.
/// `audioURL` là định dạng `audio/mp4` có `url` trực tiếp với bitrate cao nhất.
struct StreamProbeResult: Sendable, CustomStringConvertible {
    let summary: StreamProbeSummary
    let hlsURL: URL?
    var audioURL: URL?

    var description: String {
        "StreamProbeResult(\(self.summary), hasURL=\(self.hlsURL != nil), hasAudioURL=\(self.audioURL != nil))"
    }
}

extension YTMusicParsers {
    static func parseStreamProbe(from data: Data, now: Date = Date()) -> StreamProbeResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let playability = json["playabilityStatus"] as? [String: Any],
              let status = playability["status"] as? String else {
            return StreamProbeResult(summary: .failure(.schemaMismatch), hlsURL: nil)
        }
        guard status == "OK" else {
            let kind = StreamProbePlayability(rawValue: status) ?? .other
            return StreamProbeResult(summary: .failure(.unplayable(kind)), hlsURL: nil)
        }
        let rawStreaming = json["streamingData"].flatMap { $0 is NSNull ? nil : $0 }
        guard rawStreaming != nil else {
            return StreamProbeResult(summary: .failure(.validNoHLS), hlsURL: nil)
        }
        guard let streaming = rawStreaming as? [String: Any],
              let formats = Self.optionalArray(streaming["formats"]),
              let adaptive = Self.optionalArray(streaming["adaptiveFormats"]) else {
            return StreamProbeResult(summary: .failure(.schemaMismatch), hlsURL: nil)
        }
        let rawHLS = streaming["hlsManifestUrl"].flatMap { $0 is NSNull ? nil : $0 }
        var hlsURL: URL?
        if let rawHLS {
            // Có trường HLS nhưng không phải URL https hợp lệ là sai cấu trúc, không phải "không có HLS".
            guard let text = rawHLS as? String, let url = URL(string: text),
                  url.scheme == "https", url.host != nil else {
                return StreamProbeResult(summary: .failure(.schemaMismatch), hlsURL: nil)
            }
            hlsURL = url
        }
        guard let (audio, audioURL) = Self.audioCounts(in: formats + adaptive, now: now) else {
            return StreamProbeResult(summary: .failure(.schemaMismatch), hlsURL: nil)
        }
        let expiresIn = (streaming["expiresInSeconds"] as? String).flatMap(Int.init)
        let expiry = hlsURL.flatMap { Self.secondsUntilExpiry(of: $0, now: now) } ?? (hlsURL != nil ? expiresIn : nil)
        var summary = StreamProbeSummary(
            outcome: hlsURL != nil ? .hasHLS : .validNoHLS,
            formatCount: formats.count,
            adaptiveFormatCount: adaptive.count,
            hasSABR: streaming["serverAbrStreamingUrl"] is String,
            secondsUntilExpiry: expiry
        )
        summary.audio = audio
        return StreamProbeResult(summary: summary, hlsURL: hlsURL, audioURL: audioURL)
    }

    /// Phần tử định dạng không phải object là sai cấu trúc (trả nil). Định dạng thiếu `mimeType` bị bỏ qua.
    private static func audioCounts(in entries: [Any], now: Date) -> (StreamProbeAudioCounts, URL?)? {
        var counts = StreamProbeAudioCounts()
        var best: (bitrate: Int, url: URL)?
        for entry in entries {
            guard let format = entry as? [String: Any] else { return nil }
            guard let mime = format["mimeType"] as? String, mime.hasPrefix("audio/") else { continue }
            let directURL = (format["url"] as? String).flatMap(URL.init(string:))
                .flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }
            let isCipher = directURL == nil && (format["signatureCipher"] is String || format["cipher"] is String)
            switch (mime.hasPrefix("audio/mp4"), mime.hasPrefix("audio/webm"), directURL != nil, isCipher) {
            case (true, _, true, _): counts.mp4Direct += 1
            case (true, _, false, true): counts.mp4Cipher += 1
            case (_, true, true, _): counts.webmDirect += 1
            case (_, true, false, true): counts.webmCipher += 1
            default: counts.otherAudio += 1
            }
            guard let directURL else { continue }
            let query = URLComponents(url: directURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if query.contains(where: { $0.name == "n" }) { counts.directWithN += 1 }
            if mime.hasPrefix("audio/mp4") {
                let bitrate = format["bitrate"] as? Int ?? 0
                if best == nil || bitrate > (best?.bitrate ?? 0) { best = (bitrate, directURL) }
            }
        }
        counts.secondsUntilExpiry = best.flatMap { Self.secondsUntilExpiry(of: $0.url, now: now) }
        return (counts, best?.url)
    }

    /// Trường thiếu là mảng rỗng; có mặt mà không phải mảng là sai cấu trúc (trả nil).
    private static func optionalArray(_ value: Any?) -> [Any]? {
        guard let value else { return [] }
        return value as? [Any]
    }

    /// Đọc `expire` từ query hoặc từ đoạn đường dẫn `/expire/<giây>/`.
    static func secondsUntilExpiry(of url: URL, now: Date) -> Int? {
        var raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "expire" })?.value
        if raw == nil {
            let parts = url.pathComponents
            if let index = parts.firstIndex(of: "expire"), parts.indices.contains(index + 1) {
                raw = parts[index + 1]
            }
        }
        // Chỉ nhận số nguyên trong khoảng hợp lý để không tràn số với giá trị lạ như "inf" hay "1e400".
        guard let raw, let epoch = Int(raw), epoch > 0, epoch < 32_503_680_000 else { return nil }
        return epoch - Int(now.timeIntervalSince1970)
    }
}
#endif
