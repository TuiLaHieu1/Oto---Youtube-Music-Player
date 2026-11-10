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
                .font(OtoTheme.subtitleFont)
                .foregroundStyle(OtoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        let isInitial = searchVM.query.isEmpty
        return OtoEmptyState(
            iconName: "magnifyingglass",
            title: isInitial ? "Khám phá bài hát mới" : "Không tìm thấy kết quả phù hợp",
            message: isInitial ? "Nhập tên bài hát hoặc nghệ sĩ bạn muốn nghe." : "Hãy thử tìm kiếm với từ khóa khác."
        )
    }

    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: OtoTheme.spacing8) {
                ForEach(searchVM.searchResults) { song in
                    let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                    OtoSongRow(song: song, isPlaying: isCurrent) {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        let index = searchVM.searchResults.firstIndex(where: { $0.id == song.id }) ?? 0
                        playerVM.playQueue(songs: searchVM.searchResults, startIndex: index)
                    }
                }
            }
            .padding(.horizontal, OtoTheme.spacing16)
            .padding(.top, OtoTheme.spacing12)
            .padding(.bottom, 160) // Chừa khoảng trống nổi cho MiniPlayer
        }
    }
}
