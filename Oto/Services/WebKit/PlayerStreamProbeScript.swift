#if DEBUG && OTO_STREAM_PROBE
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
      const maxAttempts = 5;
      let reportedGeneration = -1;
      let attemptGeneration = -1;
      let attempts = 0;
      const statuses = ['OK', 'UNPLAYABLE', 'LOGIN_REQUIRED', 'ERROR', 'CONTENT_CHECK_REQUIRED',
        'AGE_CHECK_REQUIRED', 'LIVE_STREAM_OFFLINE'];
      const clients = ['WEB_REMIX', 'WEB', 'MWEB', 'TVHTML5'];
      function playerResponse() {
        const sources = [document.getElementById('movie_player'),
          (document.querySelector('ytmusic-player') || {}).playerApi];
        let hasAPI = false;
        let apiError = false;
        for (const api of sources) {
          if (api && typeof api.getPlayerResponse === 'function') {
            hasAPI = true;
            try {
              const response = api.getPlayerResponse();
              if (response) return { hasAPI: true, apiError: false, response: response };
            } catch (e) { apiError = true; }
          }
        }
        return { hasAPI: hasAPI, apiError: apiError, response: null };
      }
      function clientName() {
        try {
          const name = window.ytcfg && typeof window.ytcfg.get === 'function'
            ? window.ytcfg.get('INNERTUBE_CLIENT_NAME') : '';
          return clients.includes(name) ? name : (name ? 'other' : 'unknown');
        } catch (e) { return 'unknown'; }
      }
      function kind(value, type) {
        if (value === undefined || value === null) return 'missing';
        if (type === 'array') return Array.isArray(value) ? 'ok' : 'other';
        if (type === 'object') return typeof value === 'object' && !Array.isArray(value) ? 'ok' : 'other';
        return typeof value === type ? 'ok' : 'other';
      }
      function count(value) { return Array.isArray(value) ? value.length : (value == null ? 0 : -1); }
      setInterval(function() {
        const generation = window.__otoCurrentGeneration || 0;
        const expected = window.__otoCurrentVideoId || '';
        if (!expected || generation === reportedGeneration) return;
        if (attemptGeneration !== generation) { attemptGeneration = generation; attempts = 0; }
        attempts += 1;
        const found = playerResponse();
        const response = found.response;
        const details = response && response.videoDetails;
        const playability = response && response.playabilityStatus;
        const status = playability && playability.status;
        const matchesTrack = !!details && details.videoId === expected;
        // Response lỗi thường không có videoDetails; vẫn báo vì đó là kết quả cần đo.
        const errorWithoutDetails = !!status && status !== 'OK' && !details;
        if (!(matchesTrack || errorWithoutDetails) && attempts < maxAttempts) return;
        reportedGeneration = generation;
        const streaming = response && response.streamingData;
        const streamingKind = kind(streaming, 'object');
        const body = {
          type: 'streamProbe', generation: generation, attempts: attempts,
          hasAPI: found.hasAPI, apiError: found.apiError, hasResponse: !!response,
          matchesTrack: matchesTrack, errorWithoutDetails: errorWithoutDetails,
          status: statuses.includes(status) ? status : (status ? 'OTHER' : 'none'),
          streamingDataKind: streamingKind,
          hlsKind: streamingKind === 'ok' ? kind(streaming.hlsManifestUrl, 'string') : 'missing',
          hasSABR: streamingKind === 'ok' && typeof streaming.serverAbrStreamingUrl === 'string',
          formatCount: streamingKind === 'ok' ? count(streaming.formats) : 0,
          adaptiveFormatCount: streamingKind === 'ok' ? count(streaming.adaptiveFormats) : 0,
          clientName: clientName()
        };
        const handler = window.webkit && window.webkit.messageHandlers
          && window.webkit.messageHandlers.otoPlayback;
        if (handler) handler.postMessage(body);
      }, 2000);
    })();
    """

    /// Dựng tóm tắt từ message của trang. Trả nil khi message sai cấu trúc hoặc thuộc generation cũ.
    /// Quy tắc phân loại khớp với `YTMusicParsers.parseStreamProbe` của M2.
    static func summary(from body: [String: Any], currentGeneration: Int) -> (StreamProbeSummary, String)? {
        guard let generation = body["generation"] as? Int, generation == currentGeneration,
              let hasAPI = body["hasAPI"] as? Bool, let hasResponse = body["hasResponse"] as? Bool,
              let matchesTrack = body["matchesTrack"] as? Bool,
              let errorWithoutDetails = body["errorWithoutDetails"] as? Bool,
              let status = body["status"] as? String,
              let streamingKind = body["streamingDataKind"] as? String,
              let hlsKind = body["hlsKind"] as? String, let hasSABR = body["hasSABR"] as? Bool,
              let formats = body["formatCount"] as? Int, let adaptive = body["adaptiveFormatCount"] as? Int,
              let client = body["clientName"] as? String else { return nil }
        let clients = ["WEB_REMIX", "WEB", "MWEB", "TVHTML5", "other", "unknown"]
        let outcome: StreamProbeOutcome
        if !hasAPI || !hasResponse || !(matchesTrack || errorWithoutDetails) {
            outcome = .notObserved
        } else if status == "none" {
            outcome = .schemaMismatch
        } else if status != "OK" {
            outcome = .unplayable(StreamProbePlayability(rawValue: status) ?? .other)
        } else if streamingKind == "missing" {
            outcome = .validNoHLS
        } else if streamingKind != "ok" || hlsKind == "other" || formats < 0 || adaptive < 0 {
            outcome = .schemaMismatch
        } else {
            outcome = hlsKind == "ok" ? .hasHLS : .validNoHLS
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
        let flags = ["hasAPI", "apiError", "matchesTrack", "errorWithoutDetails"]
            .map { "\($0)=\(body[$0] as? Bool == true)" }.joined(separator: " ")
        let attempts = body["attempts"] as? Int ?? -1
        let line = summary.logLine(variant: .page) + " client=\(client) \(flags) attempts=\(attempts)"
        Logger(subsystem: "com.oto.music", category: "StreamProbe").notice("\(line, privacy: .public)")
    }
}
#endif
