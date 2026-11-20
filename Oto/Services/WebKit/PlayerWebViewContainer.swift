import SwiftUI
import WebKit
import os

/// Giữ một WebView cho cả chế độ ảnh bìa và video.
public struct PlayerWebViewContainer: UIViewRepresentable {
    private let onVideoResult: ((Bool) -> Void)?

    public init() {
        self.onVideoResult = nil
    }

    init(onVideoResult: @escaping (Bool) -> Void) {
        self.onVideoResult = onVideoResult
    }

    public func makeUIView(context: Context) -> UIView {
        let view = PlayerWebViewHost(onVideoResult: onVideoResult)
        view.isUserInteractionEnabled = false
        return view
    }

    public func updateUIView(_ view: UIView, context: Context) {
        (view as? PlayerWebViewHost)?.updateAttachment()
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        (uiView as? PlayerWebViewHost)?.detach()
    }
}

private final class PlayerWebViewHost: UIView {
    private static weak var backgroundHost: PlayerWebViewHost?
    private static weak var videoHost: PlayerWebViewHost?
    private static let logger = Logger(subsystem: "com.oto.music", category: "VideoPresentation")
    private let onVideoResult: ((Bool) -> Void)?

    init(onVideoResult: ((Bool) -> Void)?) {
        self.onVideoResult = onVideoResult
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { detach() } else { updateAttachment() }
    }

    func updateAttachment() {
        guard window != nil else { return }
        if onVideoResult != nil {
            Self.videoHost = self
        } else {
            Self.backgroundHost = self
        }
        Self.attachPlayer()
    }

    func detach() {
        if Self.videoHost === self { Self.videoHost = nil }
        if Self.backgroundHost === self { Self.backgroundHost = nil }
        Self.attachPlayer()
    }

    private static func attachPlayer() {
        guard let host = videoHost ?? backgroundHost,
              let webView = SingletonPlayerWebView.shared.webView,
              webView.superview !== host else { return }
        webView.frame = host.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(webView)
        host.updateVideoPresentation(in: webView)
    }

    private func updateVideoPresentation(in webView: WKWebView) {
        webView.callAsyncJavaScript(
            Self.presentationScript, arguments: ["showsVideo": onVideoResult != nil], in: nil, in: .page
        ) { [weak self, weak webView] result in
            guard let self, webView?.superview === self, let onVideoResult = self.onVideoResult else { return }
            let status = (try? result.get()) as? String ?? "script-error"
            Self.logger.info("Video presentation status=\(status, privacy: .public)")
            onVideoResult(status == "ready")
        }
    }

    private static let presentationScript = """
    if (location.origin !== 'https://music.youtube.com') return 'wrong-origin';
    const request = (window.__otoVideoPresentationRequest || 0) + 1;
    window.__otoVideoPresentationRequest = request;
    const marker = 'data-oto-video-presentation';
    const id = 'oto-video-presentation';
    const previous = document.querySelector('video[' + marker + ']');
    if (previous) {
      previous.hidePopover();
      previous.removeAttribute('popover');
      previous.removeAttribute(marker);
    }
    document.getElementById(id)?.remove();
    if (!showsVideo) return 'artwork';
    const expected = window.__otoCurrentVideoId;
    let video;
    let mismatchedTrack = false;
    for (let attempt = 0; attempt < 25; attempt++) {
      if (window.__otoVideoPresentationRequest !== request) return 'superseded';
      if (document.querySelector('ytmusic-dialog[opened], yt-player-error-message-renderer')) return 'blocked';
      const player = document.getElementById('movie_player');
      const active = player?.getVideoData?.()?.video_id;
      mismatchedTrack = !!(expected && active && expected !== active);
      video = document.querySelector('#movie_player video') || document.querySelector('ytmusic-player video');
      if (!mismatchedTrack && video && !video.error && video.readyState >= 2 &&
          video.videoWidth > 0 && video.videoHeight > 0) break;
      video = null;
      await new Promise(resolve => setTimeout(resolve, 150));
    }
    if (!video) return mismatchedTrack ? 'track-mismatch' : 'no-video-frame';
    if (typeof video.showPopover !== 'function' || video.hasAttribute('popover')) return 'popover-unavailable';
    const style = document.createElement('style');
    style.id = id;
    style.textContent = 'video[' + marker + ']:popover-open { position: fixed !important;' +
        'inset: 0 !important; margin: 0 !important; border: 0 !important; padding: 0 !important;' +
        'width: 100vw !important; height: 100vh !important; max-width: none !important;' +
        'max-height: none !important; transform: none !important; object-fit: contain !important;' +
        'visibility: visible !important; opacity: 1 !important; background: black !important; }';
    document.head.append(style);
    video.setAttribute(marker, '');
    video.setAttribute('popover', 'manual');
    video.showPopover();
    const bounds = video.getBoundingClientRect();
    return video.matches(':popover-open') && bounds.width > 0 && bounds.height > 0 ? 'ready' : 'no-visible-bounds';
    """
}
