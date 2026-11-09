import SwiftUI
import OtoCore

/// Màn hình thư viện nhạc cá nhân và cài đặt ứng dụng theo chuẩn Atelier × Spectrum.
public struct LibraryView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var libraryVM = LibraryViewModel()
    @State private var sessionStore = SessionStore.shared
    @State private var showClearAlert: Bool = false

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Nội dung") {
                    if sessionStore.isAuthenticated {
                        NavigationLink {
                            LikedSongsView(playerVM: playerVM, libraryVM: libraryVM)
                        } label: {
                            HStack {
                                Label("Bài hát đã thích", systemImage: "heart.fill")
                                    .foregroundStyle(OtoTheme.accent)
                                Spacer()
                                if !libraryVM.likedSongs.isEmpty {
                                    Text("\(libraryVM.likedSongs.count)")
                                        .font(.system(size: 14))
                                        .foregroundStyle(OtoTheme.secondaryText)
                                }
                            }
                        }
                    } else {
                        Button {
                            playerVM.showAuth = true
                        } label: {
                            HStack {
                                Label("Bài hát đã thích", systemImage: "heart.fill")
                                    .foregroundStyle(OtoTheme.accent)
                                Spacer()
                                Text("Cần đăng nhập")
                                    .font(.system(size: 13))
                                    .foregroundStyle(OtoTheme.secondaryText)
                            }
                        }
                    }

                    unavailableLibraryRow("Danh sách phát", systemImage: "music.note.list")
                    unavailableLibraryRow("Album", systemImage: "square.stack")
                    unavailableLibraryRow("Nghệ sĩ", systemImage: "music.mic")
                }

                Section("Bộ nhớ đệm & Cài đặt") {
                    HStack {
                        Label("Dung lượng bộ nhớ đệm", systemImage: "internaldrive")
                        Spacer()
                        Text(libraryVM.cacheSizeString)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(OtoTheme.secondaryText)
                    }

                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Label("Xóa bộ nhớ đệm", systemImage: "trash")
                            .foregroundStyle(OtoTheme.error)
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

                Section("Tài khoản") {
                    if sessionStore.isAuthenticated {
                        HStack {
                            Label("Đã kết nối YouTube Music", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(OtoTheme.success)
                            Spacer()
                        }
                        Button(role: .destructive) {
                            Task {
                                await sessionStore.signOut(playerVM: playerVM)
                                libraryVM.likedSongs = []
                            }
                        } label: {
                            Text("Đăng xuất tài khoản")
                                .foregroundStyle(OtoTheme.error)
                        }
                    } else {
                        Button {
                            playerVM.showAuth = true
                        } label: {
                            Label("Đăng nhập tài khoản Google", systemImage: "person.crop.circle.badge.plus")
                                .foregroundStyle(OtoTheme.accent)
                        }
                    }
                }

                Section("Thông tin") {
                    HStack {
                        Text("Chế độ giao diện")
                        Spacer()
                        Text("Atelier Light × Spectrum Dark")
                            .font(.system(size: 13))
                            .foregroundStyle(OtoTheme.secondaryText)
                    }

                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("1.0.0 (Swift 6 Native)")
                            .font(.system(size: 13))
                            .foregroundStyle(OtoTheme.secondaryText)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(OtoTheme.background.ignoresSafeArea())
            .navigationTitle("Thư viện")
            .onAppear {
                sessionStore.refreshSessionState()
                libraryVM.updateCacheSize()
            }
            .task {
                if sessionStore.isAuthenticated && libraryVM.likedSongs.isEmpty {
                    await libraryVM.loadLikedSongs()
                }
            }
        }
    }

    private func unavailableLibraryRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("Chưa có dữ liệu")
                .font(.caption)
                .foregroundStyle(OtoTheme.tertiaryText)
        }
        .foregroundStyle(OtoTheme.controlInactive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), chưa có dữ liệu")
    }
}
