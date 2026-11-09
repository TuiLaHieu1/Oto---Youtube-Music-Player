import SwiftUI
import OtoCore

/// Điểm khởi nhập chính của ứng dụng Oto (音).
@main
struct OtoApp: App {
    @State private var playerVM: PlayerViewModel

    init() {
        let vm = PlayerViewModel()
        _playerVM = State(initialValue: vm)

        AudioSessionManager.shared.activateSession()

        // Kết nối điều khiển audio session với PlayerViewModel
        AudioSessionManager.shared.onInterruptionBegan = { [weak vm] in
            Task { @MainActor in
                vm?.pause()
            }
        }

        AudioSessionManager.shared.onInterruptionEnded = { [weak vm] shouldResume in
            if shouldResume {
                Task { @MainActor in
                    vm?.resume()
                }
            }
        }

        AudioSessionManager.shared.onHeadphonesUnplugged = { [weak vm] in
            Task { @MainActor in
                vm?.pause()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(playerVM: playerVM)
        }
    }
}
