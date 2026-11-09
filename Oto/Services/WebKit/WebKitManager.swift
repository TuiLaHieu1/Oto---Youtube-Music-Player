import Foundation
import WebKit
import os

/// Điều phối cấu hình WebKit và đồng bộ hoá cookie phiên với Keychain.
@MainActor
public final class WebKitManager {
    public static let shared = WebKitManager()
    private let logger = Logger(subsystem: "com.oto.music", category: "WebKitManager")
    private let cookieStorage = CookieStorage.shared

    private init() {}

    /// Khôi phục các cookie từ Keychain vào WKHTTPCookieStore khi khởi chạy ứng dụng.
    public func restoreSession() async {
        let savedCookies = cookieStorage.loadCookies()
        guard !savedCookies.isEmpty else { return }

        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in savedCookies {
            await store.setCookie(cookie)
        }
        logger.info("Đã khôi phục cookie phiên vào WebKit cookie store.")
    }

    /// Sao lưu cookie từ WKHTTPCookieStore vào Keychain khi người dùng đăng nhập thành công.
    public func syncCookiesToStorage() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        cookieStorage.saveCookies(cookies)
    }

    /// Đăng xuất và dọn dẹp toàn bộ dữ liệu web của phiên người dùng.
    public func clearSession() async {
        cookieStorage.clearCookies()
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: dataTypes)
        await dataStore.removeData(ofTypes: dataTypes, for: records)
        logger.info("Đã dọn dẹp sạch toàn bộ dữ liệu phiên WebKit.")
    }

    /// Tạo cấu hình WebView tối ưu cho phát nhạc nền không gián đoạn trên iOS/iPadOS.
    public func makePlayerConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Bật phát nhạc inline và nền
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false

        // Tối ưu trang web phát nhạc
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        return config
    }
}
