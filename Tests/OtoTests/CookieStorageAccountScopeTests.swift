import Foundation
import Testing
@testable import Oto

@Suite("Cookie-based account scope")
struct CookieStorageAccountScopeTests {
    @Test("HTTP 401 của guest không được phân loại là phiên đăng nhập hết hạn")
    func unauthorizedGuestRequestDoesNotExpireSession() {
        #expect(YTMusicClient.unauthorizedResponseDisposition(isAuthenticated: false) == .authenticationRequired)
        #expect(YTMusicClient.unauthorizedResponseDisposition(isAuthenticated: true) == .sessionExpired)
    }

    @Test("Cookie xác thực YouTube rỗng không được xem là phiên hợp lệ hoặc ký Authorization")
    func emptyYouTubeAuthCookieIsRejected() {
        let emptyCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "",
            .domain: ".youtube.com",
            .path: "/"
        ])

        guard let emptyCookie else {
            Issue.record("Không thể tạo fixture HTTPCookie rỗng")
            return
        }

        #expect(!CookieStorage.hasValidCatalogAuthorization(cookies: [emptyCookie]))
        #expect(!CookieStorage.hasValidYouTubeSession(cookies: [emptyCookie]))
        #expect(CookieStorage.opaqueAccountId(cookies: [emptyCookie]) == nil)
        #expect(YTMusicClient.buildAuthorizationHeader(cookies: [emptyCookie], timestamp: 1_700_000_000) == nil)
    }

    @Test("SpeedDialPinStore dùng cùng opaque YouTube account ID để phân vùng pin")
    @MainActor
    func speedDialPinsUseOpaqueAccountScope() {
        let accountId = String(repeating: "a", count: 64)
        #expect(SpeedDialPinStore.storageKey(accountId: accountId) == "oto_speed_dial_pins_user_aaaaaaaaaaaa")
        #expect(SpeedDialPinStore.storageKey(accountId: nil) == "oto_speed_dial_pins_guest")
    }

    @Test("opaque account ID ignores same-named Google cookies")
    func opaqueAccountIdUsesYouTubeDomain() {
        let googleCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "google-session",
            .domain: ".google.com",
            .path: "/"
        ])
        let youtubeCookie = HTTPCookie(properties: [
            .name: "SAPISID",
            .value: "youtube-session",
            .domain: ".youtube.com",
            .path: "/"
        ])

        guard let googleCookie, let youtubeCookie else {
            Issue.record("Không thể tạo fixture HTTPCookie")
            return
        }

        let googleOnly = CookieStorage.opaqueAccountId(cookies: [googleCookie])
        let googleFirst = CookieStorage.opaqueAccountId(cookies: [googleCookie, youtubeCookie])
        let youtubeFirst = CookieStorage.opaqueAccountId(cookies: [youtubeCookie, googleCookie])

        #expect(googleOnly == nil)
        #expect(googleFirst != nil)
        #expect(googleFirst == youtubeFirst)
    }
}
