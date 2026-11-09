import SwiftUI
import OtoCore

/// Màn hình Home Feed chính của Oto theo ngôn ngữ Atelier Light × Spectrum Dark.
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
                        loadingStateView
                    } else if homeVM.quickPicks.isEmpty && homeVM.listenAgain.isEmpty {
                        emptyStateView
                    } else {
                        feedContentView
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

    // MARK: - Subviews

    private var loadingStateView: some View {
        VStack(spacing: OtoTheme.spacing16) {
            ProgressView()
                .tint(OtoTheme.accent)
            Text("Đang tải gợi ý từ YouTube Music...")
                .font(.subheadline)
                .foregroundStyle(OtoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: OtoTheme.spacing16) {
            Image(systemName: "music.note.house")
                .font(.system(size: 48))
                .foregroundStyle(OtoTheme.tertiaryText)

            if let error = homeVM.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(OtoTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OtoTheme.spacing32)
            } else {
                Text("Chưa có nội dung trang chủ")
                    .font(.headline)
                    .foregroundStyle(OtoTheme.primaryText)
            }

            Button {
                Task {
                    await homeVM.loadFeed()
                }
            } label: {
                Label("Thử lại", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OtoTheme.surface)
                    .padding(.horizontal, OtoTheme.spacing24)
                    .padding(.vertical, OtoTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                            .fill(OtoTheme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feedContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing32) {
                // Quick Picks (Lựa chọn nhanh)
                if !homeVM.quickPicks.isEmpty {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                        Text("Lựa chọn nhanh")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(OtoTheme.primaryText)
                            .padding(.horizontal, OtoTheme.spacing16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: OtoTheme.spacing16) {
                                ForEach(homeVM.quickPicks) { song in
                                    let isCurrent = (playerVM.currentSong?.id == song.id) && playerVM.isPlaying
                                    SongCardView(song: song, isPlaying: isCurrent) {
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
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

                // Listen Again (Nghe lại gần đây)
                if !homeVM.listenAgain.isEmpty {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                        Text("Nghe lại gần đây")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(OtoTheme.primaryText)
                            .padding(.horizontal, OtoTheme.spacing16)

                        VStack(spacing: OtoTheme.spacing8) {
                            ForEach(homeVM.listenAgain) { song in
                                let isCurrent = (playerVM.currentSong?.id == song.id) && playerVM.isPlaying
                                SongRowView(song: song, isPlaying: isCurrent) {
                                    #if os(iOS)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    let index = homeVM.listenAgain.firstIndex(of: song) ?? 0
                                    playerVM.playQueue(songs: homeVM.listenAgain, startIndex: index)
                                }
                            }
                        }
                        .padding(.horizontal, OtoTheme.spacing16)
                    }
                }
            }
            .padding(.top, OtoTheme.spacing16)
            .padding(.bottom, 160) // Chừa không gian thoáng cho MiniPlayer nổi
        }
    }
}

// MARK: - Card Component (Quick Picks)

private struct SongCardView: View {
    let song: Song
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: song.artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: OtoTheme.artworkRadius, style: .continuous)
                                .fill(OtoTheme.secondaryText.opacity(0.12))
                            Image(systemName: "music.note")
                                .font(.system(size: 28))
                                .foregroundStyle(OtoTheme.secondaryText)
                        }
                    }
                    .frame(width: 144, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: OtoTheme.artworkRadius, style: .continuous))

                    if isPlaying {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(OtoTheme.surface)
                            .padding(7)
                            .background(OtoTheme.accent)
                            .clipShape(Circle())
                            .padding(8)
                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPlaying ? OtoTheme.accent : OtoTheme.primaryText)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(OtoTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(width: 144, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                    .fill(OtoTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                            .stroke(OtoTheme.separator, lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row Component (Listen Again)

private struct SongRowView: View {
    let song: Song
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OtoTheme.spacing12) {
                AsyncImage(url: song.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: OtoTheme.artworkRadius, style: .continuous)
                            .fill(OtoTheme.secondaryText.opacity(0.12))
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundStyle(OtoTheme.secondaryText)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.artworkRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isPlaying ? OtoTheme.accent : OtoTheme.primaryText)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(OtoTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(OtoTheme.accent)
                }
            }
            .padding(.horizontal, OtoTheme.spacing12)
            .padding(.vertical, 10)
            .frame(minHeight: OtoTheme.minTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                    .fill(isPlaying ? OtoTheme.accentSurface : OtoTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                            .stroke(isPlaying ? OtoTheme.accent.opacity(0.3) : OtoTheme.separator, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
