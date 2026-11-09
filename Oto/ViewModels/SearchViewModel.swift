import Foundation
import SwiftUI
import OtoCore

/// ViewModel quản lý tìm kiếm bài hát trực tiếp qua YouTube Music API trên MainActor.
@MainActor
@Observable
public final class SearchViewModel {
    public var query: String = "" {
        didSet {
            handleQueryChange(query)
        }
    }
    public var searchResults: [Song] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private var currentSearchTask: Task<Void, Never>?
    private let client: YTMusicClient

    public init(client: YTMusicClient = .shared) {
        self.client = client
    }

    /// Xử lý truy vấn tìm kiếm với cơ chế debounce 350ms chống quá tải mạng.
    private func handleQueryChange(_ newQuery: String) {
        currentSearchTask?.cancel()

        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isLoading = false
            errorMessage = nil
            return
        }

        currentSearchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
            guard !Task.isCancelled else { return }

            isLoading = true
            errorMessage = nil

            do {
                let songs = try await client.searchSongs(query: trimmed)
                guard !Task.isCancelled else { return }
                self.searchResults = songs
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// Làm sạch ô tìm kiếm và kết quả.
    public func clear() {
        currentSearchTask?.cancel()
        query = ""
        searchResults = []
        isLoading = false
        errorMessage = nil
    }

    /// Thử lại truy vấn hiện tại sau lỗi mạng mà không buộc người dùng sửa nội dung ô tìm kiếm.
    public func retry() {
        handleQueryChange(query)
    }
}
