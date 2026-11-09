import Foundation

/// Đại diện cho một bài hát trong hàng đợi với ID phiên duy nhất.
/// Cho phép cùng một bài hát xuất hiện nhiều lần mà không xung đột danh tính.
public struct QueueItem: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let song: Song

    public init(id: UUID = UUID(), song: Song) {
        self.id = id
        self.song = song
    }
}

/// Chế độ lặp bài.
public enum RepeatMode: String, Sendable, Codable, CaseIterable {
    case off
    case all
    case one
}

/// Trạng thái phát nhạc của Oto.
public enum PlaybackState: Sendable, Equatable {
    case idle
    case preparing(song: Song)
    case playing(song: Song, position: TimeInterval)
    case paused(song: Song, position: TimeInterval)
    case buffering(song: Song, position: TimeInterval)
    case failed(error: String)

    public var currentSong: Song? {
        switch self {
        case .idle, .failed:
            return nil
        case .preparing(let song),
             .playing(let song, _),
             .paused(let song, _),
             .buffering(let song, _):
            return song
        }
    }

    public var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }

    public var currentPosition: TimeInterval {
        switch self {
        case .playing(_, let position),
             .paused(_, let position),
             .buffering(_, let position):
            return position
        case .idle, .preparing, .failed:
            return 0
        }
    }
}
