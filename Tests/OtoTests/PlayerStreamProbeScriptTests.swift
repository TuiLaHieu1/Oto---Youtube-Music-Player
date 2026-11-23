#if OTO_STREAM_PROBE
import Foundation
import Testing
@testable import Oto

@Suite("Khảo sát stream: message M1 từ trang")
struct PlayerStreamProbeScriptTests {
    private func body(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "type": "streamProbe", "generation": 4, "hasAPI": true, "hasResponse": true, "status": "OK",
            "hasStreamingData": true, "hasHLS": true, "hasSABR": false,
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
            from: self.body(["hasHLS": false, "hasSABR": true]), currentGeneration: 4
        ))
        #expect(noHLS.0.outcome == .validNoHLS)
        #expect(noHLS.0.hasSABR)
    }

    @Test("Generation cũ hoặc message sai kiểu bị bỏ qua")
    func staleOrMalformed() {
        #expect(PlayerStreamProbeScript.summary(from: self.body(), currentGeneration: 5) == nil)
        #expect(PlayerStreamProbeScript.summary(from: self.body(["hasHLS": "yes"]), currentGeneration: 4) == nil)
        #expect(PlayerStreamProbeScript.summary(from: [:], currentGeneration: 4) == nil)
    }

    @Test("Không có API, trạng thái lạ và client lạ được phân loại an toàn")
    func classification() throws {
        let noAPI = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["hasAPI": false, "hasResponse": false, "status": "none"]), currentGeneration: 4
        ))
        #expect(noAPI.0.outcome == .schemaMismatch)
        let blocked = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["status": "UNPLAYABLE", "clientName": "<script>"]), currentGeneration: 4
        ))
        #expect(blocked.0.outcome == .unplayable(.unplayable))
        #expect(blocked.1 == "other")
        let badCount = try #require(PlayerStreamProbeScript.summary(
            from: self.body(["formatCount": -1]), currentGeneration: 4
        ))
        #expect(badCount.0.outcome == .schemaMismatch)
    }
}
#endif
