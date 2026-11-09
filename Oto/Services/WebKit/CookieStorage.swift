import Foundation
import Security
import os

/// DTO biểu diễn Cookie tương thích Codable để lưu trữ JSON thuần túy trong Keychain.
private struct CodableCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresDate = cookie.expiresDate
        self.isSecure = cookie.isSecure
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        return HTTPCookie(properties: properties)
    }
}

/// Quản lý lưu trữ cookie phiên làm việc Google/YouTube an toàn trong iOS Keychain.
public final class CookieStorage: @unchecked Sendable {
    public static let shared = CookieStorage()
    private let logger = Logger(subsystem: "com.oto.music", category: "CookieStorage")
    private let keychainService = "com.oto.music.auth-cookies"
    private let keychainAccount = "google-session"

    private init() {}

    /// Lưu danh sách cookie phiên làm việc vào Keychain (mã hoá an toàn).
    public func saveCookies(_ cookies: [HTTPCookie]) {
        let authCookies = cookies.filter { isRelevantAuthCookie($0.name) }
        guard !authCookies.isEmpty else { return }

        let codableCookies = authCookies.map { CodableCookie(cookie: $0) }
        do {
            let data = try JSONEncoder().encode(codableCookies)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var newQuery = query
                newQuery[kSecValueData as String] = data
                newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(newQuery as CFDictionary, nil)
            }
            logger.info("Đã lưu an toàn phiên làm việc vào Keychain.")
        } catch {
            logger.error("Không thể mã hoá cookie để lưu Keychain.")
        }
    }

    /// Tải danh sách cookie phiên từ Keychain.
    public func loadCookies() -> [HTTPCookie] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return []
        }

        do {
            let codableList = try JSONDecoder().decode([CodableCookie].self, from: data)
            return codableList.compactMap(\.httpCookie)
        } catch {
            logger.error("Không thể giải mã cookie từ Keychain.")
            return []
        }
    }

    /// Xoá sạch phiên đăng nhập trong Keychain.
    public func clearCookies() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        logger.info("Đã xoá cookie phiên làm việc.")
    }

    /// Kiểm tra đã có phiên đăng nhập hợp lệ hay chưa.
    public var hasValidSession: Bool {
        let cookies = loadCookies()
        let names = Set(cookies.map(\.name))
        return names.contains("SAPISID") || names.contains("SID")
    }

    /// Lọc các cookie cốt lõi cần thiết cho xác thực YouTube Music.
    private func isRelevantAuthCookie(_ name: String) -> Bool {
        let relevant: Set<String> = [
            "SAPISID", "SSID", "SID", "HSID", "__Secure-3PAPISID",
            "__Secure-1PAPISID", "__Secure-3PSID", "__Secure-1PSID",
            "LOGIN_INFO", "APISID", "PREF"
        ]
        return relevant.contains(name)
    }
}
