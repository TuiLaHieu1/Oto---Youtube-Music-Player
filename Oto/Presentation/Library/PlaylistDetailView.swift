import SwiftUI
import OtoCore

/// Màn hình chi tiết danh sách phát / Album (Playlist Detail View).
/// Cho phép người dùng duyệt toàn bộ danh sách bài hát, phát tất cả hoặc chọn từng bài cụ thể.
public struct PlaylistDetailView: View {
    public let playlist: Playlist
    @Bindable var playerVM: PlayerViewModel

    @State private var songs: [Song] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    public init(playlist: Playlist, playerVM: PlayerViewModel) {
        self.playlist = playlist
        self.playerVM = playerVM
    }

    public var body: some View {
        ZStack {
            OtoTheme.background.ignoresSafeArea()

            Group {
                if isLoading && songs.isEmpty {
                    loadingView
                } else if let error = errorMessage, songs.isEmpty {
                    OtoErrorState(title: "Không thể tải danh sách", message: error) {
                        Task { await loadSongs() }
                    }
                } else {
                    contentView
                }
            }
        }
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSongs()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: OtoTheme.spacing16) {
            ProgressView()
                .tint(OtoTheme.accent)
            Text("Đang tải danh sách bài hát...")
                .font(OtoTheme.captionFont)
                .foregroundStyle(OtoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: OtoTheme.spacing20) {
                headerView

                if !songs.isEmpty {
                    actionButtons
                    songsListView
                } else {
                    Text("Danh sách phát này chưa có bài hát nào.")
                        .font(OtoTheme.captionFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                        .padding(.top, OtoTheme.spacing32)
                }
            }
            .padding(.bottom, 140)
        }
    }

    private var headerView: some View {
        VStack(spacing: OtoTheme.spacing12) {
            AsyncImage(url: playlist.artworkURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                    .fill(OtoTheme.surface)
                    .overlay(
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(OtoTheme.secondaryText)
                    )
            }
            .frame(width: 180, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.3), radius: 16, x: 0, y: 8)

            VStack(spacing: 4) {
                Text(playlist.title)
                    .font(OtoTheme.sectionTitleFont)
                    .foregroundStyle(OtoTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(playlist.subtitle)
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.secondaryText)

                if let count = playlist.trackCount, count > 0 {
                    Text("\(count) bài hát")
                        .font(OtoTheme.captionFont)
                        .foregroundStyle(OtoTheme.tertiaryText)
                }
            }
            .padding(.horizontal, OtoTheme.spacing16)
        }
        .padding(.top, OtoTheme.spacing16)
    }

    private var actionButtons: some View {
        HStack(spacing: OtoTheme.spacing12) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                playerVM.playQueue(songs: songs, startIndex: 0)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Phát tất cả")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15))
                .foregroundStyle(OtoTheme.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                        .fill(OtoTheme.accent)
                )
            }
            .buttonStyle(.plain)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                var shuffled = songs
                shuffled.shuffle()
                playerVM.playQueue(songs: shuffled, startIndex: 0)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                    Text("Trộn bài")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15))
                .foregroundStyle(OtoTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                        .fill(OtoTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                                .stroke(OtoTheme.separator, lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OtoTheme.spacing16)
    }

    private var songsListView: some View {
        LazyVStack(spacing: OtoTheme.spacing4) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                OtoSongRow(song: song, isPlaying: isCurrent) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    playerVM.playQueue(songs: songs, startIndex: index)
                }
            }
        }
        .padding(.horizontal, OtoTheme.spacing16)
    }

    // MARK: - Data Loading

    private func loadSongs() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await YTMusicClient.shared.fetchPlaylistSongs(playlistId: playlist.id)
            guard !Task.isCancelled else { return }
            self.songs = fetched
            self.isLoading = false
        } catch is CancellationError {
            // Task bị huỷ bình thường
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}
