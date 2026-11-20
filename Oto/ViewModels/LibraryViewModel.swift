import Foundation
import Observation
import OtoCore
import os

/// Quản lý dữ liệu Thư viện và danh sách bài hát yêu thích.
@MainActor
@Observable
public final class LibraryViewModel {
    public var likedSongs: [Song] = []
    public var playlists: [Playlist] = []
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var cacheSizeString: String = "0 KB"

    private(set) var collections: [LibraryCollection: LibraryCollectionPage] = [:]
    private(set) var loadingCollections = Set<LibraryCollection>()
    private(set) var failedCollections = Set<LibraryCollection>()
    private var collectionRevision = UUID()
    private var usedCollectionTokens: [LibraryCollection: Set<String>] = [:]

    private let logger = Logger(subsystem: "com.oto.music", category: "LibraryViewModel")
    private let client: YTMusicClient

    public init(client: YTMusicClient = .shared) {
        self.client = client
        updateCacheSize()
        SessionStore.shared.registerResetHandler { [weak self] in self?.resetLibrary() }
        SessionStore.shared.registerSignInHandler { [weak self] in self?.resetLibrary() }
    }

    private func resetLibrary() {
        collectionRevision = UUID()
        likedSongs = []
        playlists = []
        collections = [:]
        loadingCollections = []
        failedCollections = []
        usedCollectionTokens = [:]
        isLoading = false
        errorMessage = nil
    }

    /// Tải danh sách bài hát đã thích nếu người dùng đã đăng nhập.
    public func loadLikedSongs() async {
        guard CookieStorage.shared.hasValidSession else {
            likedSongs = []
            return
        }

        let revision = collectionRevision
        let generation = SessionStore.shared.sessionGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if revision == collectionRevision, generation == SessionStore.shared.sessionGeneration {
                isLoading = false
            }
        }

        do {
            let songs = try await client.fetchLikedSongs()
            guard !Task.isCancelled, revision == collectionRevision,
                  generation == SessionStore.shared.sessionGeneration else { return }
            likedSongs = songs
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, revision == collectionRevision,
                  generation == SessionStore.shared.sessionGeneration else { return }
            logger.error("Lỗi tải bài hát đã thích: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Tải danh sách phát cá nhân của người dùng từ YouTube Music.
    public func loadPlaylists() async {
        guard CookieStorage.shared.hasValidSession else {
            playlists = []
            return
        }

        let revision = collectionRevision
        let generation = SessionStore.shared.sessionGeneration
        do {
            let list = try await client.fetchLibraryPlaylists()
            guard !Task.isCancelled, revision == collectionRevision,
                  generation == SessionStore.shared.sessionGeneration else { return }
            self.playlists = list
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, revision == collectionRevision else { return }
            logger.error("Lỗi tải danh sách phát: \(error.localizedDescription)")
        }
    }

    func loadCollection(_ kind: LibraryCollection, loadMore: Bool = false) async {
        guard CookieStorage.shared.hasValidSession, loadingCollections.insert(kind).inserted else { return }
        let revision = collectionRevision
        let generation = SessionStore.shared.sessionGeneration
        let token = loadMore ? collections[kind]?.nextToken : nil
        if !loadMore { usedCollectionTokens[kind] = [] }
        failedCollections.remove(kind)
        defer {
            if revision == collectionRevision { loadingCollections.remove(kind) }
        }
        do {
            var page = try await client.fetchLibraryCollection(kind, token: token)
            guard !Task.isCancelled, revision == collectionRevision,
                  generation == SessionStore.shared.sessionGeneration,
                  CookieStorage.shared.hasValidSession else { return }
            if let token {
                usedCollectionTokens[kind, default: []].insert(token)
                let previous = collections[kind]?.items ?? []
                var seen = Set(previous.map(\.id))
                page.items = previous + page.items.filter { seen.insert($0.id).inserted }
            }
            if let next = page.nextToken, usedCollectionTokens[kind]?.contains(next) == true {
                page.nextToken = nil
            }
            collections[kind] = page
        } catch {
            if !Task.isCancelled, revision == collectionRevision,
               generation == SessionStore.shared.sessionGeneration {
                failedCollections.insert(kind)
            }
        }
    }

    /// Cập nhật dung lượng bộ nhớ đệm cache trên đĩa ngoài MainActor.
    public func updateCacheSize() {
        Task.detached(priority: .utility) {
            var totalBytes: Int64 = 0

            if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                if let enumerator = FileManager.default.enumerator(
                    at: cacheDir,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                           let fileSize = resourceValues.fileSize {
                            totalBytes += Int64(fileSize)
                        }
                    }
                }
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            let formatted = formatter.string(fromByteCount: totalBytes)

            await MainActor.run { [weak self] in
                self?.cacheSizeString = formatted
            }
        }
    }

    /// Xóa toàn bộ bộ nhớ đệm ứng dụng.
    public func clearAllCache() {
        Task {
            await HomeCache.shared.clear()
            URLCache.shared.removeAllCachedResponses()
            updateCacheSize()
        }
    }
}
