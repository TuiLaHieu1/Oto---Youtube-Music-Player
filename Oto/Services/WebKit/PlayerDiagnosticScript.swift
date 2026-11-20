import Foundation
import WebKit

/// Chỉ gửi trạng thái kỹ thuật, không gửi URL, cookie, nội dung dialog hoặc metadata tài khoản.
enum PlayerDiagnosticScript {
    static let source = """
    (function() {
      let scheduledRequest = null;
      let rejectionGeneration = -1;
      let rejectionLogged = false;
      window.otoSchedulePlaybackDiagnostics = function(id, generation) {
        const key = JSON.stringify([id, generation || 0]);
        if (scheduledRequest === key) return;
        scheduledRequest = key;
        [1000, 3000, 8000].forEach(function(delay) {
          setTimeout(function() {
            if (window.__otoCurrentVideoId === id && window.__otoCurrentGeneration === (generation || 0)) {
              window.otoReportPlaybackDiagnostic('sample');
            }
          }, delay);
        });
      };
      window.otoReportPlaybackDiagnostic = function(stage, errorName) {
        const generation = window.__otoCurrentGeneration || 0;
        if (generation !== rejectionGeneration) { rejectionGeneration = generation; rejectionLogged = false; }
        if (stage === 'playRejected') {
          if (rejectionLogged) return;
          rejectionLogged = true;
        }
        const video = document.querySelector('video');
        const player = document.getElementById('movie_player');
        const acceptedErrors = ['NotAllowedError', 'NotSupportedError', 'AbortError', 'SecurityError'];
        const error = acceptedErrors.includes(errorName) ? errorName : (errorName ? 'OtherError' : 'none');
        const body = {
          type: 'playbackDiagnostic', stage: stage,
          generation: window.__otoCurrentGeneration || 0,
          hasVideo: !!video, hasMoviePlayer: !!player,
          hasLoadAPI: !!(player && typeof player.loadVideoById === 'function'),
          hasPlayerAPI: !!(document.querySelector('ytmusic-player') || {}).playerApi,
          paused: video ? video.paused : true,
          muted: video ? video.muted : false,
          readyState: video ? video.readyState : -1,
          networkState: video ? video.networkState : -1,
          position: video && Number.isFinite(video.currentTime) ? video.currentTime : -1,
          mediaError: video && video.error ? video.error.code : 0,
          visibility: document.visibilityState === 'visible' ? 'visible' : 'hidden',
          error: error,
          blockedOverlay: !!document.querySelector('ytmusic-dialog[opened], yt-player-error-message-renderer')
        };
        const handler = window.webkit && window.webkit.messageHandlers
          && window.webkit.messageHandlers.otoPlayback;
        if (handler) handler.postMessage(body);
      };
    })();
    """
}

@MainActor
extension SingletonPlayerWebView {
    func logPlaybackDiagnostic(_ body: [String: Any]) {
        guard let generation = body["generation"] as? Int, generation == currentGeneration,
              let stage = body["stage"] as? String, ["sample", "playRejected"].contains(stage) else { return }
        if diagnosticGeneration != generation {
            diagnosticGeneration = generation
            diagnosticSamples = 0
            diagnosticRejectionLogged = false
        }
        if stage == "sample" {
            guard diagnosticSamples < 3 else { return }
            diagnosticSamples += 1
        } else {
            guard !diagnosticRejectionLogged else { return }
            diagnosticRejectionLogged = true
        }
        let allowedErrors = [
            "NotAllowedError", "NotSupportedError", "AbortError", "SecurityError", "OtherError", "none"
        ]
        let error = (body["error"] as? String).flatMap { allowedErrors.contains($0) ? $0 : nil } ?? "none"
        let video = body["hasVideo"] as? Bool ?? false
        let muted = body["muted"] as? Bool ?? false
        let paused = body["paused"] as? Bool ?? true
        let ready = body["readyState"] as? Int ?? -1
        let network = body["networkState"] as? Int ?? -1
        let mediaError = body["mediaError"] as? Int ?? 0
        let rawPosition = body["position"] as? Double ?? -1
        let position = rawPosition.isFinite ? rawPosition : -1
        let attached = webView?.window != nil
        let hidden = webView?.isHidden ?? true
        let visible = body["visibility"] as? String == "visible"
        let overlay = body["blockedOverlay"] as? Bool ?? false
        let playerAPI = body["hasPlayerAPI"] as? Bool ?? false
        let moviePlayer = body["hasMoviePlayer"] as? Bool ?? false
        let loadAPI = body["hasLoadAPI"] as? Bool ?? false
        logger.info("Playback probe t=\(ProcessInfo.processInfo.systemUptime) gen=\(generation)")
        logger.info("Playback stage=\(stage, privacy: .public) documentVisible=\(visible)")
        logger.info("Playback rejection error=\(error, privacy: .public) muted=\(muted)")
        logger.info("Playback media video=\(video) paused=\(paused) ready=\(ready) network=\(network)")
        logger.info("Playback media position=\(position) mediaError=\(mediaError) playerAPI=\(playerAPI)")
        logger.info("Playback API moviePlayer=\(moviePlayer) loadAPI=\(loadAPI)")
        logger.info("Playback view attached=\(attached) hidden=\(hidden) blockedOverlay=\(overlay)")
    }
}
