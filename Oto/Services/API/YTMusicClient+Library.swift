import Foundation
import OtoCore

enum LibraryCollection: String, Sendable {
    case albums = "FEmusic_liked_albums"
    case artists = "FEmusic_library_corpus_artists"

    var idPrefix: String { self == .albums ? "MPRE" : "UC" }
}

struct LibraryCollectionPage: Sendable {
    var items: [Playlist] = []
    var nextToken: String?
}

extension YTMusicClient {
    func fetchLibraryCollection(_ collection: LibraryCollection, token: String?) async throws -> LibraryCollectionPage {
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false")
        if let token {
            components?.queryItems?.append(contentsOf: [
                URLQueryItem(name: "ctoken", value: token),
                URLQueryItem(name: "continuation", value: token)
            ])
        }
        guard let url = components?.url else { throw YTMusicError.invalidURL }
        var request = self.makeBaseRequest(url: url)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": self.clientContext, "browseId": collection.rawValue
        ])
        let data = try await self.perform(request, operation: "library-collection")
        return try YTMusicParsers.parseLibraryCollection(data, collection: collection, continued: token != nil)
    }
}

extension YTMusicParsers {
    static func parseLibraryCollection(
        _ data: Data, collection: LibraryCollection, continued: Bool
    ) throws -> LibraryCollectionPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        let albums = collection == .albums
        let containers: [[String: Any]]
        if continued {
            let continuations = root["continuationContents"] as? [String: Any]
            guard let shelf = continuations?[albums ? "gridContinuation" : "musicShelfContinuation"]
                as? [String: Any] else { throw YTMusicError.parsingError }
            containers = [shelf]
        } else {
            guard let contents = root["contents"] as? [String: Any],
                  let column = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
                  let tabs = column["tabs"] as? [[String: Any]],
                  let tab = tabs.first?["tabRenderer"] as? [String: Any],
                  let content = tab["content"] as? [String: Any],
                  let sections = content["sectionListRenderer"] as? [String: Any] else {
                throw YTMusicError.parsingError
            }
            containers = Self.collectRenderers(named: albums ? "gridRenderer" : "musicShelfRenderer", in: sections)
            if containers.isEmpty,
               Self.collectRenderers(named: "musicEmptyStateRenderer", in: sections).isEmpty {
                throw YTMusicError.parsingError
            }
        }

        let rows = Self.collectRenderers(
            named: albums ? "musicTwoRowItemRenderer" : "musicResponsiveListItemRenderer", in: containers
        )
        var seen = Set<String>()
        let items = rows.compactMap { Self.libraryCollectionItem($0, collection: collection) }
            .filter { seen.insert($0.id).inserted }
        if !rows.isEmpty, items.isEmpty { throw YTMusicError.parsingError }
        let token = Self.collectRenderers(named: "nextContinuationData", in: containers)
            .compactMap { $0["continuation"] as? String }.first { !$0.isEmpty }
        return LibraryCollectionPage(items: items, nextToken: token)
    }

    private static func libraryCollectionItem(
        _ row: [String: Any], collection: LibraryCollection
    ) -> Playlist? {
        let column = Self.collectRenderers(
            named: "musicResponsiveListItemFlexColumnRenderer", in: row["flexColumns"] ?? []
        ).first
        let title = (row["title"] as? [String: Any]) ?? (column?["text"] as? [String: Any])
        let firstRun = (title?["runs"] as? [[String: Any]])?.first
        let nav = (row["navigationEndpoint"] as? [String: Any])
            ?? (firstRun?["navigationEndpoint"] as? [String: Any])
        let browse = nav?["browseEndpoint"] as? [String: Any]
        guard let id = browse?["browseId"] as? String, id.hasPrefix(collection.idPrefix),
              let name = firstRun?["text"] as? String, !name.isEmpty else { return nil }
        let thumbnail = (row["thumbnailRenderer"] as? [String: Any]) ?? (row["thumbnail"] as? [String: Any])
        return Playlist(id: id, title: name, subtitle: "", artworkURL: Self.extractThumbnailURL(from: thumbnail))
    }
}
