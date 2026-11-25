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
        // Nạp yt-dlp ngay khi mở app để bài đầu tiên không phải chờ phần khởi động Python.
        Task { await PythonStreamResolver.warm() }
        // Khảo sát: chạy bước 1 một lần khi app được mở kèm biến môi trường (chỉ bản Debug có cờ).
        if let videoID = ProcessInfo.processInfo.environment["OTO_PROBE_AUTORUN_VIDEO"] {
            Task {
                let result = await PythonStreamResolver.resolve(videoID: videoID)
                if let url = result.url { _ = await StreamProbeSection.fetchCheck(url) }
            }
        }
        if ProcessInfo.processInfo.environment["OTO_PROBE_NETCHECK"] != nil {
            Task { await PythonStreamResolver.netcheck() }
        }
        // Khảo sát: phát hàng đợi thử, Next sau 20 giây, Next lần nữa sau 45 giây (bài đã nạp sẵn), Pause sau 65 giây.
        if let ids = ProcessInfo.processInfo.environment["OTO_PROBE_AUTOPLAY"]?.split(separator: ",").map(String.init),
           ids.allSatisfy(YTMusicClient.isValidVideoID) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                vm.playQueue(songs: ids.enumerated().map { Song(id: $1, title: "Probe \($0 + 1)", artist: "Probe") })
                try? await Task.sleep(for: .seconds(20))
                vm.next()
                try? await Task.sleep(for: .seconds(25))
                vm.next()
                try? await Task.sleep(for: .seconds(20))
                vm.pause()
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
