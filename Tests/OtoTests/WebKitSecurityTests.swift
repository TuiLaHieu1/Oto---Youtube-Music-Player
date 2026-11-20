import Foundation
import Testing
@testable import Oto

@Suite("WebKit navigation and playback URL security")
struct WebKitSecurityTests {
    @Test("navigation allowlist rejects lookalike and unrelated hosts")
    @MainActor
    func navigationAllowlistUsesDomainBoundaries() {
        #expect(SingletonPlayerWebView.isAllowedNavigationHost("music.youtube.com"))
        #expect(SingletonPlayerWebView.isAllowedNavigationHost("accounts.google.com"))
        #expect(SingletonPlayerWebView.isAllowedNavigationHost("r1.googlevideo.com"))
        #expect(!SingletonPlayerWebView.isAllowedNavigationHost("notyoutube.com"))
        #expect(!SingletonPlayerWebView.isAllowedNavigationHost("youtube.com.evil.test"))
        #expect(!SingletonPlayerWebView.isAllowedNavigationHost("evil.test"))
        #expect(!SingletonPlayerWebView.isYouTubeHost("notyoutube.com"))
        #expect(SingletonPlayerWebView.isYouTubeHost("music.youtube.com"))
    }

    @Test("video ID được mã hóa thành một query item thay vì ghép vào URL")
    @MainActor
    func playbackURLKeepsVideoIDInSingleQueryItem() throws {
        let url = try #require(SingletonPlayerWebView.watchURL(for: "video&redirect=evil.test"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "music.youtube.com")
        #expect(components.path == "/watch")
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.name == "v")
        #expect(components.queryItems?.first?.value == "video&redirect=evil.test")
        #expect(SingletonPlayerWebView.watchURL(for: "") == nil)
    }

    @Test("origin validation chấp nhận cổng 443 và 0 cho https://music.youtube.com, từ chối origin không hợp lệ")
    @MainActor
    func originValidationAcceptsExpectedPortsAndRejectsUntrustedOrigins() {
        let ytmHost = "music.youtube.com"

        // Chấp nhận: https://music.youtube.com với cổng 443 hoặc cổng 0 (mặc định trên iOS WebKit)
        #expect(SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: ytmHost, port: 443))
        #expect(SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: ytmHost, port: 0))
        #expect(SingletonPlayerWebView.isTrustedSecurityOrigin(scheme: "https", host: ytmHost, port: 443))
        #expect(SingletonPlayerWebView.isTrustedSecurityOrigin(scheme: "https", host: ytmHost, port: 0))

        // Từ chối protocol không an toàn (HTTP hoặc các protocol khác)
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "http", host: ytmHost, port: 80))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "http", host: ytmHost, port: 443))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "http", host: ytmHost, port: 0))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "ftp", host: ytmHost, port: 21))

        // Từ chối host không được ủy quyền hoặc lookalike (ví dụ: evilyoutube.com)
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: "evilyoutube.com", port: 443))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: "evilyoutube.com", port: 0))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: "youtube.com", port: 443))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(
            protocol: "https",
            host: "notmusic.youtube.com",
            port: 443
        ))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(
            protocol: "https",
            host: "music.youtube.com.attacker.com",
            port: 443
        ))

        // Từ chối cổng không chuẩn
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: ytmHost, port: 8080))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: ytmHost, port: 8443))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: ytmHost, port: 80))
        #expect(!SingletonPlayerWebView.isTrustedSecurityOrigin(protocol: "https", host: ytmHost, port: 1))
    }

    @Test("Page load xong (didFinish) nhưng bridge chưa ready không làm mất lệnh phát")
    @MainActor
    func pageLoadFinishedBeforeBridgeReadyPreservesPendingPlayback() {
        let player = SingletonPlayerWebView(forTesting: true)

        // 1. Khởi tạo lệnh phát khi bridge chưa ready
        player.pendingLoad = SingletonPlayerWebView.PendingPlayback(
            id: "race_track_456",
            startSeconds: 0,
            generation: 2,
            shouldPlay: true
        )
        #expect(!player.isBridgeReady)
        #expect(player.pendingLoad != nil)

        // 2. didFinish hoàn tất (page load xong navigation), nhưng JS bridge chưa gửi message 'ready'
        player.handleNavigationDidFinish(in: nil)

        // Khẳng định: didFinish KHÔNG được coi bridge là ready và KHÔNG được flush mất pendingLoad
        #expect(!player.isBridgeReady)
        #expect(player.pendingLoad != nil)
        #expect(player.pendingLoad?.id == "race_track_456")
        #expect(player.pendingLoad?.generation == 2)
        #expect(player.pendingLoad?.shouldPlay == true)

        // 3. Người dùng thay đổi ý định (pause, seek) trong lúc bridge đang chờ nạp
        player.pause()
        #expect(player.pendingLoad?.shouldPlay == false)

        player.seek(to: 35.5)
        #expect(player.pendingLoad?.startSeconds == 35.5)

        // 4. JS bridge gửi message 'ready' thông qua message handler
        player.handleMessageBody(["type": "ready"], type: "ready")

        // Khẳng định: Sau khi bridge thực sự ready, trạng thái bridge chuyển thành ready và generation được cập nhật
        #expect(player.isBridgeReady)
        #expect(player.currentGeneration == 2)
    }
}
