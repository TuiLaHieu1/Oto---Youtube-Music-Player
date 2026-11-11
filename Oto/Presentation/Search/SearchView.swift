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
            VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                Text("Tìm kiếm")
                    .font(OtoTheme.largeTitleFont)
                    .foregroundStyle(OtoTheme.primaryText)
                    .padding(.horizontal, OtoTheme.spacing16)

                HStack(spacing: OtoTheme.spacing8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(OtoTheme.controlInactive)
                    TextField("Bài hát, album, nghệ sĩ", text: $searchVM.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchVM.query.isEmpty {
                        Button {
                            searchVM.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(OtoTheme.controlInactive)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, OtoTheme.spacing12)
                .frame(height: OtoTheme.minTouchTarget)
                .background(OtoTheme.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous))
                .padding(.horizontal, OtoTheme.spacing16)

                filterChips

                Group {
                    if searchVM.isLoading && searchVM.searchResults.isEmpty {
                        loadingView
                    } else if let error = searchVM.errorMessage, searchVM.searchResults.isEmpty {
                        OtoErrorState(title: "Không thể tìm kiếm", message: error) {
                            searchVM.retry()
                        }
                    } else if searchVM.searchResults.isEmpty {
                        emptyStateView
                    } else {
                        resultsListView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, OtoTheme.spacing8)
            .background(OtoTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        OtoLoadingSkeleton()
    }

    private var emptyStateView: some View {
        let isInitial = searchVM.query.isEmpty
        return OtoEmptyState(
            iconName: "magnifyingglass",
            title: isInitial ? "Tìm bài hát tiếp theo" : "Không tìm thấy kết quả",
            message: isInitial
                ? "Tìm bài hát, album, nghệ sĩ và playlist."
                : "Thử cách viết khác hoặc từ khóa ngắn hơn."
        )
    }

    private var resultsListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                OtoSectionHeader(title: "Bài hát")
                LazyVStack(spacing: OtoTheme.spacing4) {
                    ForEach(searchVM.searchResults) { song in
                        let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                        OtoSongRow(song: song, isPlaying: isCurrent) {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            playerVM.playWithRadio(song: song)
                        }
                    }
                }
                .padding(.horizontal, OtoTheme.spacing16)
            }
            .padding(.bottom, 160)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OtoTheme.spacing8) {
                filterChip("Tất cả", selected: true)
                filterChip("Bài hát", selected: false)
                filterChip("Album", selected: false)
                filterChip("Nghệ sĩ", selected: false)
                filterChip("Playlist", selected: false)
            }
            .padding(.horizontal, OtoTheme.spacing16)
        }
    }

    private func filterChip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(OtoTheme.captionFont)
            .foregroundStyle(selected ? OtoTheme.accent : OtoTheme.secondaryText)
            .padding(.horizontal, OtoTheme.spacing12)
            .frame(minHeight: 34)
            .background(selected ? OtoTheme.accentSurface : OtoTheme.surface)
            .clipShape(Capsule())
    }
}
