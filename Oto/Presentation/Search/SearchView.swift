import SwiftUI
import OtoCore

/// Màn hình tìm kiếm âm nhạc trực tiếp từ YouTube Music theo phong cách Atelier × Spectrum.
public struct SearchView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var searchVM = SearchViewModel()

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                OtoTheme.background.ignoresSafeArea()

                Group {
                    if searchVM.isLoading && searchVM.searchResults.isEmpty {
                        loadingView
                    } else if searchVM.searchResults.isEmpty {
                        emptyStateView
                    } else {
                        resultsListView
                    }
                }
            }
            .navigationTitle("Tìm kiếm")
            .searchable(
                text: $searchVM.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Bài hát, nghệ sĩ..."
            )
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: OtoTheme.spacing12) {
            ProgressView()
                .tint(OtoTheme.accent)
            Text("Đang tìm bài hát...")
                .font(.subheadline)
                .foregroundStyle(OtoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: OtoTheme.spacing16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(OtoTheme.tertiaryText)

            Text(searchVM.query.isEmpty ? "Khám phá bài hát mới" : "Không tìm thấy kết quả phù hợp")
                .font(.headline)
                .foregroundStyle(OtoTheme.primaryText)

            let subtext = searchVM.query.isEmpty
                ? "Nhập tên bài hát hoặc nghệ sĩ bạn muốn nghe."
                : "Hãy thử tìm kiếm với từ khóa khác."
            Text(subtext)
                .font(.subheadline)
                .foregroundStyle(OtoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OtoTheme.spacing32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: OtoTheme.spacing8) {
                ForEach(searchVM.searchResults) { song in
                    let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        let index = searchVM.searchResults.firstIndex(of: song) ?? 0
                        playerVM.playQueue(songs: searchVM.searchResults, startIndex: index)
                    } label: {
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
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isCurrent ? OtoTheme.accent : OtoTheme.primaryText)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 13))
                                    .foregroundStyle(OtoTheme.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isCurrent {
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.iterative.reversing)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(OtoTheme.accent)
                            }
                        }
                        .padding(.horizontal, OtoTheme.spacing12)
                        .padding(.vertical, 10)
                        .frame(minHeight: OtoTheme.minTouchTarget)
                        .background(
                            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                                .fill(isCurrent ? OtoTheme.accentSurface : OtoTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                                        .stroke(
                                            isCurrent ? OtoTheme.accent.opacity(0.3) : OtoTheme.separator,
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
            .padding(.top, OtoTheme.spacing12)
            .padding(.bottom, 160) // Chừa khoảng trống nổi cho MiniPlayer
        }
    }
}
