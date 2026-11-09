import Foundation
import SwiftUI
import OtoCore

/// ViewModel quản lý việc nạp và đồng bộ lời bài hát thời gian thực.
@MainActor
@Observable
public final class LyricsViewModel {
    public var currentDocument: LyricsDocument = LyricsDocument(type: .none)
    public var activeLineIndex: Int?
    public var isLoading: Bool = false
    public var userIsScrolling: Bool = false

    private let lyricsService: MultiSourceLyricsService
    private var currentSongID: String?
    private var scrollResetTask: Task<Void, Never>?
    private var fetchLyricsTask: Task<Void, Never>?

    public init(lyricsService: MultiSourceLyricsService = MultiSourceLyricsService()) {
        self.lyricsService = lyricsService
    }

    /// Tải lời bài hát khi đổi bài, tự động hủy bỏ yêu cầu đang xử lý của bài trước.
    public func loadLyrics(for song: Song) {
        if currentSongID == song.id && currentDocument.type != .none {
            return
        }

        fetchLyricsTask?.cancel()
        currentSongID = song.id
        isLoading = true
        currentDocument = LyricsDocument(type: .none)
        activeLineIndex = nil

        fetchLyricsTask = Task {
            let doc = await lyricsService.resolveLyrics(for: song)
            guard !Task.isCancelled, currentSongID == song.id else { return }
            self.currentDocument = doc
            self.isLoading = false
        }
    }

    /// Cập nhật vị trí phát nhạc để làm nổi bật dòng lời tương ứng.
    public func updatePosition(_ position: TimeInterval) {
        guard currentDocument.type == .synced else { return }
        let newIndex = currentDocument.currentLineIndex(at: position)
        if newIndex != activeLineIndex {
            activeLineIndex = newIndex
        }
    }

    /// Ghi nhận khi người dùng chủ động vuốt xem lời (tạm dừng auto-scroll trong 4 giây).
    public func userDidScroll() {
        userIsScrolling = true
        scrollResetTask?.cancel()
        scrollResetTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4s
            self.userIsScrolling = false
        }
    }
}
