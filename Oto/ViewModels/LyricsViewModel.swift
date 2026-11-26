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
    private(set) var userOffset: TimeInterval = 0

    private let lyricsService: MultiSourceLyricsService
    private var currentSongID: String?
    private var scrollResetTask: Task<Void, Never>?
    private var fetchLyricsTask: Task<Void, Never>?
    private var latestPosition: TimeInterval = 0
    private var offsetKey: String?

    public init(lyricsService: MultiSourceLyricsService = .otoShared) {
        self.lyricsService = lyricsService
    }

    /// Tải lời bài hát khi đổi bài, tự động hủy bỏ yêu cầu đang xử lý của bài trước.
    public func loadLyrics(for song: Song) {
        if currentSongID == song.id && currentDocument.type != .none {
            return
        }

        fetchLyricsTask?.cancel()
        currentSongID = song.id
        self.offsetKey = nil
        self.userOffset = 0
        self.latestPosition = 0
        isLoading = !song.isLocal
        currentDocument = LyricsDocument(type: .none)
        activeLineIndex = nil
        guard !song.isLocal else { return }

        fetchLyricsTask = Task {
            let doc = await lyricsService.resolveLyrics(for: song)
            guard !Task.isCancelled, currentSongID == song.id else { return }
            if doc.type == .synced {
                let key = "oto.lyrics.offset.v1.\(song.id).\(doc.source)"
                self.offsetKey = key
                let saved = UserDefaults.standard.double(forKey: key)
                self.userOffset = saved.isFinite ? min(10, max(-10, saved)) : 0
            }
            self.currentDocument = doc
            self.isLoading = false
            self.updatePosition(self.latestPosition)
        }
    }

    /// Cập nhật vị trí phát nhạc để làm nổi bật dòng lời tương ứng.
    public func updatePosition(_ position: TimeInterval) {
        self.latestPosition = position
        guard currentDocument.type == .synced else { return }
        let newIndex = currentDocument.currentLineIndex(at: position - self.userOffset)
        if newIndex != activeLineIndex {
            activeLineIndex = newIndex
        }
    }

    func setUserOffset(_ offset: TimeInterval) {
        guard let key = self.offsetKey, offset.isFinite else { return }
        self.userOffset = min(10, max(-10, offset))
        if self.userOffset == 0 {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(self.userOffset, forKey: key)
        }
        self.updatePosition(self.latestPosition)
    }

    func seekTime(for line: LyricsLine) -> TimeInterval {
        max(0, line.startTime + self.currentDocument.offset + self.userOffset)
    }

    /// Dừng bám dòng khi bắt đầu kéo; chỉ tạo timer một lần lúc thả tay.
    public func beginManualScroll() {
        guard !userIsScrolling else { return }
        userIsScrolling = true
        scrollResetTask?.cancel()
    }

    public func finishManualScroll() {
        guard userIsScrolling else { return }
        scrollResetTask?.cancel()
        scrollResetTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self.userIsScrolling = false
        }
    }

    public func resumeAutoScroll() {
        scrollResetTask?.cancel()
        userIsScrolling = false
    }
}
