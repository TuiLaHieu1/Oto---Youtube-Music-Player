import Foundation

/// Chứa JavaScript bridge nhúng vào YouTube Music Web để điều khiển phát nhạc native.
enum PlayerBridgeScript {
    static let source = bridgeJavaScript
}

private let bridgeJavaScript = """
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
      style.textContent = 'html, body { overflow: hidden !important; background-color: #000 !important; } ' +
        'ytmusic-popup-container, ytmusic-dialog, ytmusic-mealbar-promo-renderer, ' +
        'ytmusic-guide-renderer, ytmusic-nav-bar, #nav-bar-background { display: none !important; }';
      document.head.appendChild(style);

      try {
        const retF = function() { return false; };
        const retV = function() { return 'visible'; };
        Object.defineProperty(document, 'hidden', { get: retF, configurable: true });
        Object.defineProperty(document, 'visibilityState', { get: retV, configurable: true });
        window.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
      } catch(e) {}

      let boundVideo = null;
      window.__otoUserPaused = false;
      window.__otoCurrentGeneration = 0;
      window.__otoCurrentVideoId = '';

      function actualVideoId() {
        try {
          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.getVideoData === 'function') {
            const data = mp.getVideoData();
            if (data && data.video_id) return String(data.video_id);
          }
          const player = document.querySelector('ytmusic-player');
          if (player && player.playerApi && typeof player.playerApi.getVideoData === 'function') {
            const data = player.playerApi.getVideoData();
            if (data && data.video_id) return String(data.video_id);
          }
          return new URL(window.location.href).searchParams.get('v') || '';
        } catch(e) { return ''; }
      }

      function messageIdentity() {
        return { generation: window.__otoCurrentGeneration || 0, videoId: actualVideoId() };
      }

      function postRemoteCommand(command, extra) {
        post('remoteCommand', Object.assign({ command: command }, messageIdentity(), extra || {}));
      }

      function installMediaSessionHandlers() {
        if (!navigator.mediaSession || typeof navigator.mediaSession.setActionHandler !== 'function') return;

        if (!window.__otoActionHandlerPatched) {
          window.__otoActionHandlerPatched = true;
          const _origSetActionHandler = navigator.mediaSession.setActionHandler.bind(navigator.mediaSession);
          navigator.mediaSession.setActionHandler = function(action, handler) {
            if (action === 'seekforward' || action === 'seekbackward') return;
            return _origSetActionHandler(action, handler);
          };
        }

        const handlers = {
          play: function() { postRemoteCommand('play'); },
          pause: function() { postRemoteCommand('pause'); },
          nexttrack: function() { postRemoteCommand('next'); },
          previoustrack: function() { postRemoteCommand('previous'); },
          seekto: function(d) {
            if (d && Number.isFinite(d.seekTime)) postRemoteCommand('seek', { position: d.seekTime });
          }
        };
        Object.keys(handlers).forEach(function(a) {
          try { navigator.mediaSession.setActionHandler(a, handlers[a]); } catch(e) {}
        });
        ['seekforward', 'seekbackward'].forEach(function(a) {
          try { navigator.mediaSession.setActionHandler(a, null); } catch(e) {}
        });
      }

      function confirmTrack(expectedId, generation, attempt) {
        const activeId = actualVideoId();
        if (activeId === expectedId) {
          post('trackActivated', { videoId: activeId, generation: generation });
          return;
        }
        if (attempt < 40) {
          setTimeout(function() { confirmTrack(expectedId, generation, attempt + 1); }, 125);
          return;
        }
        post('error', { code: 901, videoId: expectedId, generation: generation });
      }

      try {
        localStorage.setItem('yt-player-volume', JSON.stringify({
          data: JSON.stringify({ volume: 100, muted: false })
        }));
      } catch(e) {}

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
        if (window.__otoUserPaused) return;

        try {
          const bar = document.querySelector('ytmusic-player-bar');
          if (bar && bar.shadowRoot) {
            const playBtn = bar.shadowRoot.querySelector('#play-pause-button');
            if (playBtn) {
              const label = (playBtn.getAttribute('aria-label') || '').toLowerCase();
              if (label.includes('play') || label.includes('phát')) playBtn.click();
            }
          }
        } catch(e) {}

        const mp = document.getElementById('movie_player');
        if (mp) {
          try {
            if (typeof mp.unMute === 'function') mp.unMute();
            if (typeof mp.setVolume === 'function') mp.setVolume(100);
            if (typeof mp.playVideo === 'function') mp.playVideo();
          } catch(e) {}
        }

        const player = document.querySelector('ytmusic-player');
        if (player && player.playerApi) {
          try {
            if (typeof player.playerApi.unMute === 'function') player.playerApi.unMute();
            if (typeof player.playerApi.setVolume === 'function') player.playerApi.setVolume(100);
            if (typeof player.playerApi.playVideo === 'function') player.playerApi.playVideo();
          } catch(e) {}
        }

        const targetVideo = v || document.querySelector('video');
        if (targetVideo) {
          try {
            targetVideo.muted = false;
            targetVideo.volume = 1.0;
            const p = targetVideo.play();
            if (p && typeof p.catch === 'function') {
              p.catch(function() {
                try {
                  targetVideo.muted = true;
                  const p2 = targetVideo.play();
                  if (p2 && typeof p2.then === 'function') {
                    p2.then(function() { targetVideo.muted = false; }).catch(function() {});
                  }
                } catch(e2) {}
              });
            }
          } catch(e) {}
        }
      }

      function checkAndNotifyEnded(v) {
        if (v && v.duration > 5 && v.currentTime >= v.duration - 0.6) {
          if (!v.__otoTrackEndedFired) {
            v.__otoTrackEndedFired = true;
            post('stateChange', Object.assign({ state: 0 }, messageIdentity()));
            post('trackEnded', messageIdentity());
          }
        }
      }

      function hookVideo(v) {
        if (!v || v === boundVideo) return;
        boundVideo = v;

        if (!window.__otoUserPaused) {
          attemptPlay(v);
        }

        v.addEventListener('play', function() {
          post('stateChange', Object.assign({ state: 1 }, messageIdentity()));
        });
        v.addEventListener('playing', function() {
          post('stateChange', Object.assign({ state: 1 }, messageIdentity()));
        });
        v.addEventListener('pause', function() {
          if (!isAdActive()) {
            if (v.duration > 5 && v.currentTime >= v.duration - 0.8) {
              checkAndNotifyEnded(v);
            } else {
              post('stateChange', Object.assign({ state: 2 }, messageIdentity()));
              if (!window.__otoUserPaused && !v.ended) setTimeout(function() { attemptPlay(v); }, 300);
            }
          }
        });
        v.addEventListener('ended', function() { if (!isAdActive()) checkAndNotifyEnded(v); });
        v.addEventListener('timeupdate', function() {
          if (!isAdActive()) {
            checkAndNotifyEnded(v);
            post('timeUpdate', {
              currentTime: Number(v.currentTime) || 0,
              duration: Number(v.duration) || 0,
              generation: window.__otoCurrentGeneration || 0,
              videoId: actualVideoId()
            });
          }
        });
        v.addEventListener('error', function() {
          post('error', {
            code: v.error ? v.error.code : -1,
            generation: window.__otoCurrentGeneration || 0,
            videoId: actualVideoId()
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

        const app = document.querySelector('ytmusic-app');
        if (app && !window.__otoAppReady) {
          window.__otoAppReady = true;
          post('ready');
        }
      }, 200);

      installMediaSessionHandlers();
      setInterval(installMediaSessionHandlers, 1000);

      window.otoPlayer = {
        loadVideo: function(id, startSeconds, generation, shouldPlay) {
          window.__otoUserPaused = (shouldPlay === false);
          window.__otoCurrentGeneration = generation || 0;
          window.__otoCurrentVideoId = id;
          if (boundVideo) boundVideo.__otoTrackEndedFired = false;

          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.loadVideoById === 'function') {
            try {
              try {
                mp.loadVideoById(id, startSeconds || 0);
              } catch(e1) {
                mp.loadVideoById({ videoId: id, startSeconds: startSeconds || 0 });
              }
              if (shouldPlay !== false && !window.__otoUserPaused) {
                mp.playVideo();
              }
              confirmTrack(id, generation || 0, 0);
              return;
            } catch(e) {}
          }

          const app = document.querySelector('ytmusic-app');
          if (app && typeof app.resolveCommand === 'function') {
            try {
              app.resolveCommand({ watchEndpoint: { videoId: id } });
              confirmTrack(id, generation || 0, 0);
              setTimeout(function() {
                if (actualVideoId() !== id) {
                  window.location.assign('https://music.youtube.com/watch?v=' + encodeURIComponent(id));
                }
              }, 750);
              return;
            } catch(e) {}
          }

          window.location.href = 'https://music.youtube.com/watch?v=' + encodeURIComponent(id);
        },

        adoptLoadedVideo: function(id, startSeconds, generation, shouldPlay) {
          window.__otoCurrentGeneration = generation || 0;
          window.__otoCurrentVideoId = id;
          window.__otoUserPaused = (shouldPlay === false);

          function tryAdopt(retries) {
            const v = document.querySelector('video');
            const mp = document.getElementById('movie_player');
            if (v || (mp && typeof mp.playVideo === 'function')) {
              if (v) {
                v.__otoTrackEndedFired = false;
                if (typeof startSeconds === 'number' && startSeconds > 0) v.currentTime = startSeconds;
              }
              if (mp && typeof mp.seekTo === 'function' && typeof startSeconds === 'number' && startSeconds > 0) {
                try { mp.seekTo(startSeconds, true); } catch(e) {}
              }
              if (shouldPlay && !window.__otoUserPaused) {
                attemptPlay(v);
              }
              confirmTrack(id, generation || 0, 0);
              return;
            }
            if (retries > 0) {
              setTimeout(function() { tryAdopt(retries - 1); }, 150);
            } else {
              confirmTrack(id, generation || 0, 0);
            }
          }
          tryAdopt(30);
        },

        adoptCurrentVideo: function(id, startSeconds, generation, shouldPlay) {
          window.__otoCurrentGeneration = generation || 0;
          window.__otoCurrentVideoId = id;
          window.__otoUserPaused = (shouldPlay === false);

          const v = document.querySelector('video');
          if (v) {
            if (typeof startSeconds === 'number' && startSeconds >= 0) v.currentTime = startSeconds;
            if (shouldPlay && !window.__otoUserPaused) attemptPlay(v);
          }
          const mp = document.getElementById('movie_player');
          if (mp) {
            if (typeof startSeconds === 'number' && startSeconds >= 0 && typeof mp.seekTo === 'function') {
              mp.seekTo(startSeconds, true);
            }
            if (shouldPlay && !window.__otoUserPaused && typeof mp.playVideo === 'function') {
              mp.playVideo();
            }
          }
          confirmTrack(id, generation || 0, 0);
        },

        play: function() {
          window.__otoUserPaused = false;
          const v = document.querySelector('video');
          attemptPlay(v);
        },

        pause: function() {
          window.__otoUserPaused = true;
          try {
            const bar = document.querySelector('ytmusic-player-bar');
            if (bar && bar.shadowRoot) {
              const playBtn = bar.shadowRoot.querySelector('#play-pause-button');
              if (playBtn) {
                const label = (playBtn.getAttribute('aria-label') || '').toLowerCase();
                if (label.includes('pause') || label.includes('dừng')) playBtn.click();
              }
            }
          } catch(e) {}
          const v = document.querySelector('video');
          if (v && !v.paused) v.pause();
          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.pauseVideo === 'function') mp.pauseVideo();
          const player = document.querySelector('ytmusic-player');
          if (player && player.playerApi && typeof player.playerApi.pauseVideo === 'function') {
            player.playerApi.pauseVideo();
          }
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
