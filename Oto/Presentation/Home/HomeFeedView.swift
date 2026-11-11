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
                if !homeVM.speedDialItems.isEmpty {
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
                                ForEach(homeVM.speedDialItems) { item in
                                    SpeedDialTileView(
                                        item: item,
                                        isCurrent: (playerVM.currentSong?.id == item.id) && playerVM.isPlaying,
                                        size: tileSize,
                                        onPlay: {
                                            if item.kind == .song {
                                                playerVM.playWithRadio(song: item.asSong)
                                            } else {
                                                playerVM.playPlaylist(id: item.id, fallbackSong: item.asSong)
                                            }
                                        },
                                        onTogglePin: {
                                            homeVM.togglePin(for: item)
                                        }
                                    )
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, OtoTheme.spacing16)
                            .padding(.vertical, 4)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }

                // Các phân đoạn đề xuất từ YouTube Music (Quick picks, Forgotten Favorites, Daily Discover...)
                if !homeVM.sections.isEmpty {
                    ForEach(homeVM.sections) { section in
                        if !section.items.isEmpty {
                            VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                                OtoSectionHeader(title: section.title)
                                    .padding(.horizontal, OtoTheme.spacing16)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: OtoTheme.spacing12) {
                                        ForEach(section.items) { item in
                                            OtoAlbumCard(
                                                song: item.asSong,
                                                isPlaying: playerVM.currentSong?.id == item.id && playerVM.isPlaying,
                                                size: 152
                                            ) {
                                                if item.kind == .song {
                                                    playerVM.playWithRadio(song: item.asSong)
                                                } else {
                                                    playerVM.playPlaylist(id: item.id, fallbackSong: item.asSong)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, OtoTheme.spacing16)
                                }
                            }
                        }
                    }
                } else {
                    // Fallback tương thích dữ liệu cũ
                    if !homeVM.quickPicks.isEmpty {
                        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                            OtoSectionHeader(title: "Lựa chọn nhanh")
                                .padding(.horizontal, OtoTheme.spacing16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: OtoTheme.spacing12) {
                                    ForEach(homeVM.quickPicks) { song in
                                        OtoAlbumCard(
                                            song: song,
                                            isPlaying: playerVM.currentSong?.id == song.id && playerVM.isPlaying,
                                            size: 152
                                        ) {
                                            play(song, in: homeVM.quickPicks)
                                        }
                                    }
                                }
                                .padding(.horizontal, OtoTheme.spacing16)
                            }
                        }
                    }

                    if !homeVM.listenAgain.isEmpty {
                        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                            OtoSectionHeader(title: "Nghe lại gần đây")
                                .padding(.horizontal, OtoTheme.spacing16)

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
}
