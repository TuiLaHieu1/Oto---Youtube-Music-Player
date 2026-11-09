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
        html, body {
          overflow: hidden !important;
          background-color: #000 !important;
        }
        ytmusic-popup-container, ytmusic-dialog, ytmusic-mealbar-promo-renderer,
        ytmusic-guide-renderer, ytmusic-nav-bar, #nav-bar-background {
          display: none !important;
        }
      `;
      document.head.appendChild(style);

      let boundVideo = null;
      window.__otoUserPaused = false;

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

      function attemptPlay(v) {
        if (!v || window.__otoUserPaused) return;
        v.muted = false;
        v.volume = 1.0;

        const mp = document.getElementById('movie_player');
        if (mp) {
          if (typeof mp.unMute === 'function') mp.unMute();
          if (typeof mp.setVolume === 'function') mp.setVolume(100);
          if (typeof mp.playVideo === 'function') mp.playVideo();
        }

        const player = document.querySelector('ytmusic-player');
        if (player && player.playerApi) {
          if (typeof player.playerApi.unMute === 'function') player.playerApi.unMute();
          if (typeof player.playerApi.setVolume === 'function') player.playerApi.setVolume(100);
          if (typeof player.playerApi.playVideo === 'function') player.playerApi.playVideo();
        }

        const p = v.play();
        if (p && typeof p.catch === 'function') {
          p.catch(function() {
            const playBtn = document.querySelector('#play-pause-button') ||
                            document.querySelector('.play-pause-button') ||
                            document.querySelector('[slot="player-bar"] .play-pause-button') ||
                            document.querySelector('.ytmusicPlayerControlsPlayPauseButton button');
            if (playBtn) playBtn.click();
          });
        }
      }

      function hookVideo(v) {
        if (!v || v === boundVideo) return;
        boundVideo = v;

        attemptPlay(v);

        v.addEventListener('play', function() {
          post('stateChange', { state: 1, generation: window.__otoCurrentGeneration || 0 });
        });
        v.addEventListener('playing', function() {
          post('stateChange', { state: 1, generation: window.__otoCurrentGeneration || 0 });
        });
        v.addEventListener('pause', function() {
          if (!isAdActive()) {
            post('stateChange', { state: 2, generation: window.__otoCurrentGeneration || 0 });
            if (!window.__otoUserPaused && !v.ended) {
              setTimeout(function() { attemptPlay(v); }, 300);
            }
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
      }

      const observer = new MutationObserver(function() {
        const v = document.querySelector('video');
        if (v) hookVideo(v);
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });

      setInterval(function() {
        const v = document.querySelector('video');
        if (v) {
          hookVideo(v);
          if (v.paused && !window.__otoUserPaused && !isAdActive()) {
            attemptPlay(v);
          }
        }

        const skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
        if (skipBtn) skipBtn.click();

        const app = document.querySelector('ytmusic-app');
        if (app && !window.__otoAppReady) {
          window.__otoAppReady = true;
          post('ready');
        }
      }, 200);

      window.otoPlayer = {
        loadVideo: function(id, startSeconds, generation) {
          window.__otoUserPaused = false;
          window.__otoCurrentGeneration = generation || 0;

          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.loadVideoById === 'function') {
            try {
              mp.loadVideoById({ videoId: id, startSeconds: startSeconds || 0 });
              mp.playVideo();
              return;
            } catch(e) {}
          }

          const app = document.querySelector('ytmusic-app');
          if (app && typeof app.resolveCommand === 'function') {
            try {
              app.resolveCommand({ watchEndpoint: { videoId: id } });
              return;
            } catch(e) {}
          }

          window.location.href = 'https://music.youtube.com/watch?v=' + encodeURIComponent(id);
        },

        play: function() {
          window.__otoUserPaused = false;
          const v = document.querySelector('video');
          attemptPlay(v);
        },

        pause: function() {
          window.__otoUserPaused = true;
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

      post('ready');
    })();
    """
}
