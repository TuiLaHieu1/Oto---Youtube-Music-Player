import Foundation

/// Chứa JavaScript bridge nhúng vào YouTube Music Web để điều khiển phát nhạc native.
enum PlayerBridgeScript {
    static let source = """
    (function() {
      if (window.__otoScriptInjected) return;
      window.__otoScriptInjected = true;

      function post(type, data) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.otoPlayback) {
            window.webkit.messageHandlers.otoPlayback.postMessage(Object.assign({ type: type }, data || {}));
          }
        } catch(e) {}
      }

      const style = document.createElement('style');
      style.textContent = `
        html, body { overflow: hidden !important; background-color: #000 !important; }
        ytmusic-popup-container, ytmusic-dialog, ytmusic-mealbar-promo-renderer,
        ytmusic-guide-renderer, ytmusic-nav-bar, #nav-bar-background {
          display: none !important;
        }
      `;
      document.head.appendChild(style);

      let boundVideo = null;

      function isAdActive() {
        const mp = document.getElementById('movie_player');
        if (mp && mp.classList && (mp.classList.contains('ad-showing') || mp.classList.contains('ad-interrupting'))) {
          return true;
        }
        const player = document.querySelector('ytmusic-player');
        const api = (player && player.playerApi) || mp;
        if (api && typeof api.getPresentingPlayerType === 'function') {
          if (api.getPresentingPlayerType(true) === 2) return true;
        }
        return false;
      }

      function hookVideo(v) {
        if (!v || v === boundVideo) return;
        boundVideo = v;
        v.muted = false;
        v.volume = 1.0;

        v.addEventListener('play', function() {
          post('stateChange', { state: 1, generation: window.__otoCurrentGeneration || 0 });
        });
        v.addEventListener('playing', function() {
          post('stateChange', { state: 1, generation: window.__otoCurrentGeneration || 0 });
        });
        v.addEventListener('pause', function() {
          if (!isAdActive()) {
            post('stateChange', { state: 2, generation: window.__otoCurrentGeneration || 0 });
          }
        });
        v.addEventListener('ended', function() {
          if (!isAdActive()) {
            post('stateChange', { state: 0, generation: window.__otoCurrentGeneration || 0 });
            post('trackEnded', { generation: window.__otoCurrentGeneration || 0 });
          }
        });
        v.addEventListener('timeupdate', function() {
          if (!isAdActive()) {
            post('timeUpdate', {
              currentTime: Number(v.currentTime) || 0,
              duration: Number(v.duration) || 0,
              generation: window.__otoCurrentGeneration || 0
            });
          }
        });
        v.addEventListener('error', function() {
          post('error', {
            code: v.error ? v.error.code : -1,
            generation: window.__otoCurrentGeneration || 0
          });
        });

        if (window.__otoWantsPlay && v.paused) {
          v.play().catch(function() {
            const playBtn = document.querySelector('#play-pause-button') ||
                            document.querySelector('.play-pause-button');
            if (playBtn) playBtn.click();
          });
        }
      }

      const observer = new MutationObserver(function() {
        const v = document.querySelector('video');
        if (v && v !== boundVideo) hookVideo(v);
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });

      setInterval(function() {
        const v = document.querySelector('video');
        if (v && v !== boundVideo) hookVideo(v);

        const skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
        if (skipBtn) skipBtn.click();

        const app = document.querySelector('ytmusic-app');
        if (app && typeof app.resolveCommand === 'function' && !window.__otoAppReady) {
          window.__otoAppReady = true;
          post('ready');
        }
      }, 250);

      window.otoPlayer = {
        loadVideo: function(id, startSeconds, generation) {
          window.__otoWantsPlay = true;
          window.__otoCurrentGeneration = generation || 0;

          const app = document.querySelector('ytmusic-app');
          if (app && typeof app.resolveCommand === 'function') {
            try {
              app.resolveCommand({ watchEndpoint: { videoId: id } });
              if (startSeconds && startSeconds > 0) {
                setTimeout(function() {
                  const v = document.querySelector('video');
                  if (v) v.currentTime = startSeconds;
                }, 400);
              }
              return;
            } catch(e) {}
          }

          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.loadVideoById === 'function') {
            try {
              mp.loadVideoById({ videoId: id, startSeconds: startSeconds || 0 });
              mp.playVideo();
              return;
            } catch(e) {}
          }

          window.location.href = 'https://music.youtube.com/watch?v=' + encodeURIComponent(id);
        },

        play: function() {
          window.__otoWantsPlay = true;
          const v = document.querySelector('video');
          if (v && v.paused) v.play().catch(function() {});
          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.playVideo === 'function') mp.playVideo();
          const playBtn = document.querySelector('#play-pause-button') ||
                          document.querySelector('.play-pause-button');
          if (playBtn && v && v.paused) playBtn.click();
        },

        pause: function() {
          window.__otoWantsPlay = false;
          const v = document.querySelector('video');
          if (v && !v.paused) v.pause();
          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.pauseVideo === 'function') mp.pauseVideo();
        },

        seekTo: function(seconds) {
          const v = document.querySelector('video');
          if (v) v.currentTime = seconds;
          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.seekTo === 'function') mp.seekTo(seconds, true);
        }
      };

      const app = document.querySelector('ytmusic-app');
      if (app && typeof app.resolveCommand === 'function') {
        window.__otoAppReady = true;
        post('ready');
      }
    })();
    """
}
