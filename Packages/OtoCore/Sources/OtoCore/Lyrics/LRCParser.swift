import Foundation

/// Bộ phân tích cú pháp định dạng LRC chuẩn xác, hiệu năng cao và an toàn.
public enum LRCParser {
    // Regex khớp mốc thời gian: [mm:ss.xx] hoặc [mm:ss.xxx] hoặc [mm:ss]
    private static let timestampRegex: NSRegularExpression? = {
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    // Regex khớp thẻ offset: [offset:+/-ms]
    private static let offsetRegex: NSRegularExpression? = {
        let pattern = #"\[offset:\s*([+-]?\d+)\s*\]"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    public static func parse(_ lrcContent: String, source: String = "LRC") -> LyricsDocument {
        let trimmed = lrcContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LyricsDocument(type: .none, source: source)
        }

        if trimmed.localizedCaseInsensitiveContains("instrumental") && trimmed.count < 60 {
            return LyricsDocument(type: .instrumental, source: source)
        }

        var globalOffset: TimeInterval = 0
        var rawParsedLines: [(time: TimeInterval, text: String)] = []

        for line in trimmed.components(separatedBy: .newlines) {
            let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
            guard !lineTrimmed.isEmpty else { continue }

            if let offsetMs = extractOffset(from: lineTrimmed) {
                globalOffset = offsetMs / 1000.0
                continue
            }

            let parsedEntries = extractTimestampsAndText(from: lineTrimmed)
            rawParsedLines.append(contentsOf: parsedEntries)
        }

        guard !rawParsedLines.isEmpty else {
            return LyricsDocument(type: .plain, plainLyrics: trimmed, source: source)
        }

        rawParsedLines.sort { $0.time < $1.time }
        let finalLines = buildFinalLines(from: rawParsedLines, offset: globalOffset)

        return LyricsDocument(
            type: .synced,
            lines: finalLines,
            plainLyrics: finalLines.map(\.text).joined(separator: "\n"),
            source: source,
            offset: globalOffset
        )
    }

    private static func extractOffset(from line: String) -> Double? {
        guard let offsetRegex else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = offsetRegex.firstMatch(in: line, options: [], range: range),
              let numRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Double(line[numRange])
    }

    private static func extractTimestampsAndText(from line: String) -> [(time: TimeInterval, text: String)] {
        guard let timestampRegex else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        let matches = timestampRegex.matches(in: line, options: [], range: range)
        guard !matches.isEmpty else { return [] }

        var timestamps: [TimeInterval] = []
        var lastMatchEndIndex = line.startIndex

        for match in matches {
            guard let minRange = Range(match.range(at: 1), in: line),
                  let secRange = Range(match.range(at: 2), in: line),
                  let minutes = Double(line[minRange]),
                  let seconds = Double(line[secRange]) else {
                continue
            }

            var fractionSeconds: Double = 0.0
            if match.range(at: 3).location != NSNotFound,
               let fracRange = Range(match.range(at: 3), in: line) {
                let fracStr = String(line[fracRange])
                let divisor = pow(10.0, Double(fracStr.count))
                if let fracVal = Double(fracStr) {
                    fractionSeconds = fracVal / divisor
                }
            }

            timestamps.append((minutes * 60.0) + seconds + fractionSeconds)
            if let matchFullRange = Range(match.range, in: line), matchFullRange.upperBound > lastMatchEndIndex {
                lastMatchEndIndex = matchFullRange.upperBound
            }
        }

        let text = String(line[lastMatchEndIndex...]).trimmingCharacters(in: .whitespaces)
        return timestamps.map { (time: $0, text: text) }
    }

    private static func buildFinalLines(
        from raw: [(time: TimeInterval, text: String)],
        offset: TimeInterval
    ) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        for index in 0..<raw.count {
            let current = raw[index]
            let rawEndTime = (index + 1 < raw.count) ? raw[index + 1].time : (current.time + 5.0)
            lines.append(
                LyricsLine(
                    startTime: max(0, current.time + offset),
                    endTime: max(0, rawEndTime + offset),
                    text: current.text
                )
            )
        }
        return lines
    }
}
