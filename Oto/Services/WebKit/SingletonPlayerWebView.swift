import Foundation
import UIKit
import WebKit
import os

/// Quản lý WebView phát nhạc đơn bản (Singleton) bền vững trên MainActor.
/// Sử dụng YouTube Music Web Player chính chủ để có đầy đủ bản quyền Widevine DRM,
/// chất lượng âm thanh gốc và tuân thủ các quy tắc bảo mật của hệ thống.
@MainActor
public final class SingletonPlayerWebView: NSObject, PlaybackBackend {
    public static let shared = SingletonPlayerWebView()

    public struct PendingPlayback: Sendable, Equatable {
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
    var pendingLoad: PendingPlayback?
    private var requestedVideoId: String?
    public private(set) var currentGeneration: Int = 0
    public private(set) var currentLoadedVideoId: String?
    public private(set) var activeDescriptor: ActivePlaybackDescriptor?

    var crashRetryCount = 0
    let maxCrashRetries = 3
    /// WebContent đã bị iOS tắt và chưa nạp lại; lệnh Play kế tiếp phải dựng lại player.
    var needsReloadOnPlay = false

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

    typealias CommandExecutor = @MainActor (
        String, [String: Any], @escaping @MainActor (Result<Any, Error>) -> Void
    ) -> Void
    var commandExecutor: CommandExecutor?
    var bridgeURLForTesting: URL?
    var deliveryToken: UUID?
    var diagnosticGeneration = -1
    var diagnosticSamples = 0
    var diagnosticRejectionLogged = false

    init(forTesting: Bool = false) {
        super.init()
        if !forTesting { setupWebView() }
    }

    /// Khởi tạo và cấu hình WebView một lần duy nhất lúc khởi động app.
    private func setupWebView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "otoPlayback")
        contentController.add(self, name: "otoLog")

        contentController.addUserScript(WKUserScript(
            source: PlayerDiagnosticScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        let userScript = WKUserScript(
            source: PlayerBridgeScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(userScript)
        for source in [PlayerIntentScript.source, PlayerPlayabilityScript.source] {
            contentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }

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
        guard startSeconds.isFinite, startSeconds >= 0, generation >= 0,
              let url = Self.watchURL(for: id) else { return }
        if id != requestedVideoId { crashRetryCount = 0 }
        needsReloadOnPlay = false
        currentGeneration = generation
        requestedVideoId = id
        deliveryToken = nil
        pendingLoad = PendingPlayback(
            id: id, startSeconds: startSeconds, generation: generation, shouldPlay: shouldPlay
        )
        activeDescriptor = ActivePlaybackDescriptor(
            id: id, generation: generation, position: startSeconds, shouldPlay: shouldPlay
        )
        if isBridgeReady, Self.videoID(from: webView?.url ?? bridgeURLForTesting) != nil {
            flushPendingPlayback()
        } else {
            isBridgeReady = false
            webView?.load(URLRequest(url: url))
        }
    }

    public func play() {
        updatePlaybackIntent(shouldPlay: true)
        if needsReloadOnPlay, let descriptor = activeDescriptor {
            crashRetryCount = 0
            loadVideo(
                id: descriptor.id, startSeconds: descriptor.position,
                generation: descriptor.generation, shouldPlay: true
            )
            return
        }
        guard isBridgeReady else { return }
        webView?.evaluateJavaScript("if (window.otoPlayer) window.otoPlayer.play();")
    }

    public func pause() {
        updatePlaybackIntent(shouldPlay: false)
        guard isBridgeReady else { return }
        webView?.evaluateJavaScript("if (window.otoPlayer) window.otoPlayer.pause();")
    }

    private func updatePlaybackIntent(shouldPlay: Bool) {
        if let pendingLoad { self.pendingLoad = pendingLoad.setting(shouldPlay: shouldPlay) }
        if let descriptor = activeDescriptor {
            activeDescriptor = ActivePlaybackDescriptor(
                id: descriptor.id, generation: descriptor.generation,
                position: descriptor.position, shouldPlay: shouldPlay
            )
        }
    }

    public func seek(to position: TimeInterval) {
        guard position.isFinite, position >= 0 else { return }
        if let pendingLoad { self.pendingLoad = pendingLoad.seeking(to: position) }
        if let descriptor = activeDescriptor {
            activeDescriptor = ActivePlaybackDescriptor(
                id: descriptor.id, generation: descriptor.generation,
                position: position, shouldPlay: descriptor.shouldPlay
            )
        }
        guard isBridgeReady else { return }
        webView?.callAsyncJavaScript(
            "if (window.otoPlayer) window.otoPlayer.seekTo(position);",
            arguments: ["position": position], in: nil, in: .page
        )
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
        deliveryToken = nil
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
        flushPendingPlayback()
    }

    func flushPendingPlayback() {
        guard isBridgeReady, deliveryToken == nil, let pending = pendingLoad else { return }
        let token = UUID()
        deliveryToken = token
        let method = pending.id == currentLoadedVideoId ? "adoptCurrentVideo"
            : (Self.videoID(from: webView?.url ?? bridgeURLForTesting) == pending.id ? "adoptLoadedVideo" : "loadVideo")
        let script = """
        const player = window.otoPlayer;
        if (!player || typeof player[method] !== 'function') throw new Error('OTO_BRIDGE_NOT_READY');
        player[method](id, startSeconds, generation, shouldPlay);
        return true;
        """
        let arguments: [String: Any] = [
            "method": method, "id": pending.id, "startSeconds": pending.startSeconds,
            "generation": pending.generation, "shouldPlay": pending.shouldPlay
        ]
        let completion: @MainActor (Result<Any, Error>) -> Void = { [weak self] result in
            guard let self, self.deliveryToken == token,
                  self.currentGeneration == pending.generation,
                  self.requestedVideoId == pending.id else { return }
            self.deliveryToken = nil
            if case .success(let accepted) = result, accepted as? Bool == true {
                if self.pendingLoad == pending { self.pendingLoad = nil }
                self.flushPendingPlayback()
            } else {
                self.isBridgeReady = false
                self.onError?(-998, pending.generation, pending.id)
            }
        }
        if let commandExecutor { commandExecutor(script, arguments, completion) } else if let webView {
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page, completionHandler: completion)
        } else { completion(.failure(URLError(.cannotConnectToHost))) }
    }

    static func watchURL(for id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        var url = URLComponents(string: "https://music.youtube.com/watch")
        url?.queryItems = [URLQueryItem(name: "v", value: id)]
        return url?.url
    }

    static func videoID(from url: URL?) -> String? {
        guard let url, url.scheme == "https", url.host == "music.youtube.com", url.path == "/watch" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
    }
}

// MARK: - Message Handlers

extension SingletonPlayerWebView {
    func handleMessageBody(_ body: [String: Any], type: String) {
        if type != "timeUpdate" { logger.info("JS Bridge message: \(type)") }
        switch type {
        case "playbackDiagnostic":
            logPlaybackDiagnostic(body)
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
        case "remotePlayTrace":
            logRemotePlayTrace(body)
        case "error":
            handleError(body)
        default:
            break
        }
    }

    private func logRemotePlayTrace(_ body: [String: Any]) {
        guard let identity = validatedIdentity(from: body),
              let paused = body["paused"] as? Bool,
              let visible = body["visible"] as? Bool,
              let focused = body["focused"] as? Bool,
              let blocked = body["blocked"] as? Bool else { return }
        let appState = UIApplication.shared.applicationState.rawValue
        logger.notice("""
            Playback remote trace t=\(ProcessInfo.processInfo.systemUptime) gen=\(identity.generation) \
            pauseGuard=\(paused) visible=\(visible) focused=\(focused) blocked=\(blocked) appState=\(appState)
            """)
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
        let src = body["endedSource"] as? String ?? "unknown"
        logger.info("trackEnded endedSource=\(src, privacy: .public) gen=\(identity.generation)")
        onTrackEnded?(identity.generation, identity.trackId)
    }

    private func handleRemoteCommand(_ body: [String: Any]) {
        guard validatedIdentity(from: body) != nil,
              let command = body["command"] as? String else { return }

        let commands = ["play", "pause", "next", "previous", "seek"]
        guard commands.contains(command) else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        logger.info("""
            Playback remote t=\(timestamp) source=web \
            command=\(command, privacy: .public) gen=\(self.currentGeneration)
            """)
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
