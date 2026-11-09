import SwiftUI
import WebKit

/// View đại diện (UIViewRepresentable) gắn SingletonPlayerWebView vào view hierarchy của iOS.
/// Ngăn chặn WebKit tạm dừng (throttle/freeze) tiến trình phát nhạc trong nền.
public struct PlayerWebViewContainer: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        container.isUserInteractionEnabled = false

        if let webView = SingletonPlayerWebView.shared.webView {
            webView.frame = container.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(webView)
        }
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if let webView = SingletonPlayerWebView.shared.webView, webView.superview == nil {
            webView.frame = uiView.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            uiView.addSubview(webView)
        }
    }
}
