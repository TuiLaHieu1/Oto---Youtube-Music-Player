import SwiftUI
import OtoCore

/// Màn hình Home Feed chính của ứng dụng Oto.
public struct HomeFeedView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var homeVM = HomeViewModel()

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Quick Picks
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Lựa chọn nhanh")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(homeVM.quickPicks) { song in
                                    let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                                    SongCardView(song: song, isPlaying: isCurrent) {
                                        let index = homeVM.quickPicks.firstIndex(of: song) ?? 0
                                        playerVM.queueManager.setQueue(songs: homeVM.quickPicks, startIndex: index)
                                        playerVM.play(song: song)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Listen Again
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Nghe lại gần đây")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 16)

                        VStack(spacing: 8) {
                            ForEach(homeVM.listenAgain) { song in
                                let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                                SongRowView(song: song, isPlaying: isCurrent) {
                                    let index = homeVM.listenAgain.firstIndex(of: song) ?? 0
                                    playerVM.queueManager.setQueue(songs: homeVM.listenAgain, startIndex: index)
                                    playerVM.play(song: song)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 90) // Khoảng trống cho MiniPlayer
            }
            .navigationTitle("Trang chủ")
        }
    }
}

private struct SongCardView: View {
    let song: Song
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 150, height: 150)

                    Image(systemName: "music.note")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isPlaying {
                        Image(systemName: "speaker.wave.3.fill")
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
                }
                .frame(width: 150, height: 150)

                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(song.artist)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150)
        }
        .buttonStyle(.plain)
    }
}

private struct SongRowView: View {
    let song: Song
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                    Image(systemName: isPlaying ? "speaker.wave.3.fill" : "music.note")
                        .font(.system(size: 16))
                        .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
