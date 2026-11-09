import SwiftUI
import OtoCore

/// Màn hình danh sách bài hát đã thích (Liked Songs) theo phong cách Atelier × Spectrum.
public struct LikedSongsView: View {
    @Bindable var playerVM: PlayerViewModel
    @Bindable var libraryVM: LibraryViewModel

    public init(playerVM: PlayerViewModel, libraryVM: LibraryViewModel) {
        self.playerVM = playerVM
        self.libraryVM = libraryVM
    }

    public var body: some View {
        ZStack {
            OtoTheme.background.ignoresSafeArea()

            Group {
                if libraryVM.isLoading && libraryVM.likedSongs.isEmpty {
                    loadingView
                } else if libraryVM.likedSongs.isEmpty {
                    emptyView
                } else {
                    contentListView
                }
            }
        }
        .navigationTitle("Bài hát đã thích")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: OtoTheme.spacing16) {
            ProgressView()
                .tint(OtoTheme.accent)
            Text("Đang tải bài hát đã thích...")
                .font(.subheadline)
                .foregroundStyle(OtoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: OtoTheme.spacing16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(OtoTheme.tertiaryText)

            Text("Chưa có bài hát yêu thích nào")
                .font(.headline)
                .foregroundStyle(OtoTheme.primaryText)

            Text("Các bài hát bạn nhấn Thích trên YouTube Music sẽ xuất hiện tại đây.")
                .font(.subheadline)
                .foregroundStyle(OtoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OtoTheme.spacing32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentListView: some View {
        ScrollView {
            VStack(spacing: OtoTheme.spacing16) {
                // Header Action Buttons (Phát tất cả & Trộn bài)
                HStack(spacing: OtoTheme.spacing12) {
                    Button {
                        playAll(shuffle: false)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Phát tất cả")
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(OtoTheme.surface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                                .fill(OtoTheme.accent)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        playAll(shuffle: true)
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
                                        .stroke(OtoTheme.separator, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, OtoTheme.spacing16)
                .padding(.top, OtoTheme.spacing8)

                // Subtitle count
                HStack {
                    Text("\(libraryVM.likedSongs.count) BÀI HÁT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OtoTheme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, OtoTheme.spacing16)

                // List of liked songs
                LazyVStack(spacing: OtoTheme.spacing8) {
                    ForEach(libraryVM.likedSongs) { song in
                        let isCur = isCurrent(song)
                        Button {
                            playSong(song)
                        } label: {
                            HStack(spacing: OtoTheme.spacing12) {
                                AsyncImage(url: song.artworkURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: OtoTheme.artworkRadius, style: .continuous)
                                            .fill(OtoTheme.secondaryText.opacity(0.12))
                                        Image(systemName: "music.note")
                                            .font(.system(size: 16))
                                            .foregroundStyle(OtoTheme.secondaryText)
                                    }
                                }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.artworkRadius, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(song.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(isCur ? OtoTheme.accent : OtoTheme.primaryText)
                                        .lineLimit(1)

                                    Text(song.artist)
                                        .font(.system(size: 13))
                                        .foregroundStyle(OtoTheme.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if song.duration > 0 {
                                    Text(formatDuration(song.duration))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(OtoTheme.secondaryText)
                                }
                            }
                            .padding(.horizontal, OtoTheme.spacing12)
                            .padding(.vertical, 10)
                            .frame(minHeight: OtoTheme.minTouchTarget)
                            .background(
                                RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                                    .fill(isCur ? OtoTheme.accentSurface : OtoTheme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                                            .stroke(
                                                isCur ? OtoTheme.accent.opacity(0.3) : OtoTheme.separator,
                                                lineWidth: 0.5
                                            )
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, OtoTheme.spacing16)
            }
            .padding(.bottom, 160) // Chừa khoảng trống cho MiniPlayer
        }
        .refreshable {
            await libraryVM.loadLikedSongs()
        }
    }

    // MARK: - Playback Helpers

    private func isCurrent(_ song: Song) -> Bool {
        playerVM.currentSong?.id == song.id && playerVM.isPlaying
    }

    private func playSong(_ song: Song) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let index = libraryVM.likedSongs.firstIndex(of: song) ?? 0
        playerVM.playQueue(songs: libraryVM.likedSongs, startIndex: index)
    }

    private func playAll(shuffle: Bool) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        var songs = libraryVM.likedSongs
        if shuffle {
            songs.shuffle()
        }
        playerVM.playQueue(songs: songs, startIndex: 0)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
