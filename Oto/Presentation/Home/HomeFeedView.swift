import SwiftUI
import OtoCore

/// Màn hình Trang chủ (Home Feed) của Oto theo ngôn ngữ Atelier Light × Spectrum Dark.
public struct HomeFeedView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var homeVM = HomeViewModel()

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                OtoTheme.background.ignoresSafeArea()

                Group {
                    if homeVM.isLoading && homeVM.quickPicks.isEmpty && homeVM.listenAgain.isEmpty {
                        OtoLoadingSkeleton()
                    } else if let error = homeVM.errorMessage, homeVM.quickPicks.isEmpty && homeVM.listenAgain.isEmpty {
                        OtoErrorState(message: error) {
                            Task {
                                await homeVM.loadFeed()
                            }
                        }
                    } else if homeVM.quickPicks.isEmpty && homeVM.listenAgain.isEmpty {
                        OtoEmptyState(
                            title: "Chưa có gợi ý âm nhạc",
                            message: "Vuốt xuống để tải lại từ YouTube Music hoặc mở tab Tìm kiếm để chọn bài hát.",
                            actionTitle: "Tải gợi ý"
                        ) {
                            Task {
                                await homeVM.loadFeed()
                            }
                        }
                    } else {
                        feedScrollView
                    }
                }
            }
            .navigationTitle("Trang chủ")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await homeVM.loadFeed()
            }
            .task {
                await homeVM.loadFeed()
            }
        }
    }

    // MARK: - Feed Content

    private var feedScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing4) {
                        Text("Dành cho bạn")
                            .font(OtoTheme.largeTitleFont)
                            .foregroundStyle(OtoTheme.primaryText)

                        Text("Một khoảng nhỏ để lắng nghe.")
                            .font(OtoTheme.subtitleFont)
                            .foregroundStyle(OtoTheme.secondaryText)
                    }

                    Spacer()

                    Button {
                        playerVM.showAuth = true
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(OtoTheme.controlInactive)
                            .frame(width: OtoTheme.minTouchTarget, height: OtoTheme.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, OtoTheme.spacing16)
                .padding(.top, OtoTheme.spacing8)

                // Section 1: Speed Dial (Quay số nhanh 3x3 theo chuẩn YouTube Music)
                if !homeVM.quickPicks.isEmpty {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                        OtoSectionHeader(title: "Speed dial")
                            .padding(.horizontal, OtoTheme.spacing16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHGrid(
                                rows: [
                                    GridItem(.fixed(tileSize), spacing: 8),
                                    GridItem(.fixed(tileSize), spacing: 8),
                                    GridItem(.fixed(tileSize), spacing: 8)
                                ],
                                spacing: 8
                            ) {
                                ForEach(homeVM.quickPicks) { song in
                                    speedDialTile(for: song)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, OtoTheme.spacing16)
                            .padding(.vertical, 4)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }

                if !homeVM.listenAgain.isEmpty {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                        OtoSectionHeader(title: "Nghe lại gần đây")

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: OtoTheme.spacing12) {
                                ForEach(homeVM.listenAgain) { song in
                                    OtoAlbumCard(
                                        song: song,
                                        isPlaying: playerVM.currentSong?.id == song.id && playerVM.isPlaying,
                                        size: 152
                                    ) {
                                        play(song, in: homeVM.listenAgain)
                                    }
                                }
                            }
                            .padding(.horizontal, OtoTheme.spacing16)
                        }
                    }
                }

                // Section 3: Recently Played (Đã phát gần đây)
                if !homeVM.recentlyPlayed.isEmpty {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                        OtoSectionHeader(title: "Đã phát gần đây")

                        VStack(spacing: OtoTheme.spacing8) {
                            ForEach(homeVM.recentlyPlayed) { song in
                                let isCurrent = (playerVM.currentSong?.id == song.id) && playerVM.isPlaying
                                OtoSongRow(song: song, isPlaying: isCurrent) {
                                    play(song, in: homeVM.recentlyPlayed)
                                }
                            }
                        }
                        .padding(.horizontal, OtoTheme.spacing16)
                    }
                }
            }
            .padding(.top, OtoTheme.spacing4)
            .padding(.bottom, 160)
        }
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func play(_ song: Song, in songs: [Song]) {
        triggerHaptic()
        let index = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        playerVM.playQueue(songs: songs, startIndex: index)
    }

    private var tileSize: CGFloat {
        #if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
        // 3 cột phủ trọn khung nhìn: cột thứ 4 hoàn toàn ngoài màn hình (ẩn 100%)
        return max(100, ceil((screenWidth - 40) / 3))
        #else
        return 116
        #endif
    }

    private func speedDialTile(for song: Song) -> some View {
        let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
        return Button {
            triggerHaptic()
            playerVM.playWithRadio(song: song)
        } label: {
            ZStack(alignment: .bottomLeading) {
                speedDialArtwork(for: song)

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(song.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(8)

                if isCurrent {
                    VStack {
                        HStack {
                            Spacer()
                            Circle().fill(OtoTheme.accent).frame(width: 8, height: 8).padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: tileSize, height: tileSize)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isCurrent ? OtoTheme.accent : OtoTheme.separator.opacity(0.4),
                        lineWidth: isCurrent ? 1.5 : 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(song.title), \(song.artist)")
    }

    private func speedDialArtwork(for song: Song) -> some View {
        AsyncImage(url: song.artworkURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure, .empty:
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(OtoTheme.surface)
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(OtoTheme.secondaryText)
                }
            @unknown default:
                Color.clear
            }
        }
        .id(song.artworkURL)
        .frame(width: tileSize, height: tileSize)
        .clipped()
    }
}
