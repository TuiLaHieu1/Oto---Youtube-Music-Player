import Testing
import Foundation
@testable import OtoCore

@Suite("Lyrics Parser and Title Cleaner Tests")
struct LyricsParserTests {
    @Test("TitleCleaner removes promotional video tags while preserving acoustic/remix")
    func testTitleCleaner() {
        #expect(TitleCleaner.clean("Đưa Em Về Nhà (Official Music Video)") == "Đưa Em Về Nhà")
        #expect(TitleCleaner.clean("Ánh Sao Và Bầu Trời [Lyric Video]") == "Ánh Sao Và Bầu Trời")
        #expect(TitleCleaner.clean("Một Năm Mới Bình An (Audio)") == "Một Năm Mới Bình An")
        #expect(TitleCleaner.clean("Stay (feat. Justin Bieber) [Official Video]") == "Stay (feat. Justin Bieber)")
        #expect(TitleCleaner.clean("Chờ Đợi Có Đáng Sợ (MV)") == "Chờ Đợi Có Đáng Sợ")

        // Preserves essential musical distinction
        #expect(TitleCleaner.clean("Shape of You (Acoustic)") == "Shape of You (Acoustic)")
        #expect(TitleCleaner.clean("Nothin' on You (Remix)") == "Nothin' on You (Remix)")
    }

    @Test("LRCParser parses standard and 3-digit decimals correctly")
    func testStandardLRC() {
        let lrc = """
        [00:01.00]Line 1
        [00:05.500]Line 2 with 3-digit ms
        [00:10.00]Line 3
        """
        let doc = LRCParser.parse(lrc, source: "Test")
        #expect(doc.type == .synced)
        #expect(doc.lines.count == 3)
        #expect(doc.lines[0].startTime == 1.0)
        #expect(doc.lines[0].endTime == 5.5)
        #expect(doc.lines[0].text == "Line 1")
        #expect(doc.lines[1].startTime == 5.5)
        #expect(doc.lines[1].endTime == 10.0)
        #expect(doc.lines[1].text == "Line 2 with 3-digit ms")
    }

    @Test("LRCParser handles multi-timestamp per line")
    func testMultiTimestamp() {
        let lrc = """
        [00:05.00][00:25.00]Chorus repeats twice
        [00:15.00]Verse 1
        """
        let doc = LRCParser.parse(lrc)
        #expect(doc.type == .synced)
        #expect(doc.lines.count == 3)

        // Must be sorted chronologically
        #expect(doc.lines[0].startTime == 5.0)
        #expect(doc.lines[0].text == "Chorus repeats twice")

        #expect(doc.lines[1].startTime == 15.0)
        #expect(doc.lines[1].text == "Verse 1")

        #expect(doc.lines[2].startTime == 25.0)
        #expect(doc.lines[2].text == "Chorus repeats twice")
    }

    @Test("LRCParser applies offset tag correctly")
    func testOffsetTag() {
        let lrc = """
        [offset:500]
        [00:01.00]Line 1
        [00:02.00]Line 2
        """
        let doc = LRCParser.parse(lrc)
        #expect(doc.type == .synced)
        #expect(doc.offset == 0.5)
        #expect(doc.lines[0].startTime == 1.5)
        #expect(doc.lines[1].startTime == 2.5)
    }

    @Test("LRCParser detects instrumental tracks")
    func testInstrumentalDetection() {
        let lrc = "[00:00.00] Instrumental"
        let doc = LRCParser.parse(lrc)
        #expect(doc.type == .instrumental)
        #expect(doc.lines.isEmpty)
    }

    @Test("LRCParser falls back to plain lyrics when no timestamps are found")
    func testPlainFallback() {
        let plain = """
        Đây là lời bài hát dạng văn bản thuần
        Không có mốc thời gian
        """
        let doc = LRCParser.parse(plain)
        #expect(doc.type == .plain)
        #expect(doc.lines.isEmpty)
        #expect(doc.plainLyrics?.contains("văn bản thuần") == true)
    }

    @Test("LyricsDocument currentLineIndex binary search lookup")
    func testCurrentLineIndex() {
        let lines = [
            LyricsLine(startTime: 0.0, endTime: 5.0, text: "Intro"),
            LyricsLine(startTime: 5.0, endTime: 10.0, text: "Verse 1"),
            LyricsLine(startTime: 10.0, endTime: 15.0, text: "Chorus")
        ]
        let doc = LyricsDocument(type: .synced, lines: lines)

        #expect(doc.currentLineIndex(at: -1.0) == nil)
        #expect(doc.currentLineIndex(at: 0.0) == 0)
        #expect(doc.currentLineIndex(at: 4.9) == 0)
        #expect(doc.currentLineIndex(at: 5.0) == 1)
        #expect(doc.currentLineIndex(at: 8.0) == 1)
        #expect(doc.currentLineIndex(at: 10.0) == 2)
        #expect(doc.currentLineIndex(at: 20.0) == 2)
    }
}
