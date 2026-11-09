import SwiftUI
import OtoCore

/// Màn hình thư viện nhạc cá nhân (Library).
public struct LibraryView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var hasSession: Bool = CookieStorage.shared.hasValidSession

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Bài hát đã thích", systemImage: "heart.fill")
                    Label("Danh sách phát", systemImage: "music.note.list")
                    Label("Album", systemImage: "square.stack")
                    Label("Nghệ sĩ", systemImage: "music.mic")
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
                            }
                        } label: {
                            Text("Đăng xuất")
                        }
                    } else {
                        Button {
                            playerVM.showAuth = true
                        } label: {
                            Label("Đăng nhập tài khoản Google", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Thư viện")
            .onAppear {
                hasSession = CookieStorage.shared.hasValidSession
            }
        }
    }
}
