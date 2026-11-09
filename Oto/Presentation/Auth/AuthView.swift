import SwiftUI
import WebKit
import os

/// Màn hình đăng nhập tài khoản Google để đồng bộ YouTube Music.
public struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    public var onLoginSuccess: (() -> Void)?

    public init(onLoginSuccess: (() -> Void)? = nil) {
        self.onLoginSuccess = onLoginSuccess
    }

    public var body: some View {
        NavigationStack {
            AuthWebViewRepresentable {
                onLoginSuccess?()
                dismiss()
            }
            .navigationTitle("Đăng nhập Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// UIViewRepresentable bọc WKWebView để người dùng thực hiện luồng đăng nhập an toàn.
struct AuthWebViewRepresentable: UIViewRepresentable {
    var onLoginSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoginSuccess: onLoginSuccess)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WebKitManager.shared.makePlayerConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attachCookieObserver(to: webView)

        // URL đăng nhập YouTube Music chính thức
        let authURLString = "https://accounts.google.com/ServiceLogin?service=youtube"
            + "&continue=https%3A%2F%2Fmusic.youtube.com%2F"
        if let url = URL(string: authURLString) {
            let request = URLRequest(url: url)
            webView.load(request)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let logger = Logger(subsystem: "com.oto.music", category: "AuthWebView")
        var onLoginSuccess: () -> Void
        private weak var cookieStore: WKHTTPCookieStore?

        init(onLoginSuccess: @escaping () -> Void) {
            self.onLoginSuccess = onLoginSuccess
        }

        func attachCookieObserver(to webView: WKWebView) {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            self.cookieStore = store
            store.add(self)
        }

        deinit {
            cookieStore?.remove(self)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                let cookies = await cookieStore.allCookies()
                CookieStorage.shared.saveCookies(cookies)

                if CookieStorage.shared.hasValidSession {
                    logger.info("Đã phát hiện phiên đăng nhập hợp lệ.")
                    onLoginSuccess()
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url?.absoluteString else { return }
            if url.contains("music.youtube.com") {
                Task { @MainActor in
                    let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                    CookieStorage.shared.saveCookies(cookies)
                    if CookieStorage.shared.hasValidSession {
                        onLoginSuccess()
                    }
                }
            }
        }
    }
}
