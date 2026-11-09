import Foundation
import CryptoKit
import OtoCore
import os

/// Lỗi phát sinh trong quá trình tương tác với YouTube Music Innertube API.
public enum YTMusicError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case invalidResponse
    case parsingError

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Đường dẫn API không hợp lệ."
        case .networkError(let msg): return "Lỗi kết nối mạng: \(msg)"
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

    public init(session: URLSession = .shared) {
        self.session = session
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

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw YTMusicError.invalidResponse
            }
            return YTMusicParsers.parseSongs(from: data)
        } catch {
            logger.error("Lỗi gọi Innertube search API: \(error.localizedDescription)")
            throw YTMusicError.networkError(error.localizedDescription)
        }
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

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw YTMusicError.invalidResponse
            }
            return YTMusicParsers.parseHomeSections(from: data)
        } catch {
            logger.error("Lỗi gọi Innertube browse API: \(error.localizedDescription)")
            throw YTMusicError.networkError(error.localizedDescription)
        }
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

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw YTMusicError.invalidResponse
            }
            return YTMusicParsers.parsePlaylistOrShelfSongs(from: data)
        } catch {
            logger.error("Lỗi gọi Innertube liked songs API: \(error.localizedDescription)")
            throw YTMusicError.networkError(error.localizedDescription)
        }
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
}
