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
            await reload()
        } catch {
            failed = true
        }
    }
}
