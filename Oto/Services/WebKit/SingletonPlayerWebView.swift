import Foundation
import WebKit
import os

/// Quản lý WebView phát nhạc đơn bản (Singleton) bền vững trên MainActor.
/// Tuyệt đối không bao giờ huỷ hoặc reload DOM để duy trì luồng âm thanh nền của iOS.
@MainActor
public final class SingletonPlayerWebView: NSObject {
    public static let shared = SingletonPlayerWebView()

    private let logger = Logger(subsystem: "com.oto.music", category: "SingletonPlayerWebView")
    private var webView: WKWebView?
    private var isBridgeReady: Bool = false
    private var pendingVideoId: String?

    public var onPlaybackStateChange: ((Int) -> Void)?
    public var onPositionUpdate: ((TimeInterval, TimeInterval) -> Void)?
    public var onTrackEnded: (() -> Void)?
    public var onError: ((Int) -> Void)?

    private override init() {
        super.init()
        setupWebView()
    }

    /// Khởi tạo và nạp DOM phát nhạc một lần duy nhất lúc khởi động app.
    private func setupWebView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "otoPlayback")

        let config = WebKitManager.shared.makePlayerConfiguration()
        config.userContentController = contentController

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

        let baseURL = URL(string: "https://music.youtube.com")
        wv.loadHTMLString(Self.playerBridgeHTML, baseURL: baseURL)
        self.webView = wv
        logger.info("SingletonPlayerWebView đã được khởi tạo và nạp HTML bridge.")
    }

    private static let playerBridgeHTML = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body { margin: 0; background: black; overflow: hidden; }
        #player { width: 100vw; height: 100vh; }
      </style>
    </head>
    <body>
      <div id="player"></div>
      <script>
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        var firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            playerVars: {
              'autoplay': 1,
              'playsinline': 1,
              'controls': 0,
              'origin': 'https://music.youtube.com'
            },
            events: {
              'onReady': onPlayerReady,
              'onStateChange': onPlayerStateChange,
              'onError': onPlayerError
            }
          });
        }

        function onPlayerReady(event) {
          window.webkit.messageHandlers.otoPlayback.postMessage({ type: 'ready' });
          setInterval(function() {
            if (player && player.getCurrentTime) {
              var cur = player.getCurrentTime() || 0;
              var dur = player.getDuration() || 0;
              window.webkit.messageHandlers.otoPlayback.postMessage({
                type: 'timeUpdate',
                currentTime: cur,
                duration: dur
              });
            }
          }, 250);
        }

        function onPlayerStateChange(event) {
          window.webkit.messageHandlers.otoPlayback.postMessage({
            type: 'stateChange',
            state: event.data
          });
        }

        function onPlayerError(event) {
          window.webkit.messageHandlers.otoPlayback.postMessage({
            type: 'error',
            code: event.data
          });
        }

        window.otoPlayer = {
          loadVideo: function(id, startSeconds) {
            if (player && player.loadVideoById) {
              player.loadVideoById({ videoId: id, startSeconds: startSeconds || 0 });
            }
          },
          play: function() {
            if (player && player.playVideo) player.playVideo();
          },
          pause: function() {
            if (player && player.pauseVideo) player.pauseVideo();
          },
          seekTo: function(seconds) {
            if (player && player.seekTo) player.seekTo(seconds, true);
          }
        };
      </script>
    </body>
    </html>
    """

    // MARK: - Playback Controls (Bridge JS)

    /// Nạp và phát bài hát mới qua JS Bridge mà KHÔNG reload lại DOM.
    public func loadVideo(id: String, startSeconds: TimeInterval = 0) {
        guard isBridgeReady else {
            pendingVideoId = id
            logger.info("Bridge chưa sẵn sàng, đã đưa track vào hàng đợi chờ phát.")
            return
        }

        let js = "window.otoPlayer.loadVideo('\(id)', \(startSeconds));"
        webView?.evaluateJavaScript(js)
        logger.info("Đã gửi lệnh loadVideo qua JS bridge.")
    }

    /// Tiếp tục phát nhạc.
    public func play() {
        webView?.evaluateJavaScript("window.otoPlayer.play();")
    }

    /// Tạm dừng nhạc.
    public func pause() {
        webView?.evaluateJavaScript("window.otoPlayer.pause();")
    }

    /// Nhảy đến vị trí thời gian chỉ định.
    public func seek(to position: TimeInterval) {
        webView?.evaluateJavaScript("window.otoPlayer.seekTo(\(position));")
    }
}

// MARK: - WKScriptMessageHandler
extension SingletonPlayerWebView: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            isBridgeReady = true
            logger.info("JS Bridge IFrame Player đã sẵn sàng.")
            if let pending = pendingVideoId {
                pendingVideoId = nil
                loadVideo(id: pending)
            }

        case "stateChange":
            if let stateCode = body["state"] as? Int {
                // YT.PlayerState: -1 (unstarted), 0 (ended), 1 (playing), 2 (paused), 3 (buffering), 5 (cued)
                onPlaybackStateChange?(stateCode)
                if stateCode == 0 {
                    onTrackEnded?()
                }
            }

        case "timeUpdate":
            let cur = body["currentTime"] as? TimeInterval ?? 0
            let dur = body["duration"] as? TimeInterval ?? 0
            onPositionUpdate?(cur, dur)

        case "error":
            let code = body["code"] as? Int ?? -1
            logger.error("Lỗi trình phát WebView:")
            onError?(code)

        default:
            break
        }
    }
}
