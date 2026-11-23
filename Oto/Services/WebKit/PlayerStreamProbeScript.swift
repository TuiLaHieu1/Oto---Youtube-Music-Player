#if OTO_STREAM_PROBE
import Foundation
import OSLog
import OtoCore

/// Khảo sát M1: đọc player response của chính trang đã đăng nhập.
/// Chỉ gửi cờ, số đếm và tên client đã lọc; không gửi URL, ID bài hay nội dung phản hồi.
enum PlayerStreamProbeScript {
    static let source = """
    (function() {
      if (window.__otoStreamProbeInstalled) return;
      window.__otoStreamProbeInstalled = true;
      let reportedGeneration = -1;
      const statuses = ['OK', 'UNPLAYABLE', 'LOGIN_REQUIRED', 'ERROR', 'CONTENT_CHECK_REQUIRED',
        'AGE_CHECK_REQUIRED', 'LIVE_STREAM_OFFLINE'];
      const clients = ['WEB_REMIX', 'WEB', 'MWEB', 'TVHTML5'];
      function playerResponse() {
        const sources = [document.getElementById('movie_player'),
          (document.querySelector('ytmusic-player') || {}).playerApi];
        for (const api of sources) {
          if (api && typeof api.getPlayerResponse === 'function') {
            try { return { hasAPI: true, response: api.getPlayerResponse() }; } catch (e) {}
          }
        }
        return { hasAPI: false, response: null };
      }
      function clientName() {
        try {
          const name = window.ytcfg && typeof window.ytcfg.get === 'function'
            ? window.ytcfg.get('INNERTUBE_CLIENT_NAME') : '';
          return clients.includes(name) ? name : (name ? 'other' : 'unknown');
        } catch (e) { return 'unknown'; }
      }
      function count(value) { return Array.isArray(value) ? value.length : (value == null ? 0 : -1); }
      setInterval(function() {
        const generation = window.__otoCurrentGeneration || 0;
        const expected = window.__otoCurrentVideoId || '';
        if (!expected || generation === reportedGeneration) return;
        const found = playerResponse();
        const response = found.response;
        const details = response && response.videoDetails;
        if (found.hasAPI && !(details && details.videoId === expected)) return;
        reportedGeneration = generation;
        const status = response && response.playabilityStatus && response.playabilityStatus.status;
        const streaming = response && response.streamingData;
        const body = {
          type: 'streamProbe', generation: generation, hasAPI: found.hasAPI, hasResponse: !!response,
          status: statuses.includes(status) ? status : (status ? 'OTHER' : 'none'),
          hasStreamingData: !!streaming && typeof streaming === 'object',
          hasHLS: !!streaming && typeof streaming.hlsManifestUrl === 'string',
          hasSABR: !!streaming && typeof streaming.serverAbrStreamingUrl === 'string',
          formatCount: streaming ? count(streaming.formats) : 0,
          adaptiveFormatCount: streaming ? count(streaming.adaptiveFormats) : 0,
          clientName: clientName()
        };
        const handler = window.webkit && window.webkit.messageHandlers
          && window.webkit.messageHandlers.otoPlayback;
        if (handler) handler.postMessage(body);
      }, 2000);
    })();
    """

    /// Dựng tóm tắt từ message của trang. Trả nil khi message sai cấu trúc hoặc thuộc generation cũ.
    static func summary(from body: [String: Any], currentGeneration: Int) -> (StreamProbeSummary, String)? {
        guard let generation = body["generation"] as? Int, generation == currentGeneration,
              let hasAPI = body["hasAPI"] as? Bool, let hasResponse = body["hasResponse"] as? Bool,
              let status = body["status"] as? String,
              let hasHLS = body["hasHLS"] as? Bool, let hasSABR = body["hasSABR"] as? Bool,
              let formats = body["formatCount"] as? Int, let adaptive = body["adaptiveFormatCount"] as? Int,
              let client = body["clientName"] as? String else { return nil }
        let clients = ["WEB_REMIX", "WEB", "MWEB", "TVHTML5", "other", "unknown"]
        let outcome: StreamProbeOutcome
        if !hasAPI || !hasResponse || status == "none" || formats < 0 || adaptive < 0 {
            outcome = .schemaMismatch
        } else if status != "OK" {
            outcome = .unplayable(StreamProbePlayability(rawValue: status) ?? .other)
        } else {
            outcome = hasHLS ? .hasHLS : .validNoHLS
        }
        let summary = StreamProbeSummary(
            outcome: outcome, formatCount: max(0, formats), adaptiveFormatCount: max(0, adaptive),
            hasSABR: hasSABR, secondsUntilExpiry: nil
        )
        return (summary, clients.contains(client) ? client : "other")
    }
}

@MainActor
extension SingletonPlayerWebView {
    func logStreamProbe(_ body: [String: Any]) {
        guard let (summary, client) = PlayerStreamProbeScript.summary(
            from: body, currentGeneration: self.currentGeneration
        ) else { return }
        let line = summary.logLine(variant: .page) + " client=\(client) api=\(body["hasAPI"] as? Bool == true)"
        Logger(subsystem: "com.oto.music", category: "StreamProbe").notice("\(line, privacy: .public)")
    }
}
#endif
