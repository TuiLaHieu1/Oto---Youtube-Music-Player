import Foundation

/// Báo lỗi không phát được của chính player YouTube Music (onError hoặc màn hình lỗi) về native.
/// Chỉ lắng nghe và báo mã lỗi; không đổi request, không vượt giới hạn của video.
enum PlayerPlayabilityScript {
    static let source = """
    (function() {
      if (window.__otoPlayabilityInstalled) return;
      window.__otoPlayabilityInstalled = true;
      const bound = new WeakSet();
      let lastReport = '';
      function report(code) {
        const generation = window.__otoCurrentGeneration || 0;
        const videoId = window.__otoCurrentVideoId || '';
        if (!videoId) return;
        const key = generation + ':' + videoId + ':' + code;
        if (key === lastReport) return;
        lastReport = key;
        try {
          window.webkit.messageHandlers.otoPlayback.postMessage(
            { type: 'error', code: code, generation: generation, videoId: videoId });
        } catch(e) {}
      }
      function hook(player) {
        if (!player || bound.has(player) || typeof player.addEventListener !== 'function') return;
        bound.add(player);
        try {
          player.addEventListener('onError', function(event) {
            const raw = (typeof event === 'object' && event !== null && 'data' in event) ? event.data : event;
            const code = Number(raw);
            if (Number.isFinite(code)) report(Math.trunc(code));
          });
        } catch(e) {}
      }
      function showsErrorScreen(player) {
        if (!player || typeof player.querySelector !== 'function') return false;
        const node = player.querySelector('.ytp-error-content-wrap-reason, yt-player-error-message-renderer');
        return !!node && String(node.textContent || '').trim().length > 0;
      }
      setInterval(function() {
        const player = document.getElementById('movie_player');
        hook(player);
        if (showsErrorScreen(player)) report(150);
      }, 1000);
    })();
    """
}
