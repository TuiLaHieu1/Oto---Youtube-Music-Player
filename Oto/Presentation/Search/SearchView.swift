import SwiftUI
import OtoCore

/// Màn hình tìm kiếm âm nhạc trực tiếp từ YouTube Music.
public struct SearchView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var searchVM = SearchViewModel()

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            Group {
                if searchVM.isLoading && searchVM.searchResults.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Đang tìm bài hát...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchVM.searchResults.isEmpty {
                    emptyStateView
                } else {
                    resultsListView
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

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(searchVM.query.isEmpty ? "Khám phá bài hát mới" : "Không tìm thấy kết quả phù hợp")
                .font(.headline)
            let subtext = searchVM.query.isEmpty
                ? "Nhập tên bài hát hoặc nghệ sĩ bạn muốn nghe."
                : "Hãy thử tìm kiếm với từ khóa khác."
            Text(subtext)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsListView: some View {
        List {
            ForEach(searchVM.searchResults) { song in
                let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    let index = searchVM.searchResults.firstIndex(of: song) ?? 0
                    playerVM.playQueue(songs: searchVM.searchResults, startIndex: index)
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: song.artworkURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.2))
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if isCurrent {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative.reversing)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .padding(.bottom, 160) // Khoảng trống cho MiniPlayer nổi trên TabBar
    }
}
