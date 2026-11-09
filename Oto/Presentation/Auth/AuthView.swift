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
                        .tint(.red)
                }
            }
            .navigationTitle("Đăng nhập Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        webView?.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
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

        // Sử dụng desktop Safari User-Agent để vượt qua hạn chế "disallowed_useragent" của Google
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

        DispatchQueue.main.async {
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

            // Chỉ kích hoạt thành công khi đã chuyển hướng hoàn tất về music.youtube.com
            if url.host?.contains("music.youtube.com") == true {
                hasHandledSuccess = true
                Task { @MainActor in
                    let store = webView.configuration.websiteDataStore.httpCookieStore
                    let cookies = await store.allCookies()
                    CookieStorage.shared.saveCookies(cookies)
                    self.logger.info("Đã đăng nhập thành công và lưu cookie vào Keychain (\(cookies.count) cookies).")
                    await WebKitManager.shared.restoreSession()
                    self.onLoginSuccess()
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
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
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
