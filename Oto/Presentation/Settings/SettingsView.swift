import SwiftUI
import OtoCore
#if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
import MediaAccessibility
#endif

/// Màn hình Cài đặt (Settings View) chỉ hiển thị điều khiển có backend thực sự.
public struct SettingsView: View {
    @Bindable var playerVM: PlayerViewModel
    let libraryVM: LibraryViewModel
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage("app_language") private var selectedLanguage = AppLanguage.system.rawValue
    @State private var sessionStore = SessionStore.shared
    @State private var showClearAlert: Bool = false
    @State private var showSignOutAlert: Bool = false
    @Environment(\.dismiss) private var dismiss
    #if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
    @State private var hapticsProbeRequested = false
    @State private var hapticsTrackAvailable: Bool?
    @State private var systemHapticsActive = false
    @State private var showNativeHapticsProbe = false
    #endif

    init(playerVM: PlayerViewModel, libraryVM: LibraryViewModel) {
        self.playerVM = playerVM
        self.libraryVM = libraryVM
    }

    public var body: some View {
        NavigationStack {
            List {
                // Section 1: Tài khoản (có backend thật)
                accountSection

                // Section 2: Bộ nhớ đệm & Dung lượng (có backend thật)
                storageSection
                Section("Giao diện") {
                    Picker("Chế độ", selection: $appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { choice in
                            Text(choice.label).tag(choice.rawValue)
                        }
                    }
                }
                Section("Ngôn ngữ") {
                    Picker("Ngôn ngữ ứng dụng", selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(LocalizedStringKey(language.title)).tag(language.rawValue)
                        }
                    }
                }

                // Section 3: Thông tin ứng dụng & Quyền riêng tư (thông tin thực)
                aboutSection
                #if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
                if #available(iOS 18.0, *) {
                    hapticsProbeSection
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(OtoTheme.background.ignoresSafeArea())
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                    .font(OtoTheme.buttonFont)
                    .foregroundStyle(OtoTheme.accent)
                }
            }
            .onAppear {
                sessionStore.refreshSessionState()
                libraryVM.updateCacheSize()
            }
            .confirmationDialog(
                "Bạn có chắc muốn xóa toàn bộ bộ nhớ đệm và ảnh bìa không?",
                isPresented: $showClearAlert,
                titleVisibility: .visible
            ) {
                Button("Xóa bộ nhớ đệm", role: .destructive) {
                    libraryVM.clearAllCache()
                }
                Button("Hủy", role: .cancel) {}
            }
            .confirmationDialog(
                "Bạn có chắc muốn đăng xuất khỏi tài khoản YouTube Music?",
                isPresented: $showSignOutAlert,
                titleVisibility: .visible
            ) {
                Button("Đăng xuất", role: .destructive) {
                    Task {
                        await sessionStore.signOut(playerVM: playerVM)
                        libraryVM.likedSongs = []
                        dismiss()
                    }
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }

    #if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
    @available(iOS 18.0, *)
    private var hapticsProbeSection: some View {
        Section("Music Haptics · Debug") {
            Button("Kiểm tra mẫu ISRC") {
                hapticsProbeRequested = true
            }
            .disabled(hapticsProbeRequested)
            Button("Phát bản thu mẫu") {
                playerVM.play(song: MusicHapticsPilotSample.song)
                dismiss()
            }
            Button("Thử rung bằng file audio") { showNativeHapticsProbe = true }
                .sheet(isPresented: $showNativeHapticsProbe) {
                    NativeHapticsProbeView(playerVM: playerVM)
                }
            if let hapticsTrackAvailable {
                Text("Music Haptics: \(systemHapticsActive ? "ON" : "OFF")")
                Text("Haptic track: \(hapticsTrackAvailable ? "AVAILABLE" : "UNAVAILABLE")")
            } else if hapticsProbeRequested {
                ProgressView()
            }
        }
        .task(id: hapticsProbeRequested) {
            guard hapticsProbeRequested else { return }
            let manager = MAMusicHapticsManager.shared
            let available = await manager.isHapticTrackAvailable(forMediaMatching: MusicHapticsPilotSample.isrc)
            guard !Task.isCancelled else { return }
            systemHapticsActive = manager.isActive
            hapticsTrackAvailable = available
        }
    }
    #endif

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            if sessionStore.isAuthenticated {
                HStack(spacing: OtoTheme.spacing12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 28))
                        .foregroundStyle(OtoTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("YouTube Music")
                            .font(OtoTheme.rowTitleFont.weight(.semibold))
                            .foregroundStyle(OtoTheme.primaryText)
                        Text("Đã đăng nhập phiên an toàn")
                            .font(OtoTheme.captionFont)
                            .foregroundStyle(OtoTheme.secondaryText)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    dismiss()
                    playerVM.showAuth = true
                } label: {
                    Label("Đổi tài khoản", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(OtoTheme.primaryText)
                }

                Button(role: .destructive) {
                    showSignOutAlert = true
                } label: {
                    Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(OtoTheme.error)
                }
            } else {
                HStack(spacing: OtoTheme.spacing12) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 28))
                        .foregroundStyle(OtoTheme.tertiaryText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chưa đăng nhập")
                            .font(OtoTheme.rowTitleFont.weight(.semibold))
                            .foregroundStyle(OtoTheme.primaryText)
                        Text("Đăng nhập để nghe nhạc theo sở thích")
                            .font(OtoTheme.captionFont)
                            .foregroundStyle(OtoTheme.secondaryText)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    dismiss()
                    playerVM.showAuth = true
                } label: {
                    Label("Đăng nhập YouTube Music", systemImage: "key.fill")
                        .foregroundStyle(OtoTheme.accent)
                }
            }
        } header: {
            Text("Tài khoản")
        } footer: {
            Text("Oto lưu trữ cookie phiên an toàn trong Keychain của thiết bị và không bao giờ chia sẻ ra bên ngoài.")
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Dung lượng bộ đệm", value: libraryVM.cacheSizeString)

            Button(role: .destructive) {
                showClearAlert = true
            } label: {
                Label("Xóa toàn bộ bộ nhớ đệm", systemImage: "trash")
                    .foregroundStyle(OtoTheme.error)
            }
        } header: {
            Text("Bộ nhớ đệm & Lưu trữ")
        } footer: {
            Text("Bao gồm ảnh bìa album, dữ liệu trang chủ và bộ đệm lời bài hát.")
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var aboutSection: some View {
        Section("Thông tin & Quyền riêng tư") {
            LabeledContent("Ứng dụng", value: "Oto")
            LabeledContent("Phiên bản", value: appVersionString)
            VStack(alignment: .leading, spacing: 4) {
                Text("Chính sách bảo mật")
                    .font(OtoTheme.subtitleFont.weight(.medium))
                    .foregroundStyle(OtoTheme.primaryText)
                Text(
                    "Thông tin về cách Oto xử lý dữ liệu sẽ được bổ sung khi chính sách quyền riêng tư được hoàn thiện."
                )
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.secondaryText)
            }
            .padding(.vertical, 2)
        }
    }
}
