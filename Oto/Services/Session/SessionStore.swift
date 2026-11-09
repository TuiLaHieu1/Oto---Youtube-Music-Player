import Foundation
import Observation
import os

/// Quản lý vòng đời phiên người dùng tập trung, hỗ trợ fencing callback cũ khi sign-out.
@MainActor
@Observable
public final class SessionStore {
    public static let shared = SessionStore()
    private let logger = Logger(subsystem: "com.oto.music", category: "SessionStore")

    public private(set) var sessionGeneration: Int = 0
    public private(set) var isAuthenticated: Bool = false

    private init() {
        self.isAuthenticated = CookieStorage.shared.hasValidSession
    }

    /// Kiểm tra lại phiên làm việc từ Keychain.
    public func refreshSessionState() {
        self.isAuthenticated = CookieStorage.shared.hasValidSession
    }

    /// Đăng nhập thành công: tăng session generation và đồng bộ trạng thái
    public func handleSignInSuccess() async {
        sessionGeneration += 1
        await WebKitManager.shared.syncCookiesToStorage()
        self.isAuthenticated = true
        logger.info("SessionStore: Đã đăng nhập phiên mới (gen: \(self.sessionGeneration)).")
    }

    /// Đăng xuất: thực hiện hủy request, reset player, xóa memory & disk caches và cập nhật UI.
    public func signOut(playerVM: PlayerViewModel? = nil) async {
        sessionGeneration += 1
        logger.info("SessionStore: Bắt đầu đăng xuất (gen: \(self.sessionGeneration))...")

        // 1. Hủy toàn bộ request API đang bay
        await YTMusicClient.shared.invalidateSession()

        // 2. Tạm dừng và reset WebKit engine về trang blank
        playerVM?.pause()
        SingletonPlayerWebView.shared.resetForSignOut()

        // 3. Xóa bộ đệm đĩa và Keychain
        await WebKitManager.shared.clearSession()

        // 4. Cập nhật trạng thái UI
        self.isAuthenticated = false
        logger.info("SessionStore: Đăng xuất hoàn tất.")
    }
}
