import SwiftUI
import OtoCore

/// Màn hình danh sách bài hát đã thích (Liked Songs).
public struct LikedSongsView: View {
    @Bindable var playerVM: PlayerViewModel
    @Bindable var libraryVM: LibraryViewModel

    public init(playerVM: PlayerViewModel, libraryVM: LibraryViewModel) {
        self.playerVM = playerVM
        self.libraryVM = libraryVM
    }

    public var body: some View {
        Group {
            if libraryVM.isLoading && libraryVM.likedSongs.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Đang tải bài hát đã thích...")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryVM.likedSongs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Chưa có bài hát yêu thích nào")
                        .font(.system(size: 17, weight: .semibold))

                    Text("Các bài hát bạn nhấn Thích trên YouTube Music sẽ xuất hiện tại đây.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Header controls
                    Section {
                        HStack(spacing: 16) {
                            Button {
                                playAll(shuffle: false)
                            } label: {
                                Label("Phát tất cả", systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                playAll(shuffle: true)
                            } label: {
                                Label("Trộn bài", systemImage: "shuffle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

                    // Danh sách bài hát
                    Section("\(libraryVM.likedSongs.count) bài hát") {
                        ForEach(libraryVM.likedSongs) { song in
                            Button {
                                playSong(song)
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: song.artworkURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.secondary.opacity(0.15))
                                            Image(systemName: "music.note")
                                                .font(.system(size: 16))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(song.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(isCurrent(song) ? Color.accentColor : .primary)
                                            .lineLimit(1)

                                        Text(song.artist)
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if song.duration > 0 {
                                        Text(formatDuration(song.duration))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable {
                    await libraryVM.loadLikedSongs()
                }
            }
        }
        .navigationTitle("Bài hát đã thích")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if libraryVM.likedSongs.isEmpty {
                await libraryVM.loadLikedSongs()
            }
        }
    }

    private func isCurrent(_ song: Song) -> Bool {
        playerVM.currentSong?.id == song.id
    }

    private func playSong(_ song: Song) {
        if let index = libraryVM.likedSongs.firstIndex(where: { $0.id == song.id }) {
            playerVM.playQueue(songs: libraryVM.likedSongs, startIndex: index)
        } else {
            playerVM.play(song: song)
        }
    }

    private func playAll(shuffle: Bool) {
        guard !libraryVM.likedSongs.isEmpty else { return }
        if shuffle {
            playerVM.playQueue(songs: libraryVM.likedSongs.shuffled(), startIndex: 0)
        } else {
            playerVM.playQueue(songs: libraryVM.likedSongs, startIndex: 0)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
