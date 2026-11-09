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
            Group {
                if homeVM.isLoading && homeVM.quickPicks.isEmpty && homeVM.listenAgain.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Đang tải gợi ý từ YouTube Music...")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if homeVM.quickPicks.isEmpty && homeVM.listenAgain.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.house")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        if let error = homeVM.errorMessage {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else {
                            Text("Chưa có nội dung trang chủ")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task {
                                await homeVM.loadFeed()
                            }
                        } label: {
                            Label("Thử lại", systemImage: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            // Quick Picks
                            if !homeVM.quickPicks.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Lựa chọn nhanh")
                                        .font(.system(size: 20, weight: .bold))
                                        .padding(.horizontal, 16)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(spacing: 14) {
                                            ForEach(homeVM.quickPicks) { song in
                                                let isCurrent = (playerVM.currentSong?.id == song.id)
                                                    && playerVM.isPlaying
                                                SongCardView(song: song, isPlaying: isCurrent) {
                                                    let index = homeVM.quickPicks.firstIndex(of: song) ?? 0
                                                    playerVM.playQueue(songs: homeVM.quickPicks, startIndex: index)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }

                            // Listen Again
                            if !homeVM.listenAgain.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Nghe lại gần đây")
                                        .font(.system(size: 20, weight: .bold))
                                        .padding(.horizontal, 16)

                                    VStack(spacing: 8) {
                                        ForEach(homeVM.listenAgain) { song in
                                            let isCurrent = (playerVM.currentSong?.id == song.id)
                                                && playerVM.isPlaying
                                            SongRowView(song: song, isPlaying: isCurrent) {
                                                let index = homeVM.listenAgain.firstIndex(of: song) ?? 0
                                                playerVM.playQueue(songs: homeVM.listenAgain, startIndex: index)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 90) // Khoảng trống cho MiniPlayer
                    }
                }
            }
            .navigationTitle("Trang chủ")
            .refreshable {
                await homeVM.loadFeed()
            }
            .task {
                if homeVM.quickPicks.isEmpty && homeVM.listenAgain.isEmpty {
                    await homeVM.loadFeed()
                }
            }
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
                    AsyncImage(url: song.artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.15))
                            Image(systemName: "music.note")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if isPlaying {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 140, alignment: .leading)
            }
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
            HStack(spacing: 12) {
                AsyncImage(url: song.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.15))
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
