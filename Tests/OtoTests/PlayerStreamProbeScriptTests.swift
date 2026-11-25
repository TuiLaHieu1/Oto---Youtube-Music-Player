#if DEBUG && OTO_STREAM_PROBE
import Foundation
import Testing
@testable import Oto

@Suite("Khảo sát stream: message M1 từ trang")
struct PlayerStreamProbeScriptTests {
    private func body(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "type": "streamProbe", "generation": 4, "attempts": 1, "hasAPI": true, "apiError": false,
            "hasResponse": true, "matchesTrack": true, "errorWithoutDetails": false, "status": "OK",
            "streamingDataKind": "ok", "hlsKind": "ok", "hasSABR": false,
            "formatCount": 1, "adaptiveFormatCount": 3, "clientName": "WEB_REMIX"
        ]
        for (key, value) in overrides { base[key] = value }
        return base
    }

    @Test("Message hợp lệ của generation hiện tại cho ra tóm tắt đúng")
    func validMessage() throws {
        let (summary, client) = try #require(PlayerStreamProbeScript.summary(from: self.body(), currentGeneration: 4))
        #expect(summary.outcome == .hasHLS)
        #expect(summary.adaptiveFormatCount == 3)
        #expect(client == "WEB_REMIX")
        let noHLS = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["hlsKind": "missing", "hasSABR": true]), currentGeneration: 4
        ))
        #expect(noHLS.0.outcome == .validNoHLS)
        #expect(noHLS.0.hasSABR)
    }

    @Test("Đếm audio từ trang được đọc an toàn")
    func audioCountsFromPage() throws {
        let audio: [String: Any] = ["mp4Direct": 2, "mp4Cipher": 1, "webmDirect": 1, "directWithN": -3, "evil": "x"]
        let (summary, _) = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["audio": audio]), currentGeneration: 4
        ))
        #expect(summary.audio.mp4Direct == 2)
        #expect(summary.audio.mp4Cipher == 1)
        #expect(summary.audio.webmDirect == 1)
        #expect(summary.audio.directWithN == 0)
        #expect(PlayerStreamProbeScript.audioCounts(from: "bad") == .empty)
    }

    @Test("Generation cũ hoặc message sai kiểu bị bỏ qua")
    func staleOrMalformed() {
        #expect(PlayerStreamProbeScript.summary(from: self.body(), currentGeneration: 5) == nil)
        #expect(PlayerStreamProbeScript.summary(from: self.body(["hlsKind": 1]), currentGeneration: 4) == nil)
        #expect(PlayerStreamProbeScript.summary(from: [:], currentGeneration: 4) == nil)
    }

    @Test("Không có API, trạng thái lạ và client lạ được phân loại an toàn")
    func classification() throws {
        let noAPI = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["hasAPI": false, "hasResponse": false, "status": "none"]), currentGeneration: 4
        ))
        #expect(noAPI.0.outcome == .notObserved)
        let otherTrack = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["matchesTrack": false]), currentGeneration: 4
        ))
        #expect(otherTrack.0.outcome == .notObserved)
        let errorPage = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["matchesTrack": false, "errorWithoutDetails": true, "status": "LOGIN_REQUIRED"]),
            currentGeneration: 4
        ))
        #expect(errorPage.0.outcome == .unplayable(.loginRequired))
        let blocked = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["status": "UNPLAYABLE", "clientName": "<script>"]), currentGeneration: 4
        ))
        #expect(blocked.0.outcome == .unplayable(.unplayable))
        #expect(blocked.1 == "other")
        let badCount = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["formatCount": -1]), currentGeneration: 4
        ))
        #expect(badCount.0.outcome == .schemaMismatch)
        let missingStreaming = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["streamingDataKind": "missing", "hlsKind": "missing"]), currentGeneration: 4
        ))
        #expect(missingStreaming.0.outcome == .validNoHLS)
        for overrides in [["streamingDataKind": "other"], ["hlsKind": "other"]] {
            let broken = try #require(PlayerStreamProbeScript.summary(
                from: self.body(overrides), currentGeneration: 4
            ))
            #expect(broken.0.outcome == .schemaMismatch, "Căn với cách M2 phân loại")
        }
    }
}
#endif
