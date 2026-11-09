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
            return parseSongs(from: data)
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
            return parseHomeSections(from: data)
        } catch {
            logger.error("Lỗi gọi Innertube browse API: \(error.localizedDescription)")
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

    // MARK: - Home Parser

    private func parseHomeSections(from data: Data) -> (quickPicks: [Song], listenAgain: [Song]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any],
              let browseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = browseResults["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionList["contents"] as? [[String: Any]] else {
            return ([], [])
        }

        var allSongs: [Song] = []
        for section in sectionContents {
            if let carousel = section["musicCarouselShelfRenderer"] as? [String: Any],
               let items = carousel["contents"] as? [[String: Any]] {
                for item in items {
                    if let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any],
                       let song = parseResponsiveListItem(renderer) {
                        allSongs.append(song)
                    } else if let renderer = item["musicTwoRowItemRenderer"] as? [String: Any],
                              let song = parseTwoRowItem(renderer) {
                        allSongs.append(song)
                    }
                }
            }
        }

        let half = allSongs.count / 2
        let quick = Array(allSongs.prefix(max(4, half)))
        let listen = Array(allSongs.dropFirst(max(4, half)))
        return (quick, listen)
    }

    // MARK: - Search Parser

    private func parseSongs(from data: Data) -> [Song] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any] else {
            return []
        }

        var results: [Song] = []
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

        var videoId: String?
        if let playlistItemData = renderer["playlistItemData"] as? [String: Any] {
            videoId = playlistItemData["videoId"] as? String
        }

        let col0 = flexColumns[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        let col0Runs = (col0?["text"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = col0Runs?.first?["text"] as? String ?? ""

        if videoId == nil, let runs = col0Runs, let firstRun = runs.first {
            let nav = firstRun["navigationEndpoint"] as? [String: Any]
            let watch = nav?["watchEndpoint"] as? [String: Any]
            videoId = watch?["videoId"] as? String
        }

        guard let id = videoId, !id.isEmpty, !title.isEmpty else { return nil }

        var artist = "Nhiều nghệ sĩ"
        var album: String?
        var duration: TimeInterval = 0

        if flexColumns.count > 1 {
            let col1 = flexColumns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
            let col1Runs = (col1?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []

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

        return Song(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: extractThumbnailURL(from: renderer["thumbnail"] as? [String: Any])
        )
    }

    private func parseTwoRowItem(_ renderer: [String: Any]) -> Song? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let watch = nav?["watchEndpoint"] as? [String: Any]
        guard let videoId = watch?["videoId"] as? String, !videoId.isEmpty else {
            return nil
        }

        let titleRuns = (renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = titleRuns?.first?["text"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        let subRuns = (renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]
        let artist = subRuns?.first?["text"] as? String ?? "Nhiều nghệ sĩ"

        return Song(
            id: videoId,
            title: title,
            artist: artist,
            album: nil,
            duration: 0,
            artworkURL: extractThumbnailURL(from: renderer["thumbnailRenderer"] as? [String: Any])
        )
    }

    private func extractThumbnailURL(from container: [String: Any]?) -> URL? {
        guard let container else { return nil }
        let musicThumb = container["musicThumbnailRenderer"] as? [String: Any]
        let thumbObj = (musicThumb?["thumbnail"] as? [String: Any]) ?? (container["thumbnail"] as? [String: Any])
        let thumbs = thumbObj?["thumbnails"] as? [[String: Any]]
        guard let lastThumb = thumbs?.last,
              let urlStr = lastThumb["url"] as? String else {
            return nil
        }
        return URL(string: urlStr)
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
