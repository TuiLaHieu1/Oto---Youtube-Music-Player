import Foundation
import SwiftUI
import OtoCore

/// Phạm vi tìm kiếm âm nhạc.
public enum SearchScope: String, CaseIterable, Sendable {
    case all = "Tất cả"
    case songs = "Bài hát"
    case videos = "Video"
    case albums = "Album"
    case artists = "Nghệ sĩ"
    case playlists = "Playlist"
}

/// ViewModel quản lý tìm kiếm bài hát trực tiếp qua YouTube Music API trên MainActor.
@MainActor
@Observable
public final class SearchViewModel {
    public var query: String = "" {
        didSet {
            handleQueryChange(query)
        }
    }
    public var selectedScope: SearchScope = .all {
        didSet {
            if selectedScope != oldValue {
                handleQueryChange(query)
            }
        }
    }
    var searchResults = MusicSearchPage()
    private(set) var recentQueries: [String] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    private var loadedTokens = Set<String>()
    private var currentSearchTask: Task<Void, Never>?
    private let client: YTMusicClient

    public init(client: YTMusicClient = .shared) {
        self.client = client
    }

    /// Xử lý truy vấn tìm kiếm với cơ chế debounce 350ms chống quá tải mạng.
    private func handleQueryChange(_ newQuery: String) {
        currentSearchTask?.cancel()
        isLoadingMore = false
        loadMoreFailed = false
        loadedTokens.removeAll()

        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = MusicSearchPage()
            isLoading = false
            errorMessage = nil
            return
        }

        let scope = selectedScope
        searchResults = MusicSearchPage()
        isLoading = true
        errorMessage = nil
        currentSearchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
            guard !Task.isCancelled else { return }

            isLoading = true
            errorMessage = nil

            do {
                let results = try await client.searchMusic(query: trimmed, scope: scope)
                guard !Task.isCancelled else { return }
                self.searchResults = results
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func loadMore() {
        guard !isLoading, !isLoadingMore, let token = searchResults.nextToken else { return }
        let scope = selectedScope
        let query = self.query
        isLoadingMore = true
        loadMoreFailed = false
        currentSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.client.searchMusic(query: query, scope: scope, continuation: token)
                guard !Task.isCancelled else { return }
                var seen = Set(self.searchResults.results.map(\.id))
                self.searchResults.results.append(contentsOf: page.results.filter { seen.insert($0.id).inserted })
                self.loadedTokens.insert(token)
                self.searchResults.nextToken = page.nextToken.flatMap { self.loadedTokens.contains($0) ? nil : $0 }
            } catch {
                guard !Task.isCancelled else { return }
                self.loadMoreFailed = true
            }
            self.isLoadingMore = false
        }
    }

    func recordCurrentQuery() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        recentQueries.removeAll { $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        recentQueries.insert(term, at: 0)
        recentQueries = Array(recentQueries.prefix(6))
    }

    func clearRecentQueries() {
        recentQueries.removeAll()
    }

    /// Làm sạch ô tìm kiếm và kết quả.
    public func clear() {
        currentSearchTask?.cancel()
        query = ""
        searchResults = MusicSearchPage()
        isLoading = false
        errorMessage = nil
    }

    /// Thử lại truy vấn hiện tại sau lỗi mạng mà không buộc người dùng sửa nội dung ô tìm kiếm.
    public func retry() {
        handleQueryChange(query)
    }
}
