import SwiftUI
import OtoCore

/// Điểm khởi nhập chính của ứng dụng Oto (音).
@main
struct OtoApp: App {
    @State private var playerVM: PlayerViewModel
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    init() {
        URLCache.shared.memoryCapacity = 64 * 1024 * 1024
        URLCache.shared.diskCapacity = 256 * 1024 * 1024

        let vm = PlayerViewModel()
        _playerVM = State(initialValue: vm)

        Task { @MainActor in
            await WebKitManager.shared.restoreSession()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(playerVM: playerVM)
                .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
        }
    }
}

enum AppAppearance: String, CaseIterable {
    static let storageKey = "app_appearance"
    case system, light, dark

    var label: LocalizedStringKey {
        switch self {
        case .system: "Theo hệ thống"
        case .light: "Sáng"
        case .dark: "Tối"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
