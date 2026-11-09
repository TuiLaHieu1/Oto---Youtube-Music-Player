import Foundation
import WebKit
import os

/// Quản lý WebView phát nhạc đơn bản (Singleton) bền vững trên MainActor.
/// Tuyệt đối không bao giờ huỷ hoặc reload DOM để duy trì luồng âm thanh nền của iOS.
@MainActor
public final class SingletonPlayerWebView: NSObject {
    public static let shared = SingletonPlayerWebView()

    private struct PendingPlayback {
        let id: String
        let startSeconds: TimeInterval
        let generation: Int
    }

    private let logger = Logger(subsystem: "com.oto.music", category: "SingletonPlayerWebView")
    public private(set) var webView: WKWebView?
    private var isBridgeReady: Bool = false
    private var pendingLoad: PendingPlayback?
    public private(set) var currentGeneration: Int = 0

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

        let baseURL = URL(string: "https://com.oto.music")
        wv.loadHTMLString(Self.playerBridgeHTML, baseURL: baseURL)
        self.webView = wv
        logger.info("SingletonPlayerWebView đã được khởi tạo và nạp HTML bridge.")
    }

    private static let playerBridgeHTML = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport"
            content="width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <style>
        body { margin: 0; background: black; overflow: hidden; width: 100vw; height: 100vh; }
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
        var activeGeneration = 0;

        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            width: '100%',
            height: '100%',
            playerVars: {
              'autoplay': 1,
              'playsinline': 1,
              'controls': 0,
              'rel': 0,
              'enablejsapi': 1,
              'origin': 'https://com.oto.music'
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
            if (player && typeof player.getCurrentTime === 'function') {
              var cur = player.getCurrentTime() || 0;
              var dur = player.getDuration() || 0;
              window.webkit.messageHandlers.otoPlayback.postMessage({
                type: 'timeUpdate',
                currentTime: cur,
                duration: dur,
                generation: activeGeneration
              });
            }
          }, 250);
        }

        function onPlayerStateChange(event) {
          window.webkit.messageHandlers.otoPlayback.postMessage({
            type: 'stateChange',
            state: event.data,
            generation: activeGeneration
          });
        }

        function onPlayerError(event) {
          window.webkit.messageHandlers.otoPlayback.postMessage({
            type: 'error',
            code: event.data,
            generation: activeGeneration
          });
        }

        window.otoPlayer = {
          loadVideo: function(id, startSeconds, generation) {
            activeGeneration = generation || 0;
            if (player && typeof player.loadVideoById === 'function') {
              player.loadVideoById({ videoId: id, startSeconds: startSeconds || 0 });
              if (typeof player.playVideo === 'function') {
                player.playVideo();
              }
            }
          },
          play: function() {
            if (player && typeof player.playVideo === 'function') player.playVideo();
          },
          pause: function() {
            if (player && typeof player.pauseVideo === 'function') player.pauseVideo();
          },
          seekTo: function(seconds) {
            if (player && typeof player.seekTo === 'function') player.seekTo(seconds, true);
          }
        };
      </script>
    </body>
    </html>
    """

    // MARK: - Playback Controls (Safe JS Bridge)

    /// Nạp và phát bài hát mới qua callAsyncJavaScript an toàn không có nguy cơ JS injection.
    public func loadVideo(id: String, startSeconds: TimeInterval = 0, generation: Int = 0) {
        currentGeneration = generation
        guard isBridgeReady else {
            pendingLoad = PendingPlayback(id: id, startSeconds: startSeconds, generation: generation)
            logger.info("Bridge chưa sẵn sàng, đã lưu lệnh phát vào hàng đợi.")
            return
        }

        let jsCode = "window.otoPlayer.loadVideo(id, startSeconds, generation);"
        let arguments: [String: Any] = [
            "id": id,
            "startSeconds": startSeconds,
            "generation": generation
        ]

        webView?.callAsyncJavaScript(jsCode, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result {
                self?.logger.error("Lỗi thực thi callAsyncJavaScript loadVideo: \(error.localizedDescription)")
            }
        }
        logger.info("Đã gửi lệnh loadVideo an toàn qua callAsyncJavaScript (gen: \(generation)).")
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
        let jsCode = "window.otoPlayer.seekTo(position);"
        webView?.callAsyncJavaScript(jsCode, arguments: ["position": position], in: nil, in: .page)
    }
}

// MARK: - WKScriptMessageHandler
extension SingletonPlayerWebView: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // 1. Chỉ chấp nhận message từ main frame, ngăn chặn frame giả mạo
        guard message.frameInfo.isMainFrame else {
            logger.warning("Bỏ qua message không xuất phát từ main frame.")
            return
        }

        // 2. Kiểm tra origin
        let host = message.frameInfo.securityOrigin.host
        guard host.isEmpty || host == "com.oto.music" || host == "music.youtube.com" || host == "localhost" else {
            logger.warning("Bỏ qua message từ origin không được ủy quyền: \(host)")
            return
        }

        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            isBridgeReady = true
            logger.info("JS Bridge IFrame Player đã sẵn sàng.")
            if let pending = pendingLoad {
                pendingLoad = nil
                loadVideo(id: pending.id, startSeconds: pending.startSeconds, generation: pending.generation)
            }

        case "stateChange":
            // Kiểm tra generation nếu có, bỏ qua event trễ của track cũ
            if let gen = body["generation"] as? Int, gen != currentGeneration {
                logger.info("Bỏ qua stateChange từ generation cũ (\(gen) != \(self.currentGeneration))")
                return
            }
            if let stateCode = body["state"] as? Int {
                onPlaybackStateChange?(stateCode)
                if stateCode == 0 { // YT.PlayerState.ENDED
                    onTrackEnded?()
                }
            }

        case "timeUpdate":
            if let gen = body["generation"] as? Int, gen != currentGeneration {
                return
            }
            if let cur = body["currentTime"] as? Double,
               let dur = body["duration"] as? Double {
                onPositionUpdate?(cur, dur)
            }

        case "error":
            if let code = body["code"] as? Int {
                onError?(code)
            }

        default:
            break
        }
    }
}
