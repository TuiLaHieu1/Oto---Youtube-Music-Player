import SwiftUI
import OtoCore

/// Màn hình thư viện nhạc cá nhân và cài đặt ứng dụng.
public struct LibraryView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var libraryVM = LibraryViewModel()
    @State private var hasSession: Bool = CookieStorage.shared.hasValidSession
    @State private var showClearAlert: Bool = false

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Nội dung") {
                    if hasSession {
                        NavigationLink {
                            LikedSongsView(playerVM: playerVM, libraryVM: libraryVM)
                        } label: {
                            HStack {
                                Label("Bài hát đã thích", systemImage: "heart.fill")
                                    .foregroundStyle(.pink)
                                Spacer()
                                if !libraryVM.likedSongs.isEmpty {
                                    Text("\(libraryVM.likedSongs.count)")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Button {
                            playerVM.showAuth = true
                        } label: {
                            HStack {
                                Label("Bài hát đã thích", systemImage: "heart.fill")
                                    .foregroundStyle(.pink)
                                Spacer()
                                Text("Cần đăng nhập")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Label("Danh sách phát", systemImage: "music.note.list")
                        .foregroundStyle(.secondary)
                    Label("Album", systemImage: "square.stack")
                        .foregroundStyle(.secondary)
                    Label("Nghệ sĩ", systemImage: "music.mic")
                        .foregroundStyle(.secondary)
                }

                Section("Bộ nhớ đệm & Cài đặt") {
                    HStack {
                        Label("Dung lượng bộ nhớ đệm", systemImage: "internaldrive")
                        Spacer()
                        Text(libraryVM.cacheSizeString)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Label("Xóa bộ nhớ đệm", systemImage: "trash")
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
                    if hasSession {
                        HStack {
                            Label("Đã kết nối YouTube Music", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Spacer()
                        }
                        Button(role: .destructive) {
                            Task {
                                await WebKitManager.shared.clearSession()
                                hasSession = false
                                libraryVM.likedSongs = []
                            }
                        } label: {
                            Text("Đăng xuất tài khoản")
                        }
                    } else {
                        Button {
                            playerVM.showAuth = true
                        } label: {
                            Label("Đăng nhập tài khoản Google", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }

                Section("Thông tin") {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("1.0.0 (Swift 6 Native)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Thư viện")
            .onAppear {
                hasSession = CookieStorage.shared.hasValidSession
                libraryVM.updateCacheSize()
            }
            .task {
                if hasSession && libraryVM.likedSongs.isEmpty {
                    await libraryVM.loadLikedSongs()
                }
            }
        }
    }
}
