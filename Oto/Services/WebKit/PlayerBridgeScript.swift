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
          const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.otoPlayback;
          if (h) h.postMessage(Object.assign({ type: type }, data || {}));
        } catch(e) {}
      }
      function signalReady() {
        if (window.otoPlayer && !window.__otoAppReady
            && (document.querySelector('ytmusic-app') || document.querySelector('video'))) {
          window.__otoAppReady = true;
          post('ready');
        }
      }
      const style = document.createElement('style');
      style.textContent = 'html, body { overflow: hidden !important; background-color: #000 !important; } ' +
        'ytmusic-popup-container, ytmusic-dialog, ytmusic-guide-renderer { display: none !important; }';
      document.head.appendChild(style);
      let boundVideo = null;
      window.__otoUserPaused = true;
      window.__otoCurrentGeneration = 0;
      window.__otoCurrentVideoId = '';
      function playerVideoId() {
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
        } catch(e) {}
        return '';
      }
      function actualVideoId() {
        const active = playerVideoId();
        if (active) return active;
        try {
          const urlParam = new URL(window.location.href).searchParams.get('v');
          return urlParam || window.__otoCurrentVideoId || '';
        } catch(e) { return window.__otoCurrentVideoId || ''; }
      }
      function messageIdentity() {
        return { generation: window.__otoCurrentGeneration || 0, videoId: actualVideoId() };
      }
      // WebKit sở hữu thẻ media trên Lock Screen; chuyển transport về queue và intent native.
      // Pause phải đặt cờ ngay để vòng poll không tự phát lại trước khi native xử lý.
      function installMediaSessionPolicy() {
        if (!navigator.mediaSession || typeof navigator.mediaSession.setActionHandler !== 'function') return;
        if (window.__otoMediaSessionPolicyInstalled) return;
        window.__otoMediaSessionPolicyInstalled = true;
        const original = navigator.mediaSession.setActionHandler.bind(navigator.mediaSession);
        const transport = function(command) {
          return function() {
            if (command === 'pause') window.__otoUserPaused = true;
            // Khi trang đã lấy lại focus, bỏ Play được giao muộn lúc mở app.
            // Chỉ lệnh play đã qua native mới được gỡ cờ pause.
            const body = Object.assign({ command: command }, messageIdentity());
            if (command === 'play') {
              const paused = window.__otoUserPaused === true;
              const visible = document.visibilityState === 'visible';
              const focused = visible && document.hasFocus();
              const blocked = paused && focused;
              post('remotePlayTrace', Object.assign(body, { paused, visible, focused, blocked }));
              if (blocked) return;
            }
            post('remoteCommand', body);
          };
        };
        const next = transport('next');
        const previous = transport('previous');
        const play = transport('play');
        const pause = transport('pause');
        navigator.mediaSession.setActionHandler = function(action, handler) {
          if (action === 'seekforward' || action === 'seekbackward') {
            return original(action, null);
          }
          if (action === 'play') return original(action, play);
          if (action === 'pause') return original(action, pause);
          if (action === 'nexttrack') return original(action, next);
          if (action === 'previoustrack') return original(action, previous);
          return original(action, handler);
        };
        try { original('seekforward', null); } catch(e) {}
        try { original('seekbackward', null); } catch(e) {}
        try { original('play', play); } catch(e) {}
        try { original('pause', pause); } catch(e) {}
        try { original('nexttrack', next); } catch(e) {}
        try { original('previoustrack', previous); } catch(e) {}
      }
      function isCurrentRequest(id, generation) {
        return window.__otoCurrentVideoId === id && window.__otoCurrentGeneration === (generation || 0);
      }
      function confirmTrack(expectedId, generation, attempt) {
        if (!isCurrentRequest(expectedId, generation)) return;
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
      // Chỉ báo ended một lần cho mỗi lượt phát; ended trễ của lần load trước không được xử lý.
      function notifyTrackEnded(v, source) {
        if (!v || v.__otoAwaitingPlaybackStart || v.__otoTrackEndedFired) return;
        if (!(v.duration > 5 && v.currentTime >= v.duration - 0.6)) return;
        v.__otoTrackEndedFired = true;
        post('stateChange', Object.assign({ state: 0, endedSource: source || 'video' }, messageIdentity()));
        post('trackEnded', Object.assign({ endedSource: source || 'video' }, messageIdentity()));
      }
      try {
        if (!localStorage.getItem('oto-volume-migration-v1')) {
          localStorage.removeItem('yt-player-volume');
          localStorage.setItem('oto-volume-migration-v1', 'true');
        }
      } catch(e) {}
      const boundMoviePlayers = new WeakSet();
      function hookMoviePlayer(mp) {
        if (!mp || boundMoviePlayers.has(mp)) return;
        boundMoviePlayers.add(mp);
        if (typeof mp.addEventListener === 'function') {
          try {
            mp.addEventListener('onStateChange', function(event) {
              const state = (typeof event === 'object' && event !== null && 'data' in event) ? event.data : event;
              if (state === 1) {
                post('stateChange', Object.assign({ state: 1 }, messageIdentity()));
              } else if (state === 2) {
                if (!isAdActive()) post('stateChange', Object.assign({ state: 2 }, messageIdentity()));
              } else if (state === 0) {
                const v = document.querySelector('video');
                const msg = 'YTM-s0 e=' + (v ? v.ended : '?') +
                  ' f=' + (v ? !!v.__otoTrackEndedFired : '?') + ' g=' + (window.__otoCurrentGeneration || 0);
                try { window.webkit.messageHandlers.otoLog.postMessage(msg); } catch(e2) {}
                notifyTrackEnded(v, 'ytmState0');
              }
            });
          } catch(e) {}
        }
      }
      function isAdActive() {
        const mp = document.getElementById('movie_player');
        if (mp && mp.classList && (mp.classList.contains('ad-showing') || mp.classList.contains('ad-interrupting'))) {
          return true;
        }
        const player = document.querySelector('ytmusic-player');
        const api = (player && player.playerApi) || mp;
        if (api && typeof api.getPresentingPlayerType === 'function' && api.getPresentingPlayerType(true) === 2) {
          return true;
        }
        return false;
      }
      function attemptPlay(v) {
        if (window.__otoUserPaused) return;
        const requestId = window.__otoCurrentVideoId;
        const requestGeneration = window.__otoCurrentGeneration;
        // Chọn một đường điều khiển; không phát đồng thời qua DOM và player API.
        const mp = document.getElementById('movie_player');
        const player = document.querySelector('ytmusic-player');
        const api = mp && typeof mp.playVideo === 'function' ? mp : player && player.playerApi;
        if (api && typeof api.playVideo === 'function') {
          hookMoviePlayer(api);
          try {
            if (typeof api.unMute === 'function') api.unMute();
            api.playVideo();
            return;
          } catch(e) {}
        }
        const targetVideo = v || document.querySelector('video');
        if (targetVideo) {
          try {
            targetVideo.muted = false;
            targetVideo.defaultMuted = false;
            const p = targetVideo.play();
            if (p && typeof p.catch === 'function') {
              p.catch(function(error) {
                if (isCurrentRequest(requestId, requestGeneration) && window.otoReportPlaybackDiagnostic) {
                  window.otoReportPlaybackDiagnostic('playRejected', error && error.name);
                }
                setTimeout(function() {
                  if (!window.__otoUserPaused && isCurrentRequest(requestId, requestGeneration)
                      && targetVideo === document.querySelector('video')) {
                    targetVideo.muted = false;
                    try { targetVideo.play(); } catch(e3) {}
                  }
                }, 250);
              });
            }
          } catch(e) {}
        }
      }
      function checkAndNotifyEnded(v, source) { notifyTrackEnded(v, source); }
      function hookVideo(v) {
        if (!v || v === boundVideo) return;
        boundVideo = v;
        v.__otoAwaitingPlaybackStart = true;
        if (!v.paused && v.readyState >= 2) v.__otoAwaitingPlaybackStart = false;
        if (!window.__otoUserPaused) attemptPlay(v);
        function ensureUnmuted(target) {
          if (!window.__otoUserPaused && target) {
            try { if (target.muted) target.muted = false; } catch(e) {}
          }
        }
        v.addEventListener('play', function() {
          ensureUnmuted(v);
          post('stateChange', Object.assign({ state: 3 }, messageIdentity()));
        });
        v.addEventListener('playing', function() {
          ensureUnmuted(v);
          v.__otoAwaitingPlaybackStart = false;
          v.__otoTrackEndedFired = false;
          post('stateChange', Object.assign({ state: 1 }, messageIdentity()));
        });
        v.addEventListener('pause', function() {
          if (!isAdActive()) {
            if (v.duration > 5 && v.currentTime >= v.duration - 0.8) {
              checkAndNotifyEnded(v);
            } else {
              post('stateChange', Object.assign({ state: 2 }, messageIdentity()));
              const pauseId = window.__otoCurrentVideoId;
              const pauseGeneration = window.__otoCurrentGeneration;
              if (!window.__otoUserPaused && !v.ended) setTimeout(function() {
                if (isCurrentRequest(pauseId, pauseGeneration) && v === document.querySelector('video')) attemptPlay(v);
              }, 300);
            }
          }
        });
        v.addEventListener('ended', function() { if (!isAdActive()) checkAndNotifyEnded(v, 'videoEnded'); });
        v.addEventListener('timeupdate', function() {
          if (!isAdActive()) {
            ensureUnmuted(v);
            if (v.duration > 5 && v.currentTime > 0 && v.currentTime < v.duration - 1) {
              v.__otoAwaitingPlaybackStart = false;
              v.__otoTrackEndedFired = false;
            }
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
          if (v.paused && !window.__otoUserPaused && !isAdActive()) attemptPlay(v);
        }
        const mp = document.getElementById('movie_player');
        if (mp) hookMoviePlayer(mp);
        signalReady();
      }, 200);
      window.otoPlayer = {
        loadVideo: function(id, startSeconds, generation, shouldPlay) {
          window.__otoUserPaused = (shouldPlay === false);
          window.__otoCurrentGeneration = generation || 0;
          window.__otoCurrentVideoId = id;
          if (window.otoSchedulePlaybackDiagnostics) window.otoSchedulePlaybackDiagnostics(id, generation);
          if (boundVideo) boundVideo.__otoAwaitingPlaybackStart = true;
          const mp = document.getElementById('movie_player');
          if (mp && typeof mp.loadVideoById === 'function') {
            try {
              hookMoviePlayer(mp);
              try { mp.loadVideoById(id, startSeconds || 0); }
              catch(e1) { mp.loadVideoById({ videoId: id, startSeconds: startSeconds || 0 }); }
              if (typeof mp.unMute === 'function') mp.unMute();
              if (shouldPlay !== false && !window.__otoUserPaused) attemptPlay(document.querySelector('video'));
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
                if (isCurrentRequest(id, generation) && actualVideoId() !== id) {
                  window.location.assign('https://music.youtube.com/watch?v=' + encodeURIComponent(id));
                }
              }, 750);
              return;
            } catch(e) {}
          }
          window.location.href = 'https://music.youtube.com/watch?v=' + encodeURIComponent(id);
        },
        adoptLoadedVideo: function(id, startSeconds, generation, shouldPlay) {
          const active = playerVideoId();
          if (active && active !== id) {
            window.otoPlayer.loadVideo(id, startSeconds, generation, shouldPlay);
            return;
          }
          window.__otoCurrentGeneration = generation || 0;
          window.__otoCurrentVideoId = id;
          if (window.otoSchedulePlaybackDiagnostics) window.otoSchedulePlaybackDiagnostics(id, generation);
          window.__otoUserPaused = (shouldPlay === false);
          function tryAdopt(retries) {
            if (!isCurrentRequest(id, generation)) return;
            const v = document.querySelector('video');
            const mp = document.getElementById('movie_player');
            if (v || (mp && typeof mp.playVideo === 'function')) {
              if (v) {
                v.__otoAwaitingPlaybackStart = true;
                if (!v.paused && v.readyState >= 2) v.__otoAwaitingPlaybackStart = false;
                if (typeof startSeconds === 'number' && startSeconds > 0) v.currentTime = startSeconds;
                if (!v.paused && v.readyState >= 2) {
                  post('stateChange', Object.assign({ state: 1 }, messageIdentity()));
                }
              }
              if (mp) {
                hookMoviePlayer(mp);
                if (typeof mp.seekTo === 'function' && typeof startSeconds === 'number' && startSeconds > 0) {
                  try { mp.seekTo(startSeconds, true); } catch(e) {}
                }
                if (typeof mp.getPlayerState === 'function' && mp.getPlayerState() === 1) {
                  post('stateChange', Object.assign({ state: 1 }, messageIdentity()));
                }
              }
              if (shouldPlay && !window.__otoUserPaused) attemptPlay(v);
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
          const active = playerVideoId();
          const video = document.querySelector('video');
          const restartsCompletedVideo = startSeconds === 0 && video && (video.ended || video.__otoTrackEndedFired);
          if (restartsCompletedVideo || (active && active !== id)) {
            window.otoPlayer.loadVideo(id, startSeconds, generation, shouldPlay);
            return;
          }
          window.__otoCurrentGeneration = generation || 0;
          window.__otoCurrentVideoId = id;
          if (window.otoSchedulePlaybackDiagnostics) window.otoSchedulePlaybackDiagnostics(id, generation);
          window.__otoUserPaused = (shouldPlay === false);
          const v = document.querySelector('video');
          if (v) {
            v.__otoAwaitingPlaybackStart = true;
            if (!v.paused && v.readyState >= 2) v.__otoAwaitingPlaybackStart = false;
            if (typeof startSeconds === 'number' && startSeconds >= 0) v.currentTime = startSeconds;
            if (!v.paused && v.readyState >= 2) {
              post('stateChange', Object.assign({ state: 1 }, messageIdentity()));
            }
          }
          const mp = document.getElementById('movie_player');
          if (mp) {
            hookMoviePlayer(mp);
            if (typeof startSeconds === 'number' && startSeconds >= 0 && typeof mp.seekTo === 'function') {
              try { mp.seekTo(startSeconds, true); } catch(e) {}
            }
            if (typeof mp.getPlayerState === 'function' && mp.getPlayerState() === 1) {
              post('stateChange', Object.assign({ state: 1 }, messageIdentity()));
            }
          }
          if (shouldPlay && !window.__otoUserPaused) attemptPlay(v);
          confirmTrack(id, generation || 0, 0);
        },
        play: function() {
          window.__otoUserPaused = false;
          attemptPlay(document.querySelector('video'));
        },
        pause: function() {
          window.__otoUserPaused = true;
          try {
            const bar = document.querySelector('ytmusic-player-bar');
            const playBtn = bar && bar.shadowRoot && bar.shadowRoot.querySelector('#play-pause-button');
            if (playBtn) {
              const label = (playBtn.getAttribute('aria-label') || '').toLowerCase();
              if (label.includes('pause') || label.includes('dừng')) playBtn.click();
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
      installMediaSessionPolicy();
      signalReady();
    })();
    """
