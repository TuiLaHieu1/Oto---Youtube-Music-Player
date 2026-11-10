import SwiftUI
import OtoCore

/// Màn hình thư viện nhạc cá nhân và cài đặt ứng dụng theo chuẩn Atelier × Spectrum.
public struct LibraryView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var libraryVM = LibraryViewModel()
    @State private var sessionStore = SessionStore.shared
    @State private var showClearAlert: Bool = false
    @State private var showSettings: Bool = false

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OtoTheme.spacing24) {
                    HStack {
                        Text("Thư viện của bạn")
                            .font(OtoTheme.largeTitleFont)
                            .foregroundStyle(OtoTheme.primaryText)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(OtoTheme.controlInactive)
                                .frame(width: OtoTheme.minTouchTarget, height: OtoTheme.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                    }

                    categoryChips

                    likedSongsLink

                    librarySection(title: "Danh sách phát", icon: "music.note.list")
                    librarySection(title: "Album", icon: "square.stack")
                    librarySection(title: "Nghệ sĩ", icon: "music.mic")
                }
                .padding(.horizontal, OtoTheme.spacing16)
                .padding(.top, OtoTheme.spacing8)
                .padding(.bottom, 120)
            }
            .background(OtoTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                sessionStore.refreshSessionState()
                libraryVM.updateCacheSize()
            }
            .task {
                if sessionStore.isAuthenticated && libraryVM.likedSongs.isEmpty {
                    await libraryVM.loadLikedSongs()
                }
            }
            .sheet(isPresented: $showSettings) {
                settingsView
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
        }
    }

    private var categoryChips: some View {
        HStack(spacing: OtoTheme.spacing8) {
            chip("Tất cả", selected: true)
            chip("Playlist", selected: false)
            chip("Album", selected: false)
            chip("Nghệ sĩ", selected: false)
        }
    }

    private func chip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(OtoTheme.captionFont)
            .foregroundStyle(selected ? OtoTheme.accent : OtoTheme.secondaryText)
            .padding(.horizontal, OtoTheme.spacing12)
            .frame(minHeight: 34)
            .background(selected ? OtoTheme.accentSurface : OtoTheme.surface)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var likedSongsLink: some View {
        if sessionStore.isAuthenticated {
            NavigationLink {
                LikedSongsView(playerVM: playerVM, libraryVM: libraryVM)
            } label: {
                libraryCard
            }
            .buttonStyle(.plain)
        } else {
            Button {
                playerVM.showAuth = true
            } label: {
                libraryCard
            }
            .buttonStyle(.plain)
        }
    }

    private var libraryCard: some View {
        HStack {
            Image(systemName: "heart")
                .foregroundStyle(OtoTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bài hát đã thích")
                    .font(OtoTheme.sectionTitleFont)
                    .foregroundStyle(OtoTheme.primaryText)
                Text(sessionStore.isAuthenticated
                     ? "\(libraryVM.likedSongs.count) bài hát"
                     : "Đăng nhập để xem thư viện")
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.secondaryText)
            }
            Spacer()
        }
        .padding(OtoTheme.spacing16)
        .background(OtoTheme.accentSurface)
        .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous))
    }

    private func librarySection(title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
            Text(title)
                .font(OtoTheme.sectionTitleFont)
                .foregroundStyle(OtoTheme.primaryText)
            HStack(spacing: OtoTheme.spacing12) {
                RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous)
                    .fill(OtoTheme.backgroundSecondary)
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: icon).foregroundStyle(OtoTheme.tertiaryText))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chưa có \(title.lowercased())")
                        .font(OtoTheme.rowTitleFont)
                    Text("Nội dung khả dụng sẽ xuất hiện tại đây.")
                        .font(OtoTheme.captionFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                }
            }
        }
    }

    private var settingsView: some View {
        NavigationStack {
            List {
                Section("Tài khoản") {
                    if sessionStore.isAuthenticated {
                        Text("Đã kết nối YouTube Music")
                        Button("Đăng xuất", role: .destructive) {
                            Task {
                                await sessionStore.signOut(playerVM: playerVM)
                                libraryVM.likedSongs = []
                                showSettings = false
                            }
                        }
                    } else {
                        Button("Đăng nhập") {
                            showSettings = false
                            playerVM.showAuth = true
                        }
                    }
                }
                Section("Bộ nhớ đệm") {
                    LabeledContent("Dung lượng", value: libraryVM.cacheSizeString)
                    Button("Xóa bộ nhớ đệm", role: .destructive) {
                        showClearAlert = true
                    }
                }
                Section("Giao diện") {
                    LabeledContent("Chế độ", value: "Theo hệ thống")
                }
                Section("Thông tin") {
                    LabeledContent("Phiên bản", value: "1.0.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(OtoTheme.background)
            .navigationTitle("Cài đặt")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { showSettings = false }
                }
            }
        }
    }
}
