import SwiftUI
import UniformTypeIdentifiers
import OtoCore

struct LocalMusicView: View {
    let playerVM: PlayerViewModel
    @State private var songs: [Song] = []
    @State private var showImporter = false
    @State private var importURLs: [URL] = []
    @State private var isImporting = false
    @State private var failed = false
    @State private var editingSong: Song?

    var body: some View {
        List {
            if songs.isEmpty && !isImporting {
                Text("Chưa có nhạc trên thiết bị")
            }
            if isImporting { ProgressView("Đang nhập nhạc…") }
            if failed {
                Text("Không thể đọc một số tệp nhạc.")
                    .foregroundStyle(OtoTheme.error)
            }
            ForEach(songs) { song in
                OtoSongRow(song: song, isPlaying: playerVM.currentSong?.id == song.id && playerVM.isPlaying) {
                    guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
                    playerVM.playQueue(
                        songs: songs, startIndex: index,
                        sourceTitle: String(localized: "Nhạc trên thiết bị", locale: AppLanguage.current.locale)
                    )
                }
                .swipeActions(edge: .leading) {
                    Button("Chỉnh thông tin", systemImage: "pencil") { self.editingSong = song }
                }
                .swipeActions {
                    if !playerVM.queueItems.contains(where: { $0.song.id == song.id }) {
                        Button("Xóa", role: .destructive) {
                            Task { await remove(song) }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(OtoTheme.background)
        .safeAreaPadding(.bottom, 75)
        .navigationTitle("Nhạc trên thiết bị")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nhập nhạc") { showImporter = true }
                    .disabled(isImporting)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) {
            switch $0 {
            case .success(let urls): importURLs = urls
            case .failure: failed = true
            }
        }
        .task(id: importURLs) {
            if !importURLs.isEmpty { await importFiles(importURLs) }
            await reload()
        }
        .sheet(item: self.$editingSong) { song in
            LocalSongEditor(song: song) { updated in
                self.playerVM.replaceSavedLocalSong(updated)
                await self.reload()
            }
        }
    }

    private func reload() async {
        do {
            songs = try await LocalMusicStore.shared.songs()
        } catch {
            failed = true
        }
    }

    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        failed = false
        defer {
            isImporting = false
            importURLs = []
        }
        for url in urls {
            if Task.isCancelled { return }
            do {
                try await LocalMusicStore.shared.importFile(url)
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
        }
    }

    private func remove(_ song: Song) async {
        do {
            try await LocalMusicStore.shared.remove(song.id)
            self.playerVM.removeSavedLocalSong(id: song.id)
            await reload()
        } catch {
            failed = true
        }
    }
}

private struct LocalSongEditor: View {
    let song: Song
    let onSave: (Song) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @State private var artwork: URL?
    @State private var showsImporter = false
    @State private var failed = false
    @State private var saving = false

    init(song: Song, onSave: @escaping (Song) async -> Void) {
        self.song = song
        self.onSave = onSave
        self._title = State(initialValue: song.title)
        self._artist = State(initialValue: song.artist)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên bài hát", text: self.$title)
                TextField("Nghệ sĩ", text: self.$artist)
                Button("Chọn ảnh bìa", systemImage: "photo") { self.showsImporter = true }
                if let artwork = self.artwork { Text(artwork.lastPathComponent) }
                if self.failed { Text("Không lưu được thông tin bài hát").foregroundStyle(OtoTheme.error) }
            }
            .navigationTitle("Chỉnh thông tin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { self.dismiss() }.disabled(self.saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await self.save() } }
                        .disabled(self.saving || self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: self.$showsImporter, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result { self.artwork = url }
            }
        }
        .interactiveDismissDisabled(self.saving)
    }

    private func save() async {
        guard !self.saving else { return }
        self.saving = true
        defer { self.saving = false }
        do {
            let updated = try await LocalMusicStore.shared.update(
                self.song.id, title: self.title, artist: self.artist, artwork: self.artwork
            )
            await self.onSave(updated)
            self.dismiss()
        } catch {
            self.failed = true
        }
    }
}
