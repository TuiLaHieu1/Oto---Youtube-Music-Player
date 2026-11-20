import Foundation

extension YTMusicClient {
    public func fetchArtistDetail(browseId: String) async throws -> YTMusicParsers.ArtistDetail {
        let trimmed = browseId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("UC"),
              let url = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }
        var request = makeBaseRequest(url: url)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": clientContext,
            "browseId": trimmed
        ])
        let data = try await perform(request, operation: "artist-detail")
        return try YTMusicParsers.parseArtistDetail(browseId: trimmed, from: data)
    }

    func fetchArtistSongs(
        endpoint: YTMusicParsers.ArtistSongsEndpoint,
        continuation: String?
    ) async throws -> YTMusicParsers.ArtistSongsPage {
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false") else {
            throw YTMusicError.invalidURL
        }
        var body: [String: Any] = ["context": self.clientContext]
        if let continuation {
            body["continuation"] = continuation
        } else {
            body["browseId"] = endpoint.browseId
            body["params"] = endpoint.params
        }
        var request = self.makeBaseRequest(url: url)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await self.perform(request, operation: "artist-songs")
        return try YTMusicParsers.parseArtistSongsPage(from: data, isContinuation: continuation != nil)
    }
}
