import Foundation

/// Tiện ích làm sạch tiêu đề bài hát để tối ưu việc tìm kiếm lời bài hát (LRCLIB, Musixmatch).
/// Loại bỏ các nhãn quảng bá video mà không xoá các nhãn phân biệt bản thu (live, remix, acoustic).
public enum TitleCleaner {
    private static let promotionalPatterns: [String] = [
        #"\s*[\(\[]\s*official\s+music\s+video\s*[\)\]]"#,
        #"\s*[\(\[]\s*official\s+lyric\s+video\s*[\)\]]"#,
        #"\s*[\(\[]\s*official\s+video\s*[\)\]]"#,
        #"\s*[\(\[]\s*official\s+audio\s*[\)\]]"#,
        #"\s*[\(\[]\s*lyric\s+video\s*[\)\]]"#,
        #"\s*[\(\[]\s*lyrics\s+video\s*[\)\]]"#,
        #"\s*[\(\[]\s*music\s+video\s*[\)\]]"#,
        #"\s*[\(\[]\s*video\s+clip\s*[\)\]]"#,
        #"\s*[\(\[]\s*visualizer\s*[\)\]]"#,
        #"\s*[\(\[]\s*audio\s*[\)\]]"#,
        #"\s*[\(\[]\s*mv\s*[\)\]]"#,
        #"\s*[\(\[]\s*m/v\s*[\)\]]"#,
        #"\s*[\(\[]\s*remastered\s*[\)\]]"#
    ]

    private static let regexes: [NSRegularExpression] = {
        promotionalPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()

    public static func clean(_ title: String) -> String {
        var result = title
        for regex in regexes {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Dọn khoảng trắng thừa và ký tự nối mồ côi ở cuối
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("-") || result.hasSuffix("|") || result.hasSuffix("/") {
            result = String(result.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result.isEmpty ? title : result
    }
}
