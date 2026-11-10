import Foundation
import WebKit
import os

/// Quản lý WebView phát nhạc đơn bản (Singleton) bền vững trên MainActor.
/// Sử dụng YouTube Music Web Player chính chủ để có đầy đủ bản quyền Widevine DRM,
/// chất lượng âm thanh gốc và tuân thủ các quy tắc bảo mật của hệ thống.
@MainActor
public final class SingletonPlayerWebView: NSObject, PlaybackBackend {
    public static let shared = SingletonPlayerWebView()

    public struct PendingPlayback: Sendable {
        public let id: String
        public let startSeconds: TimeInterval
        public let generation: Int
        public let shouldPlay: Bool

        public init(id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool = true) {
            self.id = id
            self.startSeconds = startSeconds
            self.generation = generation
            self.shouldPlay = shouldPlay
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

    let logger = Logger(subsystem: "com.oto.music", category: "SingletonPlayerWebView")
    public private(set) var webView: WKWebView?
    var isBridgeReady: Bool = false
    private var pendingLoad: PendingPlayback?
    private var requestedVideoId: String?
    public private(set) var currentGeneration: Int = 0
    public private(set) var currentLoadedVideoId: String?
    public private(set) var activeDescriptor: ActivePlaybackDescriptor?

    var crashRetryCount = 0
    let maxCrashRetries = 3

    public var onTrackActivated: ((_ trackId: String, _ generation: Int) -> Void)?
    public var onPlaybackStateChange: ((_ state: Int, _ generation: Int, _ trackId: String) -> Void)?
    public var onPositionUpdate: ((
        _ current: TimeInterval,
        _ duration: TimeInterval,
        _ generation: Int,
        _ trackId: String
    ) -> Void)?
    public var onTrackEnded: ((_ generation: Int, _ trackId: String) -> Void)?
    public var onError: ((_ code: Int, _ generation: Int, _ trackId: String) -> Void)?
    public var onRemoteCommand: ((PlaybackRemoteCommand) -> Void)?
    public var onRecoveryRequired: (() -> Void)?

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
    public func loadVideo(
        id: String,
        startSeconds: TimeInterval = 0,
        generation: Int = 0,
        shouldPlay: Bool = true
    ) {
        if id != currentLoadedVideoId {
            crashRetryCount = 0
        }
        currentGeneration = generation
        requestedVideoId = id
        activeDescriptor = ActivePlaybackDescriptor(
            id: id,
            generation: generation,
            position: startSeconds,
            shouldPlay: shouldPlay
        )

        // Nếu video đã được nạp sẵn trong DOM, đồng bộ generation mới và seek tới startSeconds thay vì chỉ gọi play()
        if id == currentLoadedVideoId, isBridgeReady {
            logger.info("Video \(id) đã nạp sẵn, adoptCurrentVideo (gen: \(generation), seek: \(startSeconds)).")
            let jsCode = """
            if (window.otoPlayer) window.otoPlayer.adoptCurrentVideo(id, startSeconds, generation, shouldPlay);
            """
            let arguments: [String: Any] = [
                "id": id,
                "startSeconds": startSeconds,
                "generation": generation,
                "shouldPlay": shouldPlay
            ]
            webView?.callAsyncJavaScript(jsCode, arguments: arguments, in: nil, in: .page)
            return
        }

        let watchURLString = "https://music.youtube.com/watch?v=\(id)"
        guard let watchURL = URL(string: watchURLString) else { return }

        let isAlreadyOnWatch = webView?.url?.path.contains("watch") == true

        // Nếu chưa ở trang watch hoặc bridge chưa ready, lưu pendingLoad và nạp URL
        guard isBridgeReady, isAlreadyOnWatch else {
            pendingLoad = PendingPlayback(
                id: id,
                startSeconds: startSeconds,
                generation: generation,
                shouldPlay: shouldPlay
            )
            logger.info("Nạp trực tiếp URL phát nhạc: \(watchURLString) (gen: \(generation)).")
            isBridgeReady = false
            webView?.load(URLRequest(url: watchURL))
            return
        }

        let jsCode = "if (window.otoPlayer) window.otoPlayer.loadVideo(id, startSeconds, generation, shouldPlay);"
        let arguments: [String: Any] = [
            "id": id,
            "startSeconds": startSeconds,
            "generation": generation,
            "shouldPlay": shouldPlay
        ]

        webView?.callAsyncJavaScript(jsCode, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result {
                self?.logger.error("Lỗi gọi loadVideo JS: \(error.localizedDescription), nạp lại URL.")
                self?.webView?.load(URLRequest(url: watchURL))
            }
        }
        if !shouldPlay {
            pause()
        }
        logger.info("Đã gửi lệnh đổi bài trong trang (id: \(id), gen: \(generation)).")
    }

    /// Tiếp tục phát nhạc.
    public func play() {
        if let desc = activeDescriptor {
            activeDescriptor = ActivePlaybackDescriptor(
                id: desc.id,
                generation: desc.generation,
                position: desc.position,
                shouldPlay: true
            )
        }
        webView?.evaluateJavaScript("if (window.otoPlayer) window.otoPlayer.play();")
    }

    /// Tạm dừng nhạc.
    public func pause() {
        if let desc = activeDescriptor {
            activeDescriptor = ActivePlaybackDescriptor(
                id: desc.id,
                generation: desc.generation,
                position: desc.position,
                shouldPlay: false
            )
        }
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
                loadVideo(
                    id: pending.id,
                    startSeconds: pending.startSeconds,
                    generation: pending.generation,
                    shouldPlay: pending.shouldPlay
                )
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
        requestedVideoId = nil
        isBridgeReady = false
        if let blankURL = URL(string: "about:blank") {
            webView?.load(URLRequest(url: blankURL))
        }
    }

    func checkReadyAndFlush() {
        isBridgeReady = true
        if let pending = pendingLoad {
            pendingLoad = nil
            currentGeneration = pending.generation

            if webView?.url?.absoluteString.contains(pending.id) == true {
                logger.info(
                    "Trang watch \(pending.id) đã ready, gọi adoptLoadedVideo (gen: \(pending.generation))."
                )
                let jsCode = """
                if (window.otoPlayer) window.otoPlayer.adoptLoadedVideo(id, startSeconds, generation, shouldPlay);
                """
                let arguments: [String: Any] = [
                    "id": pending.id,
                    "startSeconds": pending.startSeconds,
                    "generation": pending.generation,
                    "shouldPlay": pending.shouldPlay
                ]
                webView?.callAsyncJavaScript(jsCode, arguments: arguments, in: nil, in: .page)
            } else {
                loadVideo(
                    id: pending.id,
                    startSeconds: pending.startSeconds,
                    generation: pending.generation,
                    shouldPlay: pending.shouldPlay
                )
            }
        }
    }
}

// MARK: - Message Handlers

extension SingletonPlayerWebView {
    func handleMessageBody(_ body: [String: Any], type: String) {
        logger.info("JS Bridge message: \(type)")
        switch type {
        case "ready":
            checkReadyAndFlush()
        case "stateChange":
            handleStateChange(body)
        case "trackActivated":
            handleTrackActivated(body)
        case "timeUpdate":
            handleTimeUpdate(body)
        case "trackEnded":
            handleTrackEnded(body)
        case "remoteCommand":
            handleRemoteCommand(body)
        case "error":
            handleError(body)
        default:
            break
        }
    }

    private func validatedIdentity(from body: [String: Any]) -> (generation: Int, trackId: String)? {
        guard let generation = body["generation"] as? Int,
              generation == currentGeneration,
              let trackId = body["videoId"] as? String,
              !trackId.isEmpty,
              trackId == requestedVideoId else {
            return nil
        }
        return (generation, trackId)
    }

    private func handleTrackActivated(_ body: [String: Any]) {
        guard let identity = validatedIdentity(from: body) else { return }
        currentLoadedVideoId = identity.trackId
        onTrackActivated?(identity.trackId, identity.generation)
    }

    private func handleStateChange(_ body: [String: Any]) {
        guard let identity = validatedIdentity(from: body) else { return }
        if let stateCode = body["state"] as? Int {
            // Khi engine đã phát ổn định (stateCode == 1: playing), reset retry count của recovery episode
            if stateCode == 1 {
                crashRetryCount = 0
            }
            onPlaybackStateChange?(stateCode, identity.generation, identity.trackId)
        }
    }

    private func handleTimeUpdate(_ body: [String: Any]) {
        guard let identity = validatedIdentity(from: body) else { return }
        guard let cur = body["currentTime"] as? Double, !cur.isNaN, !cur.isInfinite else {
            return
        }
        let dur = (body["duration"] as? Double).flatMap { (!$0.isNaN && !$0.isInfinite && $0 > 0) ? $0 : nil } ?? 0

        if cur > 0, let videoId = currentLoadedVideoId {
            let wasPlaying = activeDescriptor?.shouldPlay ?? true
            activeDescriptor = ActivePlaybackDescriptor(
                id: videoId,
                generation: identity.generation,
                position: cur,
                shouldPlay: wasPlaying
            )
        }

        onPositionUpdate?(cur, dur, identity.generation, identity.trackId)
    }

    private func handleTrackEnded(_ body: [String: Any]) {
        guard let identity = validatedIdentity(from: body) else { return }
        onTrackEnded?(identity.generation, identity.trackId)
    }

    private func handleRemoteCommand(_ body: [String: Any]) {
        guard validatedIdentity(from: body) != nil,
              let command = body["command"] as? String else { return }

        switch command {
        case "play": onRemoteCommand?(.play)
        case "pause": onRemoteCommand?(.pause)
        case "next": onRemoteCommand?(.next)
        case "previous": onRemoteCommand?(.previous)
        case "seek":
            guard let position = body["position"] as? Double,
                  position.isFinite,
                  position >= 0 else { return }
            onRemoteCommand?(.seek(position))
        default: break
        }
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
