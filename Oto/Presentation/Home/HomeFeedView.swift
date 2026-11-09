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

    // MARK: - Feed Content

    private var feedScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing32) {
                // Section 1: Quick Picks (Lựa chọn nhanh dạng thẻ ngang)
                if !homeVM.quickPicks.isEmpty {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                        OtoSectionHeader(title: "Lựa chọn nhanh")

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: OtoTheme.spacing16) {
                                ForEach(homeVM.quickPicks) { song in
                                    let isCurrent = (playerVM.currentSong?.id == song.id) && playerVM.isPlaying
                                    OtoAlbumCard(song: song, isPlaying: isCurrent) {
                                        triggerHaptic()
                                        let index = homeVM.quickPicks.firstIndex(of: song) ?? 0
                                        playerVM.playQueue(songs: homeVM.quickPicks, startIndex: index)
                                    }
                                }
                            }
                            .padding(.horizontal, OtoTheme.spacing16)
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Section 2: Listen Again (Nghe lại gần đây dạng hàng danh sách)
                if !homeVM.listenAgain.isEmpty {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                        OtoSectionHeader(title: "Nghe lại gần đây")

                        VStack(spacing: OtoTheme.spacing8) {
                            ForEach(homeVM.listenAgain) { song in
                                let isCurrent = (playerVM.currentSong?.id == song.id) && playerVM.isPlaying
                                OtoSongRow(song: song, isPlaying: isCurrent) {
                                    triggerHaptic()
                                    let index = homeVM.listenAgain.firstIndex(of: song) ?? 0
                                    playerVM.playQueue(songs: homeVM.listenAgain, startIndex: index)
                                }
                            }
                        }
                        .padding(.horizontal, OtoTheme.spacing16)
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
                                    triggerHaptic()
                                    let index = homeVM.recentlyPlayed.firstIndex(of: song) ?? 0
                                    playerVM.playQueue(songs: homeVM.recentlyPlayed, startIndex: index)
                                }
                            }
                        }
                        .padding(.horizontal, OtoTheme.spacing16)
                    }
                }
            }
            .padding(.top, OtoTheme.spacing16)
            .padding(.bottom, 160)
        }
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
