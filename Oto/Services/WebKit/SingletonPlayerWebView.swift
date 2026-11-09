import Foundation
import WebKit
import os

/// Quản lý WebView phát nhạc đơn bản (Singleton) bền vững trên MainActor.
/// Sử dụng YouTube Music Web Player chính chủ để có đầy đủ bản quyền Widevine DRM,
/// chất lượng âm thanh gốc và tuân thủ các quy tắc bảo mật của hệ thống.
@MainActor
public final class SingletonPlayerWebView: NSObject {
    public static let shared = SingletonPlayerWebView()

    public struct PendingPlayback: Sendable {
        public let id: String
        public let startSeconds: TimeInterval
        public let generation: Int

        public init(id: String, startSeconds: TimeInterval, generation: Int) {
            self.id = id
            self.startSeconds = startSeconds
            self.generation = generation
        }
    }

    public struct ActivePlaybackDescriptor: Sendable {
        public let id: String
        public let generation: Int
        public let position: TimeInterval
        public let shouldPlay: Bool

        public init(id: String, generation: Int, position: TimeInterval, shouldPlay: Bool) {
            self.id = id
            self.generation = generation
            self.position = position
            self.shouldPlay = shouldPlay
        }
    }

    private let logger = Logger(subsystem: "com.oto.music", category: "SingletonPlayerWebView")
    public private(set) var webView: WKWebView?
    private var isBridgeReady: Bool = false
    private var pendingLoad: PendingPlayback?
    public private(set) var currentGeneration: Int = 0
    public private(set) var currentLoadedVideoId: String?
    public private(set) var activeDescriptor: ActivePlaybackDescriptor?

    private var crashRetryCount = 0
    private let maxCrashRetries = 3

    public var onPlaybackStateChange: ((_ state: Int, _ generation: Int) -> Void)?
    public var onPositionUpdate: ((_ current: TimeInterval, _ duration: TimeInterval, _ generation: Int) -> Void)?
    public var onTrackEnded: ((_ generation: Int) -> Void)?
    public var onError: ((_ code: Int, _ generation: Int, _ trackId: String) -> Void)?

    private override init() {
        super.init()
        setupWebView()
    }

    /// Khởi tạo và cấu hình WebView một lần duy nhất lúc khởi động app.
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

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 240), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        wv.navigationDelegate = self

        #if DEBUG
        wv.isInspectable = true
        #endif

        self.webView = wv
        logger.info("SingletonPlayerWebView đã được khởi tạo.")

        Task { @MainActor in
            await WebKitManager.shared.restoreSession()
            self.logger.info("Phiên làm việc đã sẵn sàng để phát nhạc.")
        }
    }

    // MARK: - Playback Controls (Safe JS Bridge)

    /// Nạp và phát bài hát mới. Đảm bảo generation và startSeconds luôn được truyền chính xác tới JavaScript.
    public func loadVideo(id: String, startSeconds: TimeInterval = 0, generation: Int = 0) {
        currentGeneration = generation
        activeDescriptor = ActivePlaybackDescriptor(
            id: id,
            generation: generation,
            position: startSeconds,
            shouldPlay: true
        )
        crashRetryCount = 0

        // Nếu video đã được nạp sẵn trong DOM, đồng bộ generation mới và seek tới startSeconds thay vì chỉ gọi play()
        if id == currentLoadedVideoId, isBridgeReady {
            logger.info("Video \(id) đã nạp sẵn, adoptCurrentVideo với gen \(generation), seek \(startSeconds).")
            let jsCode = "if (window.otoPlayer) window.otoPlayer.adoptCurrentVideo(id, startSeconds, generation, true);"
            let arguments: [String: Any] = [
                "id": id,
                "startSeconds": startSeconds,
                "generation": generation
            ]
            webView?.callAsyncJavaScript(jsCode, arguments: arguments, in: nil, in: .page)
            return
        }

        let watchURLString = "https://music.youtube.com/watch?v=\(id)"
        guard let watchURL = URL(string: watchURLString) else { return }

        let isAlreadyOnWatch = webView?.url?.path.contains("watch") == true

        // Nếu chưa ở trang watch hoặc bridge chưa ready, lưu pendingLoad và nạp URL
        guard isBridgeReady, isAlreadyOnWatch else {
            currentLoadedVideoId = id
            pendingLoad = PendingPlayback(id: id, startSeconds: startSeconds, generation: generation)
            logger.info("Nạp trực tiếp URL phát nhạc: \(watchURLString) (gen: \(generation)).")
            isBridgeReady = false
            webView?.load(URLRequest(url: watchURL))
            return
        }

        currentLoadedVideoId = id
        let jsCode = "if (window.otoPlayer) window.otoPlayer.loadVideo(id, startSeconds, generation);"
        let arguments: [String: Any] = [
            "id": id,
            "startSeconds": startSeconds,
            "generation": generation
        ]

        webView?.callAsyncJavaScript(jsCode, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result {
                self?.logger.error("Lỗi gọi loadVideo JS: \(error.localizedDescription), nạp lại URL.")
                self?.webView?.load(URLRequest(url: watchURL))
            }
        }
        logger.info("Đã gửi lệnh đổi bài trong trang (id: \(id), gen: \(generation)).")
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

    /// Tải lại YouTube Music sau khi đăng nhập thành công để nạp phiên mới.
    public func reloadAfterLogin() {
        Task { @MainActor in
            await WebKitManager.shared.restoreSession()
            if let pending = pendingLoad {
                loadVideo(id: pending.id, startSeconds: pending.startSeconds, generation: pending.generation)
            } else if let homeURL = URL(string: "https://music.youtube.com") {
                isBridgeReady = false
                webView?.load(URLRequest(url: homeURL))
                logger.info("Đã nạp lại YouTube Music với phiên cookie mới sau đăng nhập.")
            }
        }
    }

    /// Đưa web view về trang trắng và dọn sạch playback descriptor khi sign out.
    public func resetForSignOut() {
        currentGeneration += 1
        pendingLoad = nil
        activeDescriptor = nil
        currentLoadedVideoId = nil
        isBridgeReady = false
        if let blankURL = URL(string: "about:blank") {
            webView?.load(URLRequest(url: blankURL))
        }
    }

    private func checkReadyAndFlush() {
        isBridgeReady = true
        crashRetryCount = 0
        if let pending = pendingLoad {
            pendingLoad = nil
            currentGeneration = pending.generation
            currentLoadedVideoId = pending.id

            if webView?.url?.absoluteString.contains(pending.id) == true {
                logger.info("Trang watch \(pending.id) đã ready, gọi adoptLoadedVideo (gen: \(pending.generation)).")
                let jsCode = """
                if (window.otoPlayer) window.otoPlayer.adoptLoadedVideo(id, startSeconds, generation, true);
                """
                let arguments: [String: Any] = [
                    "id": pending.id,
                    "startSeconds": pending.startSeconds,
                    "generation": pending.generation
                ]
                webView?.callAsyncJavaScript(jsCode, arguments: arguments, in: nil, in: .page)
            } else {
                loadVideo(
                    id: pending.id,
                    startSeconds: pending.startSeconds,
                    generation: pending.generation
                )
            }
        }
    }

    // MARK: - Message Handlers

    fileprivate func handleMessageBody(_ body: [String: Any], type: String) {
        logger.info("JS Bridge message: \(type)")
        switch type {
        case "ready":
            checkReadyAndFlush()
        case "stateChange":
            handleStateChange(body)
        case "timeUpdate":
            handleTimeUpdate(body)
        case "trackEnded":
            handleTrackEnded(body)
        case "error":
            handleError(body)
        default:
            break
        }
    }

    private func handleStateChange(_ body: [String: Any]) {
        guard let gen = body["generation"] as? Int, gen == currentGeneration else {
            return
        }
        if let stateCode = body["state"] as? Int {
            onPlaybackStateChange?(stateCode, gen)
        }
    }

    private func handleTimeUpdate(_ body: [String: Any]) {
        guard let gen = body["generation"] as? Int, gen == currentGeneration else {
            return
        }
        guard let cur = body["currentTime"] as? Double, !cur.isNaN, !cur.isInfinite else {
            return
        }
        let dur = (body["duration"] as? Double).flatMap { (!$0.isNaN && !$0.isInfinite && $0 > 0) ? $0 : nil } ?? 0

        if cur > 0, let videoId = currentLoadedVideoId {
            activeDescriptor = ActivePlaybackDescriptor(
                id: videoId,
                generation: gen,
                position: cur,
                shouldPlay: true
            )
        }

        onPositionUpdate?(cur, dur, gen)
    }

    private func handleTrackEnded(_ body: [String: Any]) {
        guard let gen = body["generation"] as? Int, gen == currentGeneration else {
            return
        }
        onTrackEnded?(gen)
    }

    private func handleError(_ body: [String: Any]) {
        guard let gen = body["generation"] as? Int, gen == currentGeneration else {
            logger.warning("Bỏ qua lỗi từ generation cũ")
            return
        }
        let code = body["code"] as? Int ?? -1
        let trackId = body["videoId"] as? String ?? ""
        onError?(code, gen, trackId)
    }
}

// MARK: - WKNavigationDelegate
extension SingletonPlayerWebView: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Chỉ cho phép navigation https tới music.youtube.com và accounts.google.com
        let host = url.host ?? ""
        let scheme = url.scheme ?? ""

        if scheme == "about" && url.absoluteString == "about:blank" {
            decisionHandler(.allow)
            return
        }

        if scheme == "https" && (host == "music.youtube.com" || host == "accounts.google.com") {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated {
            logger.warning("Chặn navigation ngoài allowlist: \(url.absoluteString)")
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("WebView đã nạp xong: \(webView.url?.absoluteString ?? "unknown")")
        webView.evaluateJavaScript(PlayerBridgeScript.source) { [weak self] _, _ in
            self?.checkReadyAndFlush()
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("WebContent process bị terminate bởi iOS, kiểm tra phục hồi...")
        isBridgeReady = false
        currentGeneration += 1 // Fence toàn bộ callback đang treo

        guard crashRetryCount < maxCrashRetries, let descriptor = activeDescriptor else {
            logger.error("Đã vượt quá giới hạn thử lại sau crash hoặc không có bài hát active.")
            onError?(-999, currentGeneration, activeDescriptor?.id ?? "")
            return
        }

        crashRetryCount += 1
        logger.info("Đang tự động khôi phục bài hát \(descriptor.id) ở vị trí \(descriptor.position)s...")
        pendingLoad = PendingPlayback(
            id: descriptor.id,
            startSeconds: descriptor.position,
            generation: currentGeneration
        )
        if let watchURL = URL(string: "https://music.youtube.com/watch?v=\(descriptor.id)") {
            webView.load(URLRequest(url: watchURL))
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

        let origin = message.frameInfo.securityOrigin
        let isTrusted = origin.protocol == "https" && origin.host == "music.youtube.com"
        guard isTrusted else {
            logger.warning("Bỏ qua message từ origin không được ủy quyền: \(origin.host)")
            return
        }

        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        handleMessageBody(body, type: type)
    }
}
