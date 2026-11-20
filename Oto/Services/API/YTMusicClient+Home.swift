import Foundation

extension YTMusicClient {
    public func fetchHomeContinuation(token: String) async throws -> YTMusicParsers.HomeContinuationPage {
        guard !token.isEmpty, token.count < 8_192,
              var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/browse") else {
            throw YTMusicError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "prettyPrint", value: "false"),
            URLQueryItem(name: "ctoken", value: token),
            URLQueryItem(name: "continuation", value: token)
        ]
        guard let url = components.url else { throw YTMusicError.invalidURL }
        var request = makeBaseRequest(url: url)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": clientContext,
            "browseId": "FEmusic_home"
        ])
        let data = try await perform(request, operation: "home-continuation")
        return try YTMusicParsers.parseHomeContinuationPage(from: data)
    }
}
