import Foundation
import CryptoKit
import OtoCore
import os

/// Lỗi phát sinh trong quá trình tương tác với YouTube Music Innertube API.
public enum YTMusicError: Error, LocalizedError {
    case invalidURL
    case transport(String)
    case authenticationExpired
    case permissionDenied
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case invalidResponse
    case parsingError

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Đường dẫn API không hợp lệ."
        case .transport(let message): return "Lỗi kết nối mạng: \(message)"
        case .authenticationExpired: return "Phiên đăng nhập đã hết hạn."
        case .permissionDenied: return "Tài khoản không có quyền truy cập nội dung này."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "YouTube Music đang giới hạn yêu cầu. Thử lại sau \(Int(retryAfter)) giây."
            }
            return "YouTube Music đang giới hạn yêu cầu. Vui lòng thử lại sau."
        case .serverError: return "YouTube Music đang tạm thời gặp sự cố."
        case .invalidResponse: return "Máy chủ trả về phản hồi không hợp lệ."
        case .parsingError: return "Không thể phân tích dữ liệu bài hát."
        }
    }
}

/// Client giao tiếp trực tiếp với Innertube JSON API của YouTube Music (không dùng WebView để cào dữ liệu).
public final class YTMusicClient: Sendable {
    public static let shared = YTMusicClient()
    private let logger = Logger(subsystem: "com.oto.music", category: "YTMusicClient")
    private let session: URLSession
    private let sessionFence = SessionFence()

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15.0
            config.timeoutIntervalForResource = 30.0
            self.session = URLSession(configuration: config)
        }
    }

    /// Tìm kiếm danh sách bài hát theo từ khóa trên YouTube Music.
    public func searchSongs(query: String) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }

        var request = makeBaseRequest(url: url)
        let bodyPayload: [String: Any] = [
            "context": clientContext,
            "query": trimmed,
            "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF" // Lọc chỉ lấy bài hát (Songs only)
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyPayload)

        let data = try await perform(request, operation: "search")
        return try YTMusicParsers.parseSongs(from: data)
    }

    /// Nạp danh mục trang chủ (Home feed) từ YouTube Music.
    public func fetchHomeFeed() async throws -> (quickPicks: [Song], listenAgain: [Song]) {
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }

        var request = makeBaseRequest(url: url)
        let bodyPayload: [String: Any] = [
            "context": clientContext,
            "browseId": "FEmusic_home"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyPayload)

        let data = try await perform(request, operation: "home")
        return try YTMusicParsers.parseHomeSections(from: data)
    }

    /// Nạp danh sách bài hát đã thích (Liked Songs) từ tài khoản YouTube Music.
    public func fetchLikedSongs() async throws -> [Song] {
        guard CookieStorage.shared.hasValidSession else {
            return []
        }

        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }

        var request = makeBaseRequest(url: url)
        let bodyPayload: [String: Any] = [
            "context": clientContext,
            "browseId": "FEmusic_liked_videos"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyPayload)

        let data = try await perform(request, operation: "liked-songs")
        return try YTMusicParsers.parsePlaylistOrShelfSongs(from: data)
    }

    /// Chặn callback của phiên cũ và hủy request đang chạy trước khi xóa thông tin đăng nhập.
    public func invalidateSession() async {
        await sessionFence.invalidate()
        let tasks = await session.allTasks
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Request Builder

    private var clientContext: [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20241014.01.00",
                "hl": "vi",
                "gl": "VN"
            ]
        ]
    }

    private func makeBaseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        attachAuthHeaders(to: &request)
        return request
    }

    private func attachAuthHeaders(to request: inout URLRequest) {
        let cookies = CookieStorage.shared.loadCookies()
        guard !cookies.isEmpty else { return }

        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        if let sapisidCookie = cookies.first(where: { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" }) {
            let timestamp = Int(Date().timeIntervalSince1970)
            let origin = "https://music.youtube.com"
            let input = "\(timestamp) \(sapisidCookie.value) \(origin)"
            let hash = Insecure.SHA1.hash(data: Data(input.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            request.setValue("SAPISIDHASH \(timestamp)_\(hash)", forHTTPHeaderField: "Authorization")
        }
    }

    private func perform(_ request: URLRequest, operation: String) async throws -> Data {
        let generation = await sessionFence.snapshot()
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard await sessionFence.isCurrent(generation) else {
                throw CancellationError()
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw YTMusicError.invalidResponse
            }
            try validate(httpResponse, operation: operation)
            return data
        } catch is CancellationError {
            logger.info("operation=\(operation, privacy: .public) errorCategory=cancelled")
            throw CancellationError()
        } catch let urlError as URLError {
            logURLError(urlError, operation: operation)
            throw YTMusicError.transport(urlError.localizedDescription)
        } catch let error as YTMusicError {
            throw error
        } catch {
            logger.error("operation=\(operation, privacy: .public) errorCategory=unknown")
            throw YTMusicError.transport(error.localizedDescription)
        }
    }

    private func validate(_ response: HTTPURLResponse, operation: String) throws {
        let code = response.statusCode
        switch code {
        case 200...299:
            return
        case 401:
            logger.error("operation=\(operation, privacy: .public) errorCategory=http statusCode=401")
            throw YTMusicError.authenticationExpired
        case 403:
            logger.error("operation=\(operation, privacy: .public) errorCategory=http statusCode=403")
            throw YTMusicError.permissionDenied
        case 429:
            logger.error("operation=\(operation, privacy: .public) errorCategory=http statusCode=429")
            let retryHeader = response.value(forHTTPHeaderField: "Retry-After")
            throw YTMusicError.rateLimited(retryAfter: Self.retryAfter(from: retryHeader))
        case 500...599:
            logger.error("operation=\(operation, privacy: .public) errorCategory=http statusCode=\(code)")
            throw YTMusicError.serverError(statusCode: code)
        default:
            logger.error("operation=\(operation, privacy: .public) errorCategory=http statusCode=\(code)")
            throw YTMusicError.invalidResponse
        }
    }

    private func logURLError(_ urlError: URLError, operation: String) {
        let category: String
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            category = "offline"
        case .timedOut:
            category = "timeout"
        case .cancelled:
            category = "cancelled"
        default:
            category = "transport"
        }
        let op = operation
        let cat = category
        let code = urlError.errorCode
        logger.error("operation=\(op, privacy: .public) errorCategory=\(cat, privacy: .public) code=\(code)")
    }

    private static func retryAfter(from value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let retryDate = formatter.date(from: value) else { return nil }
        return max(0, retryDate.timeIntervalSinceNow)
    }
}

private actor SessionFence {
    private var generation: UInt = 0

    func snapshot() -> UInt { generation }

    func invalidate() {
        generation &+= 1
    }

    func isCurrent(_ candidate: UInt) -> Bool {
        candidate == generation
    }
}
