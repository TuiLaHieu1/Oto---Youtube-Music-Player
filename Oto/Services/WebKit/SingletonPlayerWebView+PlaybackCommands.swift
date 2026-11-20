import Foundation
import WebKit

@MainActor
extension SingletonPlayerWebView {
    static func watchURL(for videoId: String) -> URL? {
        guard !videoId.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "music.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoId)]
        return components.url
    }

    static func videoID(from url: URL?) -> String? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host?.lowercased() == "music.youtube.com",
              components.path == "/watch" else { return nil }
        return components.queryItems?.first(where: { $0.name == "v" })?.value
    }

    public func play() {
        if let pendingLoad {
            self.pendingLoad = pendingLoad.setting(shouldPlay: true)
        }
        updateActiveDescriptor(shouldPlay: true)
        guard isBridgeReady else { return }
        webView?.evaluateJavaScript("if (window.otoPlayer) window.otoPlayer.play();")
    }

    public func pause() {
        if let pendingLoad {
            self.pendingLoad = pendingLoad.setting(shouldPlay: false)
        }
        updateActiveDescriptor(shouldPlay: false)
        guard isBridgeReady else { return }
        webView?.evaluateJavaScript("if (window.otoPlayer) window.otoPlayer.pause();")
    }

    public func seek(to position: TimeInterval) {
        guard position.isFinite, position >= 0 else { return }
        if let pendingLoad {
            self.pendingLoad = pendingLoad.seeking(to: position)
        }
        if let descriptor = activeDescriptor {
            activeDescriptor = ActivePlaybackDescriptor(
                id: descriptor.id,
                generation: descriptor.generation,
                position: position,
                shouldPlay: descriptor.shouldPlay
            )
        }
        guard isBridgeReady else { return }
        webView?.callAsyncJavaScript(
            "if (window.otoPlayer) window.otoPlayer.seekTo(position);",
            arguments: ["position": position],
            in: nil,
            in: .page
        )
    }

    func adoptCurrentVideo(
        _ id: String,
        startSeconds: TimeInterval,
        generation: Int,
        shouldPlay: Bool
    ) {
        logger.info("Đồng bộ video đã nạp (gen: \(generation), seek: \(startSeconds)).")
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
    }

    func loadVideoInWatchPage(
        _ id: String,
        startSeconds: TimeInterval,
        generation: Int,
        shouldPlay: Bool,
        url: URL
    ) {
        let jsCode = "if (window.otoPlayer) window.otoPlayer.loadVideo(id, startSeconds, generation, shouldPlay);"
        let arguments: [String: Any] = [
            "id": id,
            "startSeconds": startSeconds,
            "generation": generation,
            "shouldPlay": shouldPlay
        ]
        webView?.callAsyncJavaScript(jsCode, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result {
                self?.logger.error("Lỗi gọi loadVideo JS (NSError code: \((error as NSError).code)); nạp lại URL.")
                self?.webView?.load(URLRequest(url: url))
            }
        }
        if shouldPlay {
            webView?.evaluateJavaScript("if (window.otoPlayer) window.otoPlayer.play();")
        } else {
            pause()
        }
        logger.info("Đã gửi lệnh đổi bài trong trang (gen: \(generation)).")
    }

    private func updateActiveDescriptor(shouldPlay: Bool) {
        guard let descriptor = activeDescriptor else { return }
        activeDescriptor = ActivePlaybackDescriptor(
            id: descriptor.id,
            generation: descriptor.generation,
            position: descriptor.position,
            shouldPlay: shouldPlay
        )
    }
}
