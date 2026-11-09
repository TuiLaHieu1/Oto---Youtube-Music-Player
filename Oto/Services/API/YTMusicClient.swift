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

        // Đính kèm xác thực SAPISIDHASH nếu người dùng đã đăng nhập
        attachAuthHeaders(to: &request)

        let bodyPayload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20241014.01.00",
                    "hl": "vi",
                    "gl": "VN"
                ]
            ],
            "query": trimmed,
            "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF" // Lọc chỉ lấy bài hát (Songs only)
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyPayload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw YTMusicError.invalidResponse
            }
            return parseSongs(from: data)
        } catch {
            logger.error("Lỗi gọi Innertube search API: \(error.localizedDescription)")
            throw YTMusicError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Auth Helpers

    private func attachAuthHeaders(to request: inout URLRequest) {
        let cookies = CookieStorage.shared.loadCookies()
        guard !cookies.isEmpty else { return }

        // Đính kèm Cookie header
        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        // Tạo chữ ký SAPISIDHASH nếu có cookie SAPISID hoặc __Secure-3PAPISID
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

    // MARK: - Response Parser

    private func parseSongs(from data: Data) -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any] else {
            return []
        }

        var results: [Song] = []

        // Tìm sectionListRenderer từ tabbedSearchResultsRenderer hoặc trực tiếp
        let sectionLists = extractSectionLists(from: contents)
        for section in sectionLists {
            guard let shelfContents = section["contents"] as? [[String: Any]] else { continue }
            for container in shelfContents {
                guard let musicShelf = container["musicShelfRenderer"] as? [String: Any],
                      let items = musicShelf["contents"] as? [[String: Any]] else {
                    continue
                }

                for item in items {
                    guard let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
                          let song = parseResponsiveListItem(renderer) else {
                        continue
                    }
                    results.append(song)
                }
            }
        }

        logger.info("Đã phân tích thành công \(results.count) bài hát từ kết quả tìm kiếm.")
        return results
    }

    private func extractSectionLists(from contents: [String: Any]) -> [[String: Any]] {
        if let direct = contents["sectionListRenderer"] as? [String: Any] {
            return [direct]
        }
        if let tabbed = contents["tabbedSearchResultsRenderer"] as? [String: Any],
           let tabs = tabbed["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionList = tabContent["sectionListRenderer"] as? [String: Any] {
            return [sectionList]
        }
        return []
    }

    private func parseResponsiveListItem(_ renderer: [String: Any]) -> Song? {
        guard let flexColumns = renderer["flexColumns"] as? [[String: Any]], !flexColumns.isEmpty else {
            return nil
        }

        // 1. Video ID
        var videoId: String?
        if let playlistItemData = renderer["playlistItemData"] as? [String: Any] {
            videoId = playlistItemData["videoId"] as? String
        }

        // 2. Title từ flex column 0
        let col0 = flexColumns[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        let col0Text = col0?["text"] as? [String: Any]
        let col0Runs = col0Text?["runs"] as? [[String: Any]]
        let title = col0Runs?.first?["text"] as? String ?? ""

        if videoId == nil, let runs = col0Runs, let firstRun = runs.first {
            if let nav = firstRun["navigationEndpoint"] as? [String: Any],
               let watch = nav["watchEndpoint"] as? [String: Any] {
                videoId = watch["videoId"] as? String
            }
        }

        guard let id = videoId, !id.isEmpty, !title.isEmpty else { return nil }

        // 3. Artist & Album từ flex column 1
        var artist = "Nhiều nghệ sĩ"
        var album: String?
        var duration: TimeInterval = 0

        if flexColumns.count > 1 {
            let col1 = flexColumns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
            let col1Text = col1?["text"] as? [String: Any]
            let col1Runs = col1Text?["runs"] as? [[String: Any]] ?? []

            if !col1Runs.isEmpty {
                artist = col1Runs[0]["text"] as? String ?? "Nhiều nghệ sĩ"
            }
            if col1Runs.count >= 3 {
                album = col1Runs[2]["text"] as? String
            }
            if let lastText = col1Runs.last?["text"] as? String, lastText.contains(":") {
                duration = parseDurationString(lastText)
            }
        }

        // 4. Artwork URL
        var artworkURL: URL?
        if let thumbnail = renderer["thumbnail"] as? [String: Any],
           let musicThumb = thumbnail["musicThumbnailRenderer"] as? [String: Any],
           let thumbObj = musicThumb["thumbnail"] as? [String: Any],
           let thumbs = thumbObj["thumbnails"] as? [[String: Any]],
           let lastThumb = thumbs.last,
           let urlStr = lastThumb["url"] as? String {
            artworkURL = URL(string: urlStr)
        }

        return Song(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: artworkURL
        )
    }

    private func parseDurationString(_ text: String) -> TimeInterval {
        let parts = text.components(separatedBy: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 {
            return (parts[0] * 60) + parts[1]
        } else if parts.count == 3 {
            return (parts[0] * 3600) + (parts[1] * 60) + parts[2]
        }
        return 0
    }
}
