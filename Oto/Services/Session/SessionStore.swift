import Foundation
import Observation
import OtoCore
import os

/// Lỗi liên quan đến xác thực và lưu trữ phiên.
public enum SessionError: LocalizedError {
    case cookieStorageFailed
    case invalidSession

    public var errorDescription: String? {
        switch self {
        case .cookieStorageFailed:
            return "Không thể lưu thông tin xác thực an toàn vào Keychain."
        case .invalidSession:
            return "Phiên đăng nhập không chứa cookie YouTube Music hợp lệ."
        }
    }
}

/// Quản lý vòng đời phiên người dùng tập trung, hỗ trợ fencing callback cũ khi sign-out.
@MainActor
@Observable
public final class SessionStore {
    public static let shared = SessionStore()
    private let logger = Logger(subsystem: "com.oto.music", category: "SessionStore")
    private var resetHandlers: [@MainActor () -> Void] = []
    private var signInHandlers: [@MainActor () -> Void] = []

    public private(set) var sessionGeneration: Int = 0
    public private(set) var isAuthenticated: Bool = false

    private init() {
        self.isAuthenticated = CookieStorage.shared.hasValidSession
    }

    /// Đăng ký handler dọn dẹp dữ liệu memory cache khi người dùng đăng xuất.
    public func registerResetHandler(_ handler: @escaping @MainActor () -> Void) {
        resetHandlers.append(handler)
    }

    /// Đăng ký handler cập nhật dữ liệu khi người dùng đăng nhập thành công.
    public func registerSignInHandler(_ handler: @escaping @MainActor () -> Void) {
        signInHandlers.append(handler)
    }

    /// Kiểm tra lại phiên làm việc từ Keychain.
    public func refreshSessionState() {
        self.isAuthenticated = CookieStorage.shared.hasValidSession
    }

    /// Đăng nhập thành công: kiểm tra và lưu cookie, chỉ kích hoạt authenticated khi lưu thành công.
    public func handleSignInSuccess() async throws {
        let saved = await WebKitManager.shared.syncCookiesToStorage()
        guard saved else {
            logger.error("SessionStore: Đồng bộ cookie sang Keychain thất bại.")
            throw SessionError.cookieStorageFailed
        }

        refreshSessionState()
        guard isAuthenticated else {
            logger.error("SessionStore: Không tìm thấy cookie phiên hợp lệ sau khi lưu.")
            throw SessionError.invalidSession
        }

        sessionGeneration += 1
        logger.info("SessionStore: Đã đăng nhập phiên mới thành công (gen: \(self.sessionGeneration)).")

        for handler in signInHandlers {
            handler()
        }
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

        // 3. Xóa bộ nhớ đệm lời bài hát trong RAM
        await MultiSourceLyricsService.shared.clearCache()

        // 4. Kích hoạt toàn bộ reset handlers (HomeViewModel memory caches, v.v.)
        for handler in resetHandlers {
            handler()
        }

        // 5. Xóa bộ đệm đĩa và Keychain
        await WebKitManager.shared.clearSession()

        // 6. Cập nhật trạng thái UI
        self.isAuthenticated = false
        logger.info("SessionStore: Đăng xuất hoàn tất.")
    }
}
