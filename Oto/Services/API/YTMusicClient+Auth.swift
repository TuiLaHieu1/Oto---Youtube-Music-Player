import CryptoKit
import Foundation

extension YTMusicClient {
    /// Tạo Cookie header chỉ với cookie hợp lệ cho host đích.
    public static func buildCookieHeader(
        cookies: [HTTPCookie],
        targetHost: String = "music.youtube.com"
    ) -> String {
        let valid = cookies.filter { CookieStorage.matchesHost($0, host: targetHost) }
        var cookieDict: [String: (value: String, isSpecific: Bool)] = [:]

        for cookie in valid {
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let isSpecific = domain == targetHost.lowercased()
            if let existing = cookieDict[cookie.name] {
                if !existing.isSpecific && isSpecific {
                    cookieDict[cookie.name] = (cookie.value, true)
                }
            } else {
                cookieDict[cookie.name] = (cookie.value, isSpecific)
            }
        }

        return cookieDict.map { "\($0.key)=\($0.value.value)" }.sorted().joined(separator: "; ")
    }

    /// Tạo SAPISIDHASH từ cookie YouTube phù hợp với host đích.
    public static func buildAuthorizationHeader(
        cookies: [HTTPCookie],
        origin: String = "https://music.youtube.com",
        timestamp: Int? = nil
    ) -> String? {
        let youtubeCookies = cookies.filter {
            !$0.value.isEmpty && CookieStorage.isYouTubeDomain($0.domain)
        }
        guard let cookie = youtubeCookies.first(where: { $0.name == "__Secure-3PAPISID" })
            ?? youtubeCookies.first(where: { $0.name == "SAPISID" }) else {
            return nil
        }

        let time = timestamp ?? Int(Date().timeIntervalSince1970)
        let input = "\(time) \(cookie.value) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "SAPISIDHASH \(time)_\(digest)"
    }

    func attachAuthHeaders(to request: inout URLRequest, cookies: [HTTPCookie]) {
        let cookieHeader = Self.buildCookieHeader(cookies: cookies)
        guard !cookieHeader.isEmpty else { return }

        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        request.setValue("true", forHTTPHeaderField: "X-Youtube-Bootstrap-Logged-In")

        if let authorization = Self.buildAuthorizationHeader(cookies: cookies) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
    }
}
