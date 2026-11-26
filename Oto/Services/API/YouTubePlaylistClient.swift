import Foundation

struct YouTubePlaylistClient: Sendable {
    struct EditablePlaylist: Decodable, Identifiable, Sendable {
        struct Snippet: Decodable, Sendable { let title: String }
        let id: String
        let snippet: Snippet
    }

    struct Page: Decodable, Sendable {
        let items: [EditablePlaylist]
        let nextPageToken: String?
    }

    enum Failure: Error, Equatable {
        case invalidRequest
        case invalidResponse
        case sessionExpired
        case permissionDenied
        case quotaExceeded
        case playlistUnavailable
        case rejected(Int)
    }

    private struct ErrorEnvelope: Decodable {
        struct Details: Decodable {
            struct Entry: Decodable { let reason: String }
            let errors: [Entry]?
        }
        let error: Details
    }

    private struct NewItem: Encodable {
        struct Snippet: Encodable {
            struct Resource: Encodable {
                let kind = "youtube#video"
                let videoId: String
            }
            let playlistId: String
            let resourceId: Resource
        }
        let snippet: Snippet
    }

    private struct InsertResult: Decodable { let id: String }
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }) {
        self.transport = transport
    }

    func ownedPlaylists(accessToken: String, pageToken: String? = nil) async throws -> Page {
        var query = [
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50")
        ]
        if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        let request = try Self.request(path: "playlists", accessToken: accessToken, query: query)
        return try await self.send(request, decoding: Page.self)
    }

    func add(videoID: String, to playlistID: String, accessToken: String) async throws {
        guard videoID.utf8.count == 11, Self.isResourceID(videoID), Self.isResourceID(playlistID) else {
            throw Failure.invalidRequest
        }
        var request = try Self.request(path: "playlistItems", accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            NewItem(snippet: .init(playlistId: playlistID, resourceId: .init(videoId: videoID)))
        )
        let inserted = try await self.send(request, decoding: InsertResult.self)
        guard !inserted.id.isEmpty else { throw Failure.invalidResponse }
    }

    private static func isResourceID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    private static func request(path: String, accessToken: String, query: [URLQueryItem] = []) throws -> URLRequest {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "www.googleapis.com"
        url.path = "/youtube/v3/" + path
        url.queryItems = [URLQueryItem(name: "part", value: "snippet")] + query
        guard !accessToken.isEmpty, let endpoint = url.url else { throw Failure.invalidRequest }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, decoding type: T.Type) async throws -> T {
        let (data, response) = try await self.transport(request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let reason = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.errors?.first?.reason
            switch (response.statusCode, reason) {
            case (401, _): throw Failure.sessionExpired
            case (429, _), (_, "quotaExceeded"), (_, "dailyLimitExceeded"): throw Failure.quotaExceeded
            case (404, _), (_, "playlistOperationUnsupported"): throw Failure.playlistUnavailable
            case (403, _): throw Failure.permissionDenied
            default: throw Failure.rejected(response.statusCode)
            }
        }
        guard let result = try? JSONDecoder().decode(type, from: data) else { throw Failure.invalidResponse }
        return result
    }
}
