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

    private let logger = Logger(subsystem: "com.oto.music", category: "LibraryViewModel")
    private let client: YTMusicClient

    public init(client: YTMusicClient = .shared) {
        self.client = client
        updateCacheSize()
        SessionStore.shared.registerResetHandler { [weak self] in
            self?.likedSongs = []
            self?.playlists = []
        }
    }

    /// Tải danh sách bài hát đã thích nếu người dùng đã đăng nhập.
    public func loadLikedSongs() async {
        guard CookieStorage.shared.hasValidSession else {
            likedSongs = []
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let songs = try await client.fetchLikedSongs()
            likedSongs = songs
            isLoading = false
        } catch is CancellationError {
            // Sign-out hoặc view lifecycle đã hủy request; giữ trạng thái sạch.
            likedSongs = []
            isLoading = false
        } catch {
            logger.error("Lỗi tải bài hát đã thích: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Tải danh sách phát cá nhân của người dùng từ YouTube Music.
    public func loadPlaylists() async {
        guard CookieStorage.shared.hasValidSession else {
            playlists = []
            return
        }

        do {
            let list = try await client.fetchLibraryPlaylists()
            self.playlists = list
        } catch is CancellationError {
            playlists = []
        } catch {
            logger.error("Lỗi tải danh sách phát: \(error.localizedDescription)")
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
