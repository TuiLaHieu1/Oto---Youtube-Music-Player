import Foundation

/// Giữ ý định "đã dừng" của người dùng: khi đã dừng thì thẻ media không được tự phát lại,
/// kể cả khi trang YouTube Music tự phát sau khi nạp lại hoặc khi app quay về foreground.
enum PlayerIntentScript {
    static let source = """
    (function() {
      if (window.__otoIntentGuardInstalled) return;
      window.__otoIntentGuardInstalled = true;
      // Chỉ bật sau lệnh dừng/nạp-không-phát tường minh; mặc định tắt để không chặn lần nạp đầu.
      window.__otoPauseGuard = false;
      function wrap(name, guardFor) {
        const player = window.otoPlayer;
        if (!player || typeof player[name] !== 'function' || player[name].__otoWrapped) return;
        const original = player[name];
        const wrapped = function() {
          window.__otoPauseGuard = guardFor.apply(null, arguments);
          return original.apply(this, arguments);
        };
        wrapped.__otoWrapped = true;
        player[name] = wrapped;
      }
      function install(attempt) {
        if (!window.otoPlayer) {
          if (attempt < 40) setTimeout(function() { install(attempt + 1); }, 50);
          return;
        }
        wrap('play', function() { return false; });
        wrap('pause', function() { return true; });
        const byShouldPlay = function(id, start, generation, shouldPlay) { return shouldPlay === false; };
        wrap('loadVideo', byShouldPlay);
        wrap('adoptLoadedVideo', byShouldPlay);
        wrap('adoptCurrentVideo', byShouldPlay);
      }
      install(0);
      setInterval(function() {
        if (!window.__otoPauseGuard || window.__otoUserPaused !== true) return;
        const video = document.querySelector('video');
        if (video && !video.paused && !video.ended) {
          try { video.pause(); } catch(e) {}
        }
      }, 400);
    })();
    """
}
