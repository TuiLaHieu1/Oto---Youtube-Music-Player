import Foundation
import OtoCore
import os

extension YTMusicParsers {
    public struct HomeContinuationPage: Sendable {
        public let sections: [HomeSection]
        public let nextToken: String?
    }

    public static func homeContinuationToken(from data: Data) throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.invalidResponse
        }
        guard let contents = root["contents"] as? [String: Any],
              let column = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = column["tabs"] as? [[String: Any]],
              let tab = tabs.first?["tabRenderer"] as? [String: Any],
              let tabContent = tab["content"] as? [String: Any],
              let sectionList = tabContent["sectionListRenderer"] as? [String: Any] else {
            return nil
        }
        return continuationToken(in: sectionList)
    }

    public static func parseHomeContinuationPage(from data: Data) throws -> HomeContinuationPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.parsingError
        }
        let continuationContents = root["continuationContents"] as? [String: Any]
        guard let sectionList = continuationContents?["sectionListContinuation"] as? [String: Any] else {
            if Self.isEmptyHomeContinuation(root) { return HomeContinuationPage(sections: [], nextToken: nil) }
            Self.logUnrecognizedHomePage(root)
            throw YTMusicError.parsingError
        }
        let rawShelves = sectionList["contents"] as? [[String: Any]]
            ?? sectionList["items"] as? [[String: Any]] ?? []
        let sections = rawShelves.enumerated().compactMap { index, container -> HomeSection? in
            if var speedDial = container["musicSpeedDialShelfRenderer"] as? [String: Any]
                ?? container["musicSpeedDialShelfModel"] as? [String: Any] {
                speedDial["_isSpeedDialRenderer"] = true
                return Self.parseServerHomeShelf(speedDial, id: "continuation_\(index)")
            }
            guard let shelf = container["musicCarouselShelfRenderer"] as? [String: Any]
                    ?? container["musicShelfRenderer"] as? [String: Any] else { return nil }
            return Self.parseServerHomeShelf(shelf, id: "continuation_\(index)")
        }
        return HomeContinuationPage(sections: sections, nextToken: continuationToken(in: sectionList))
    }

    private static func logUnrecognizedHomePage(_ root: [String: Any]) {
        let allowedKeys = [
            "contents", "continuationContents", "alerts", "onResponseReceivedActions",
            "onResponseReceivedCommands", "onResponseReceivedEndpoints"
        ]
        let visibleKeys = allowedKeys.filter { root[$0] != nil }.joined(separator: ",")
        let column = (root["contents"] as? [String: Any])?["singleColumnBrowseResultsRenderer"] as? [String: Any]
        let tabs = column?["tabs"] as? [[String: Any]] ?? []
        let populatedTabs = tabs.filter { ($0["tabRenderer"] as? [String: Any])?["content"] != nil }.count
        let summary = "keys=\(visibleKeys) tabs=\(tabs.count) populated=\(populatedTabs)"
        Logger(subsystem: "com.oto.music", category: "HomeContinuation")
            .warning("Home continuation schema \(summary, privacy: .public)")
    }

    private static func isEmptyHomeContinuation(_ root: [String: Any]) -> Bool {
        // Dạng cuối feed quan sát được trong probe công khai có một tab rỗng.
        guard Set(root.keys).isSubset(of: ["contents", "responseContext", "trackingParams"]),
              let contents = root["contents"] as? [String: Any],
              let column = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = column["tabs"] as? [[String: Any]], tabs.count == 1,
              let tab = tabs.first?["tabRenderer"] as? [String: Any] else { return false }
        return tab["content"] == nil
    }

    private static func continuationToken(in sectionList: [String: Any]) -> String? {
        guard let continuations = sectionList["continuations"] as? [[String: Any]],
              let first = continuations.first,
              let next = first["nextContinuationData"] as? [String: Any],
              let token = next["continuation"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }
}
