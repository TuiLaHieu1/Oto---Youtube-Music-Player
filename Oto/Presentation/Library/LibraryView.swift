import SwiftUI
import OtoCore

/// Màn hình thư viện nhạc cá nhân (Library).
public struct LibraryView: View {
    @Bindable var playerVM: PlayerViewModel

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
            }
            .navigationTitle("Thư viện")
        }
    }
}
