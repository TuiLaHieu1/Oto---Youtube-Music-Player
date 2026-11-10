import Foundation
import WebKit
import os

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

        // Cho phép các iframe và subframe tải tài nguyên DRM, auth và media luồng
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
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
            if host.hasSuffix("youtube.com") {
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
        logger.info("WebView đã nạp xong: \(webView.url?.absoluteString ?? "unknown")")
        webView.evaluateJavaScript(PlayerBridgeScript.source) { [weak self] _, _ in
            self?.checkReadyAndFlush()
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("WebContent process bị terminate bởi iOS, kiểm tra phục hồi...")
        isBridgeReady = false

        guard crashRetryCount < maxCrashRetries else {
            logger.error("Đã vượt quá giới hạn thử lại sau crash (\(self.maxCrashRetries) lần).")
            onError?(-999, currentGeneration, currentLoadedVideoId ?? "")
            return
        }

        crashRetryCount += 1
        logger.info("Yêu cầu ViewModel/StateMachine phục hồi playback (lần retry: \(self.crashRetryCount))...")
        onRecoveryRequired?()
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
