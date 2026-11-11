import Foundation
import CryptoKit
import OtoCore
import os

/// Quản lý danh sách các mục được Ghim (Pin to Speed dial) trên màn hình chính theo chuẩn YouTube Music.
/// Dữ liệu được lưu trữ phân vùng theo tài khoản người dùng và duy trì trạng thái ghim an toàn.
@MainActor
public final class SpeedDialPinStore {
    public static let shared = SpeedDialPinStore()
    private let logger = Logger(subsystem: "com.oto.music", category: "SpeedDialPinStore")
    private let userDefaults = UserDefaults.standard
    private let maxItems: Int = 27 // Tối đa 3 trang 3x3

    private init() {}

    private var storageKey: String {
        let cookies = CookieStorage.shared.loadCookies()
        if let authCookie = cookies.first(where: { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" }) {
            let digest = SHA256.hash(data: Data(authCookie.value.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return "oto_speed_dial_pins_user_\(hex.prefix(12))"
        }
        return "oto_speed_dial_pins_guest"
    }

    /// Tải danh sách các mục đã ghim từ bộ nhớ cục bộ.
    public func loadPinnedItems() -> [SpeedDialItem] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }
        do {
            let items = try JSONDecoder().decode([SpeedDialItem].self, from: data)
            return items.map {
                var copy = $0
                copy.isPinned = true
                return copy
            }
        } catch {
            logger.error("Không thể giải mã danh sách Speed dial đã ghim: \(error.localizedDescription)")
            return []
        }
    }

    /// Lưu danh sách các mục đã ghim vào bộ nhớ cục bộ.
    public func savePinnedItems(_ items: [SpeedDialItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            userDefaults.set(data, forKey: storageKey)
            logger.info("Đã lưu \(items.count) mục ghim Speed dial.")
        } catch {
            logger.error("Không thể lưu danh sách Speed dial ghim: \(error.localizedDescription)")
        }
    }

    /// Ghim hoặc Bỏ ghim một item. Trả về `true` nếu item được ghim, `false` nếu đã bỏ ghim.
    @discardableResult
    public func togglePin(_ item: SpeedDialItem) -> Bool {
        var pinned = loadPinnedItems()
        if let index = pinned.firstIndex(where: { $0.id == item.id }) {
            pinned.remove(at: index)
            savePinnedItems(pinned)
            return false
        } else {
            var newItem = item
            newItem.isPinned = true
            pinned.insert(newItem, at: 0)
            if pinned.count > maxItems {
                pinned = Array(pinned.prefix(maxItems))
            }
            savePinnedItems(pinned)
            return true
        }
    }

    /// Kiểm tra một id có đang được ghim hay không.
    public func isPinned(id: String) -> Bool {
        loadPinnedItems().contains(where: { $0.id == id })
    }

    /// Trộn các mục đã ghim lên đầu danh sách nạp từ API.
    /// Giữ đúng giới hạn 27 mục (3 trang 3x3) và loại bỏ trùng lặp.
    public func mergePinned(with fetchedItems: [SpeedDialItem]) -> [SpeedDialItem] {
        let pinned = loadPinnedItems()
        let pinnedIds = Set(pinned.map(\.id))

        let remaining = fetchedItems.filter { !pinnedIds.contains($0.id) }
        let combined = pinned + remaining
        return Array(combined.prefix(maxItems))
    }
}
