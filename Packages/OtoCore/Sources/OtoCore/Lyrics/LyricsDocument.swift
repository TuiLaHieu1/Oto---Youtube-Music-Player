import Foundation

/// Phân loại dạng lời bài hát.
public enum LyricType: String, Sendable, Codable, Equatable {
    case synced
    case plain
    case instrumental
    case none
}

/// Một dòng lời bài hát có mốc thời gian.
public struct LyricsLine: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let startTime: TimeInterval
    public let endTime: TimeInterval?
    public let text: String

    public init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval? = nil, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

/// Tài liệu lời bài hát hoàn chỉnh (hỗ trợ cả lời đồng bộ và lời tĩnh).
public struct LyricsDocument: Sendable, Codable, Equatable {
    public let type: LyricType
    public let lines: [LyricsLine]
    public let plainLyrics: String?
    public let source: String
    public let offset: TimeInterval

    public init(
        type: LyricType,
        lines: [LyricsLine] = [],
        plainLyrics: String? = nil,
        source: String = "Unknown",
        offset: TimeInterval = 0
    ) {
        self.type = type
        self.lines = lines
        self.plainLyrics = plainLyrics
        self.source = source
        self.offset = offset
    }

    /// Trả về index của dòng lời đang phát tại mốc thời gian hiện tại (có tính offset).
    public func currentLineIndex(at position: TimeInterval) -> Int? {
        guard type == .synced, !lines.isEmpty else { return nil }
        let adjustedTime = position - offset
        if adjustedTime < lines[0].startTime {
            return nil
        }

        // Binary search để tìm dòng gần nhất có startTime <= adjustedTime
        var low = 0
        var high = lines.count - 1
        var candidateIndex = 0

        while low <= high {
            let mid = low + (high - low) / 2
            if lines[mid].startTime <= adjustedTime {
                candidateIndex = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return candidateIndex
    }
}
