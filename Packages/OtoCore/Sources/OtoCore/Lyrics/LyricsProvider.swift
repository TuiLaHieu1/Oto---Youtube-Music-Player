import Foundation

/// Hợp đồng chung cho các nguồn cung cấp lời bài hát.
public protocol LyricsProvider: Sendable {
    var providerName: String { get }
    func fetchLyrics(for song: Song) async throws -> LyricsDocument?
}

/// Nguồn cung cấp lời đồng bộ miễn phí từ LRCLIB.
public final class LRCLibProvider: LyricsProvider {
    public let providerName: String = "LRCLIB"
    private let transport: HTTPTransport
    private let baseURL: URL

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        baseURL: URL = URL(string: "https://lrclib.net")!
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    public func fetchLyrics(for song: Song) async throws -> LyricsDocument? {
        let cleanedTitle = TitleCleaner.clean(song.title)

        // 1. Thử endpoint /api/get trước
        if let doc = try await fetchGetEndpoint(
            title: cleanedTitle,
            artist: song.artist,
            album: song.album,
            duration: song.duration
        ) {
            return doc
        }

        // 2. Dự phòng sang endpoint /api/search
        return try await fetchSearchEndpoint(title: cleanedTitle, artist: song.artist, duration: song.duration)
    }

    private func fetchGetEndpoint(
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval
    ) async throws -> LyricsDocument? {
        let endpointURL = baseURL.appendingPathComponent("api/get")
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let album = album, !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Oto-Music-Player/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return parseResponseData(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func fetchSearchEndpoint(
        title: String,
        artist: String,
        duration: TimeInterval
    ) async throws -> LyricsDocument? {
        let endpointURL = baseURL.appendingPathComponent("api/search")
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let query = "\(title) \(artist)"
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Oto-Music-Player/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let decoder = JSONDecoder()
            guard let items = try? decoder.decode([LRCLibResponse].self, from: data), !items.isEmpty else {
                return nil
            }

            // Lọc ra các kết quả đáp ứng tiêu chuẩn đối sánh tên bài và thời lượng (P1.12)
            let matchingItems = items.filter { item in
                isAcceptableMatch(
                    item: item,
                    expectedTitle: title,
                    expectedArtist: artist,
                    expectedDuration: duration
                )
            }

            guard !matchingItems.isEmpty else {
                return nil
            }

            // Ưu tiên bản có syncedLyrics và sai số thời lượng nhỏ nhất
            let bestMatch = matchingItems.first(where: { item in
                guard let synced = item.syncedLyrics, !synced.isEmpty else { return false }
                if duration > 0, let itemDur = item.duration {
                    return abs(itemDur - duration) <= 5.0
                }
                return true
            }) ?? matchingItems.first

            guard let match = bestMatch else { return nil }
            return makeDocument(from: match)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func isAcceptableMatch(
        item: LRCLibResponse,
        expectedTitle: String,
        expectedArtist: String,
        expectedDuration: TimeInterval
    ) -> Bool {
        guard let trackName = item.trackName else { return false }
        let cleanTrack = TitleCleaner.clean(trackName).lowercased()
        let cleanExpected = TitleCleaner.clean(expectedTitle).lowercased()

        let titleMatches = cleanTrack.contains(cleanExpected) || cleanExpected.contains(cleanTrack)
        guard titleMatches else { return false }

        if expectedDuration > 0, let itemDur = item.duration {
            if abs(itemDur - expectedDuration) > 5.0 {
                return false
            }
        }
        return true
    }

    private func parseResponseData(_ data: Data) -> LyricsDocument? {
        let decoder = JSONDecoder()
        guard let item = try? decoder.decode(LRCLibResponse.self, from: data) else {
            return nil
        }
        return makeDocument(from: item)
    }

    private func makeDocument(from item: LRCLibResponse) -> LyricsDocument? {
        if item.instrumental == true {
            return LyricsDocument(type: .instrumental, source: providerName)
        }
        if let synced = item.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LRCParser.parse(synced, source: providerName)
        }
        if let plain = item.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsDocument(type: .plain, plainLyrics: plain, source: providerName)
        }
        return nil
    }
}

private struct LRCLibResponse: Codable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}
