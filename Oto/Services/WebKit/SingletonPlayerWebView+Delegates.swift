import Foundation
import WebKit
import os

// MARK: - WKNavigationDelegate

extension SingletonPlayerWebView: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let host = url.host?.lowercased() ?? ""
        let scheme = url.scheme?.lowercased() ?? ""

        // Cho phép trang blank nội bộ
        if scheme == "about" && url.absoluteString == "about:blank" {
            decisionHandler(.allow)
            return
        }

        // Bắt buộc HTTPS
        guard scheme == "https" else {
            logger.warning("Chặn navigation không dùng HTTPS: \(url.absoluteString)")
            decisionHandler(.cancel)
            return
        }

        // Bắt buộc host thuộc danh sách cho phép của YouTube Music Player và Google Services
        let isAllowedHost = host == "music.youtube.com"
            || host == "accounts.google.com"
            || host.hasSuffix(".youtube.com")
            || host.hasSuffix(".google.com")
            || host.hasSuffix(".googlevideo.com")
        guard isAllowedHost else {
            logger.warning("Chặn navigation ngoài allowlist: \(url.absoluteString)")
            decisionHandler(.cancel)
            return
        }

        // Với link navigation từ người dùng, chỉ cho phép trên các domain YouTube
        if navigationAction.navigationType == .linkActivated {
            if host == "youtube.com" || host.hasSuffix(".youtube.com") {
                decisionHandler(.allow)
            } else {
                logger.warning("Chặn click link ngoài allowlist: \(url.absoluteString)")
                decisionHandler(.cancel)
            }
            return
        }

        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("WebView đã nạp navigation; đang chờ handshake của player.")
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        handleWebContentTermination()
    }
    func handleWebContentTermination() {
        logger.error("WebContent process bị terminate bởi iOS, kiểm tra phục hồi...")
        isBridgeReady = false
        needsReloadOnPlay = true
        logger.notice("""
            Lifecycle webContentTerminated t=\(ProcessInfo.processInfo.systemUptime) \
            retry=\(self.crashRetryCount) gen=\(self.currentGeneration)
            """)

        guard crashRetryCount < maxCrashRetries else {
            logger.error("Đã vượt quá giới hạn thử lại sau crash (\(self.maxCrashRetries) lần).")
            onError?(-999, currentGeneration, currentLoadedVideoId ?? "")
            return
        }

        crashRetryCount += 1
        logger.info("Yêu cầu ViewModel/StateMachine phục hồi playback (lần retry: \(self.crashRetryCount))...")
        onRecoveryRequired?()
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error, phase: "provisional navigation")
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error, phase: "navigation")
    }

    private func handleNavigationError(_ error: Error, phase: String) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            logger.debug("Bỏ qua navigation cancelled (-999) trong \(phase)")
            return
        }

        logger.error("Lỗi WebKit \(phase): \(error.localizedDescription) (code: \(nsError.code))")
        isBridgeReady = false
        let trackId = activeDescriptor?.id ?? currentLoadedVideoId ?? ""
        onError?(nsError.code, currentGeneration, trackId)
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
            && (origin.port == 0 || origin.port == 443)
        guard isTrusted else {
            logger.warning("Bỏ qua message từ origin không được ủy quyền: \(origin.host)")
            return
        }

        // otoLog: nhận string thẳng từ JS diagnostic (không phải dict)
        if message.name == "otoLog" {
            let text = message.body as? String ?? "\(message.body)"
            logger.debug("JS-diag: \(text, privacy: .public)")
            return
        }

        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        handleMessageBody(body, type: type)
    }
}

// MARK: - PendingPlayback Fluent Modifiers

extension SingletonPlayerWebView.PendingPlayback {
    public func setting(shouldPlay: Bool) -> SingletonPlayerWebView.PendingPlayback {
        SingletonPlayerWebView.PendingPlayback(
            id: id,
            startSeconds: startSeconds,
            generation: generation,
            shouldPlay: shouldPlay
        )
    }

    public func seeking(to position: TimeInterval) -> SingletonPlayerWebView.PendingPlayback {
        SingletonPlayerWebView.PendingPlayback(
            id: id,
            startSeconds: position,
            generation: generation,
            shouldPlay: shouldPlay
        )
    }
}
