import SwiftUI
import WebKit

/// View đại diện (UIViewRepresentable) gắn SingletonPlayerWebView vào view hierarchy của iOS.
/// Ngăn chặn WebKit tạm dừng (throttle/freeze) tiến trình phát nhạc trong nền.
public struct PlayerWebViewContainer: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.isUserInteractionEnabled = false
        container.alpha = 0.01

        if let webView = SingletonPlayerWebView.shared.webView {
            webView.frame = container.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(webView)
        }
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {}
}
