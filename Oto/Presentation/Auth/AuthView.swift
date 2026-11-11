import SwiftUI
import WebKit
import os

/// Màn hình đăng nhập tài khoản Google để đồng bộ YouTube Music.
public struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading: Bool = true
    @State private var webView: WKWebView?
    public var onLoginSuccess: (() -> Void)?

    public init(onLoginSuccess: (() -> Void)? = nil) {
        self.onLoginSuccess = onLoginSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AuthWebViewRepresentable(
                    isLoading: $isLoading,
                    webView: $webView
                ) {
                    onLoginSuccess?()
                    dismiss()
                }

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(OtoTheme.accent)
                }
            }
            .navigationTitle("Đăng nhập Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        Task { @MainActor in
                            let saved = await WebKitManager.shared.syncCookiesToStorage()
                            if saved && CookieStorage.shared.hasValidSession {
                                try? await SessionStore.shared.handleSignInSuccess()
                                onLoginSuccess?()
                            }
                            dismiss()
                        }
                    }
                    .foregroundStyle(OtoTheme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        webView?.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(OtoTheme.accent)
                    }
                }
            }
        }
    }
}

/// UIViewRepresentable bọc WKWebView để người dùng thực hiện luồng đăng nhập an toàn.
struct AuthWebViewRepresentable: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var webView: WKWebView?
    var onLoginSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isLoading: $isLoading,
            onLoginSuccess: onLoginSuccess
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WebKitManager.shared.makePlayerConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)

        // ADR Note: Cấu hình Safari macOS User-Agent là một giải pháp tình thế (workaround)
        // để xử lý hạn chế embedded webview ('disallowed_useragent') của Google OAuth.
        // Đây là giả thuyết vận hành cần được theo dõi thực tế và không được xem là
        // cơ chế đăng nhập chính thức được Google cam kết hỗ trợ lâu dài.
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator

        // URL đăng nhập YouTube Music chính thức kèm chuyển hướng hoàn tất qua action_handle_signin
        let authURLString = "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3"
            + "&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue"
            + "%26app%3Ddesktop%26hl%3Den%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F"

        if let url = URL(string: authURLString) {
            wv.load(URLRequest(url: url))
        }

        Task { @MainActor in
            self.webView = wv
        }

        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let logger = Logger(subsystem: "com.oto.music", category: "AuthWebView")
        @Binding var isLoading: Bool
        var onLoginSuccess: () -> Void
        private var hasHandledSuccess: Bool = false

        init(
            isLoading: Binding<Bool>,
            onLoginSuccess: @escaping () -> Void
        ) {
            self._isLoading = isLoading
            self.onLoginSuccess = onLoginSuccess
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            guard !hasHandledSuccess, let url = webView.url else { return }

            let host = url.host?.lowercased() ?? ""
            let isTargetHost = host.contains("music.youtube.com")
                || (host.contains("youtube.com") && !url.path.contains("ServiceLogin"))

            // Kiểm tra trạng thái cookie thực tế từ WebKit cookie store
            Task { @MainActor in
                let store = WKWebsiteDataStore.default().httpCookieStore
                let cookies = await store.allCookies()
                let hasValidToken = cookies.contains { cookie in
                    let name = cookie.name
                    let domain = cookie.domain.lowercased()
                    let isGoogleOrYT = domain.contains("youtube.com") || domain.contains("google.com")
                    return isGoogleOrYT && (name == "SAPISID" || name == "LOGIN_INFO" || name == "__Secure-3PAPISID")
                }

                if isTargetHost && hasValidToken {
                    guard !self.hasHandledSuccess else { return }
                    self.hasHandledSuccess = true
                    do {
                        try await SessionStore.shared.handleSignInSuccess()
                        self.logger.info("Đã đăng nhập thành công và đồng bộ phiên Keychain.")
                        await WebKitManager.shared.restoreSession()
                        self.onLoginSuccess()
                    } catch {
                        self.logger.error("Đăng nhập thất bại: \(error.localizedDescription)")
                        self.hasHandledSuccess = false
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
            logger.error("Lỗi điều hướng AuthWebView: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Mở tất cả các popup, cửa sổ xác thực 2FA/passkey trực tiếp trên cùng một webview
            if let target = navigationAction.targetFrame {
                if !target.isMainFrame {
                    webView.load(navigationAction.request)
                }
            } else {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
