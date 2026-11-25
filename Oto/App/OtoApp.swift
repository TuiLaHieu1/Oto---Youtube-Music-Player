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
        SessionStore.shared.registerResetHandler { [weak vm] in
            vm?.clearPlaybackResumePoint()
            vm?.clearForSignOut()
        }
        SessionStore.shared.registerSignInHandler { [weak vm] in
            Task { @MainActor [weak vm] in await vm?.preparePlaybackResumePoint() }
        }

        Task { @MainActor in
            await WebKitManager.shared.restoreSession()
            await vm.preparePlaybackResumePoint()
        }
        #if DEBUG && OTO_STREAM_PROBE
        // Khảo sát: chạy bước 1 một lần khi app được mở kèm biến môi trường (chỉ bản Debug có cờ).
        if let videoID = ProcessInfo.processInfo.environment["OTO_PROBE_AUTORUN_VIDEO"] {
            Task {
                let result = await PythonStreamResolver.resolve(videoID: videoID)
                if let url = result.url { _ = await StreamProbeSection.fetchCheck(url) }
            }
        }
        #endif
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
