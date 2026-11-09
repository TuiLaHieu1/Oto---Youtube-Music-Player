import Foundation
import WebKit
import os

/// Quản lý WebView phát nhạc đơn bản (Singleton) bền vững trên MainActor.
/// Sử dụng trực tiếp YouTube Music Web Player chính chủ để có đầy đủ bản quyền Widevine DRM,
/// chất lượng âm thanh gốc và không bị chặn bởi các hạn chế nhúng (embed restrictions).
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

        let userScript = WKUserScript(
            source: PlayerBridgeScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(userScript)

        let config = WebKitManager.shared.makePlayerConfiguration()
        config.userContentController = contentController

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        wv.navigationDelegate = self

        self.webView = wv
        logger.info("SingletonPlayerWebView đã được khởi tạo.")

        Task { @MainActor in
            await WebKitManager.shared.restoreSession()
            if let initialURL = URL(string: "https://music.youtube.com") {
                wv.load(URLRequest(url: initialURL))
                self.logger.info("Đã bắt đầu nạp YouTube Music tại https://music.youtube.com")
            }
        }
    }

    // MARK: - Playback Controls (Safe JS Bridge)

    /// Nạp và phát bài hát mới qua callAsyncJavaScript an toàn không có nguy cơ JS injection.
    public func loadVideo(id: String, startSeconds: TimeInterval = 0, generation: Int = 0) {
        currentGeneration = generation
        guard isBridgeReady else {
            pendingLoad = PendingPlayback(id: id, startSeconds: startSeconds, generation: generation)
            logger.info("Bridge chưa sẵn sàng, đã lưu lệnh phát vào hàng đợi (id: \(id)).")
            if let currentURL = webView?.url?.absoluteString, !currentURL.contains("music.youtube.com") {
                if let watchURL = URL(string: "https://music.youtube.com/watch?v=\(id)") {
                    webView?.load(URLRequest(url: watchURL))
                }
            }
            return
        }

        let jsCode = "if (window.otoPlayer) window.otoPlayer.loadVideo(id, startSeconds, generation);"
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
        logger.info("Đã gửi lệnh loadVideo qua JS Bridge (id: \(id), gen: \(generation)).")
    }

    /// Tiếp tục phát nhạc.
    public func play() {
        webView?.evaluateJavaScript("if (window.otoPlayer) window.otoPlayer.play();")
    }

    /// Tạm dừng nhạc.
    public func pause() {
        webView?.evaluateJavaScript("if (window.otoPlayer) window.otoPlayer.pause();")
    }

    /// Nhảy đến vị trí thời gian chỉ định.
    public func seek(to position: TimeInterval) {
        let jsCode = "if (window.otoPlayer) window.otoPlayer.seekTo(position);"
        webView?.callAsyncJavaScript(jsCode, arguments: ["position": position], in: nil, in: .page)
    }

    private func checkReadyAndFlush() {
        let jsCheck = """
        (function() {
            const app = document.querySelector('ytmusic-app');
            return !!(app && typeof app.resolveCommand === 'function');
        })()
        """
        webView?.evaluateJavaScript(jsCheck) { [weak self] result, _ in
            guard let self = self else { return }
            if let isReady = result as? Bool, isReady {
                self.isBridgeReady = true
                self.logger.info("ytmusic-app đã sẵn sàng qua navigation check.")
                if let pending = self.pendingLoad {
                    self.pendingLoad = nil
                    self.loadVideo(
                        id: pending.id,
                        startSeconds: pending.startSeconds,
                        generation: pending.generation
                    )
                }
            }
        }
    }

    // MARK: - Message Handlers

    fileprivate func handleMessageBody(_ body: [String: Any], type: String) {
        switch type {
        case "ready":
            isBridgeReady = true
            logger.info("JS Bridge YouTube Music đã sẵn sàng.")
            if let pending = pendingLoad {
                pendingLoad = nil
                loadVideo(id: pending.id, startSeconds: pending.startSeconds, generation: pending.generation)
            }
        case "stateChange":
            handleStateChange(body)
        case "timeUpdate":
            handleTimeUpdate(body)
        case "trackEnded":
            handleTrackEnded(body)
        case "error":
            if let code = body["code"] as? Int {
                onError?(code)
            }
        default:
            break
        }
    }

    private func handleStateChange(_ body: [String: Any]) {
        if let gen = body["generation"] as? Int, gen != currentGeneration {
            return
        }
        if let stateCode = body["state"] as? Int {
            onPlaybackStateChange?(stateCode)
        }
    }

    private func handleTimeUpdate(_ body: [String: Any]) {
        if let gen = body["generation"] as? Int, gen != currentGeneration {
            return
        }
        if let cur = body["currentTime"] as? Double,
           let dur = body["duration"] as? Double {
            onPositionUpdate?(cur, dur)
        }
    }

    private func handleTrackEnded(_ body: [String: Any]) {
        if let gen = body["generation"] as? Int, gen != currentGeneration {
            return
        }
        onTrackEnded?()
    }
}

// MARK: - WKNavigationDelegate
extension SingletonPlayerWebView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("WebView đã nạp xong: \(webView.url?.absoluteString ?? "unknown")")
        webView.evaluateJavaScript(PlayerBridgeScript.source) { [weak self] _, _ in
            self?.checkReadyAndFlush()
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("WebContent process bị terminate bởi iOS, đang khởi động lại...")
        isBridgeReady = false
        if let currentSongId = pendingLoad?.id {
            if let watchURL = URL(string: "https://music.youtube.com/watch?v=\(currentSongId)") {
                webView.load(URLRequest(url: watchURL))
            }
        } else if let homeURL = URL(string: "https://music.youtube.com") {
            webView.load(URLRequest(url: homeURL))
        }
    }
}

// MARK: - WKScriptMessageHandler
extension SingletonPlayerWebView: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame else {
            logger.warning("Bỏ qua message không xuất phát từ main frame.")
            return
        }

        let host = message.frameInfo.securityOrigin.host
        let bundleHost = Bundle.main.bundleIdentifier ?? "com.hieu.oto"
        let isTrusted = host.isEmpty
            || host == "music.youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == bundleHost
            || host == "localhost"
        guard isTrusted else {
            logger.warning("Bỏ qua message từ origin không được ủy quyền: \(host)")
            return
        }

        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        handleMessageBody(body, type: type)
    }
}
