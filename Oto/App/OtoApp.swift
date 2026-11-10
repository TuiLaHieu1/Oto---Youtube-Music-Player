import SwiftUI
import OtoCore

/// Điểm khởi nhập chính của ứng dụng Oto (音).
@main
struct OtoApp: App {
    @State private var playerVM: PlayerViewModel

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
        }
    }
}
