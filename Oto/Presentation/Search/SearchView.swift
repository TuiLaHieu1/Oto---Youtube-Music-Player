import SwiftUI
import OtoCore

/// Màn hình tìm kiếm âm nhạc trực tiếp từ YouTube Music theo phong cách Atelier × Spectrum.
public struct SearchView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var searchVM: SearchViewModel
    @Environment(\.displayScale) private var displayScale

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
        self._searchVM = State(initialValue: SearchViewModel())
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
                        .submitLabel(.search)
                        .onSubmit { searchVM.recordCurrentQuery() }
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
                        if searchVM.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            SearchDiscoveryView(
                                recent: searchVM.recentQueries, clearRecent: searchVM.clearRecentQueries
                            ) {
                                searchVM.selectedScope = .all
                                searchVM.query = $0
                                searchVM.recordCurrentQuery()
                            }
                        } else {
                            emptyStateView
                        }
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
        .onChange(of: SessionStore.shared.sessionGeneration) {
            searchVM.clear()
            searchVM.clearRecentQueries()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        OtoLoadingSkeleton()
    }

    private var emptyStateView: some View {
        OtoEmptyState(
            iconName: "magnifyingglass",
            title: "Không tìm thấy kết quả",
            message: "Thử cách viết khác hoặc từ khóa ngắn hơn."
        )
    }

    private var resultsListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                LazyVStack(spacing: OtoTheme.spacing4) {
                    if let top = searchVM.searchResults.topResult {
                        OtoSectionHeader(title: "Kết quả hàng đầu")
                        resultRow(top, featured: true)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: OtoTheme.spacing12)],
                                  spacing: OtoTheme.spacing12) {
                            ForEach(searchVM.searchResults.results.prefix(2)) { result in
                                resultRow(result, featured: true)
                            }
                        }
                    }
                    let featuredCount = searchVM.searchResults.topResult == nil ? 2 : 0
                    ForEach(searchVM.searchResults.results.dropFirst(featuredCount)) { result in
                        resultRow(result)
                    }
                    if searchVM.isLoadingMore {
                        ProgressView()
                    } else if searchVM.searchResults.nextToken != nil {
                        if searchVM.loadMoreFailed { Text("Không thể tải thêm kết quả.") }
                        Button("Tải thêm kết quả", action: searchVM.loadMore)
                    }
                }
                .padding(.horizontal, OtoTheme.spacing16)
            }
            .padding(.bottom, 160)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func resultRow(_ result: MusicSearchResult, featured: Bool = false) -> some View {
        switch result {
        case .song(let song):
            let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
            if featured {
                Button {
                    playSearchSong(song)
                } label: {
                    searchLink(song.title, subtitle: song.artist, category: ("Bài hát", "music.note"),
                               artwork: song.artworkURL, featured: true)
                }
                .buttonStyle(.plain)
            } else {
                OtoSongRow(song: song, isPlaying: isCurrent) { playSearchSong(song) }
            }
        case .video(let video):
            Button {
                playSearchSong(video, isVideo: true)
            } label: {
                searchLink(video.title, subtitle: video.artist, category: ("Video", "play.rectangle"),
                           artwork: video.artworkURL, featured: featured)
            }
            .buttonStyle(.plain)
        case .album(let album):
            NavigationLink {
                AlbumDetailView(browseId: album.id, playerVM: playerVM)
                    .onAppear { searchVM.recordCurrentQuery() }
            } label: {
                searchLink(album.title, subtitle: album.subtitle, category: ("Album", "square.stack"),
                           artwork: album.artworkURL, featured: featured)
            }
        case .artist(let artist, let artwork, let subtitle):
            NavigationLink {
                ArtistDetailView(browseId: artist.browseId, playerVM: playerVM)
                    .onAppear { searchVM.recordCurrentQuery() }
            } label: {
                searchLink(artist.name, subtitle: subtitle, category: ("Nghệ sĩ", "music.mic"),
                           artwork: artwork, featured: featured)
            }
        case .playlist(let playlist):
            NavigationLink {
                PlaylistDetailView(playlist: playlist, playerVM: playerVM)
                    .onAppear { searchVM.recordCurrentQuery() }
            } label: {
                searchLink(playlist.title, subtitle: playlist.subtitle, category: ("Playlist", "music.note.list"),
                           artwork: playlist.artworkURL, featured: featured)
            }
        }
    }

    private func playSearchSong(_ song: Song, isVideo: Bool = false) {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        searchVM.recordCurrentQuery()
        playerVM.playWithRadio(song: song, sourceTitle: "Tìm kiếm", isVideo: isVideo)
    }

    private func searchLink(
        _ title: String, subtitle: String, category: (label: LocalizedStringKey, icon: String),
        artwork: URL?, featured: Bool
    ) -> some View {
        let size: CGFloat = featured ? 96 : 46
        return HStack(spacing: OtoTheme.spacing12) {
            AsyncImage(url: OtoArtworkURL.forDisplay(artwork, points: size, scale: displayScale)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: category.icon)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OtoTheme.surface)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(featured ? .system(.title3, design: .serif, weight: .bold) : OtoTheme.rowTitleFont)
                    .lineLimit(2)
                Text(category.label).font(OtoTheme.captionFont).foregroundStyle(OtoTheme.secondaryText)
                if !subtitle.isEmpty {
                    Text(subtitle).font(OtoTheme.captionFont).foregroundStyle(OtoTheme.secondaryText).lineLimit(2)
                }
            }
        }
        .foregroundStyle(OtoTheme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(featured ? OtoTheme.spacing12 : OtoTheme.spacing8)
        .background(featured ? OtoTheme.accentSurface : .clear,
                    in: RoundedRectangle(cornerRadius: OtoTheme.cardRadius))
        .contentShape(Rectangle())
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OtoTheme.spacing8) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        searchVM.selectedScope = scope
                    } label: {
                        Text(LocalizedStringKey(scope.rawValue))
                            .font(OtoTheme.captionFont)
                            .fontWeight(searchVM.selectedScope == scope ? .semibold : .medium)
                            .foregroundStyle(
                                searchVM.selectedScope == scope
                                    ? OtoTheme.onAccent
                                    : OtoTheme.secondaryText
                            )
                            .padding(.horizontal, OtoTheme.spacing16)
                            .frame(minHeight: 34)
                            .background(
                                searchVM.selectedScope == scope
                                    ? OtoTheme.accent
                                    : OtoTheme.surface
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OtoTheme.spacing16)
        }
    }
}

private struct SearchDiscoveryView: View {
    private struct Category {
        let title: LocalizedStringKey
        let query: String
        let icon: String
    }

    let recent: [String]
    let clearRecent: () -> Void
    let onSelect: (String) -> Void

    private let moods: [Category] = [
        .init(title: "Thư giãn", query: "Chill music", icon: "moon"),
        .init(title: "Tập trung", query: "Focus music", icon: "scope"),
        .init(title: "Tập luyện", query: "Workout music", icon: "bolt.fill"),
        .init(title: "Cảm hứng", query: "Feel-good music", icon: "sun.max")
    ]
    private let genres: [Category] = [
        .init(title: "Nhạc Việt", query: "Nhạc Việt", icon: "music.note.list"),
        .init(title: "Pop", query: "Pop music", icon: "sparkles"),
        .init(title: "Hip-hop", query: "Hip-hop music", icon: "mic"),
        .init(title: "R&B", query: "R&B music", icon: "waveform"),
        .init(title: "Rock", query: "Rock music", icon: "guitars"),
        .init(title: "Jazz", query: "Jazz music", icon: "music.note"),
        .init(title: "Nhạc điện tử", query: "Electronic music", icon: "waveform.path"),
        .init(title: "Lo-fi", query: "Lo-fi music", icon: "headphones")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing20) {
                if !recent.isEmpty { recentSection }
                categoryGrid("Theo tâm trạng và hoạt động", items: moods, accent: true)
                categoryGrid("Khám phá thể loại", items: genres, accent: false)
            }
            .padding(.bottom, 128)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing4) {
            HStack {
                OtoSectionHeader(title: "Tìm kiếm gần đây")
                Button("Xóa lịch sử tìm kiếm", action: clearRecent)
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.accent)
                    .frame(minHeight: OtoTheme.minTouchTarget)
                    .padding(.trailing, OtoTheme.spacing16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OtoTheme.spacing8) {
                    ForEach(recent, id: \.self) { query in
                        Button { onSelect(query) } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .font(OtoTheme.subtitleFont)
                                .foregroundStyle(OtoTheme.primaryText)
                                .lineLimit(1)
                                .padding(.horizontal, OtoTheme.spacing12)
                                .frame(minHeight: OtoTheme.minTouchTarget)
                                .background(OtoTheme.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, OtoTheme.spacing16)
            }
        }
    }

    private func categoryGrid(_ title: String, items: [Category], accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
            OtoSectionHeader(title: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 144), spacing: OtoTheme.spacing12)],
                      spacing: OtoTheme.spacing12) {
                ForEach(items, id: \.query) { item in
                    Button { onSelect(item.query) } label: {
                        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 23, weight: .medium))
                                .foregroundStyle(OtoTheme.accent)
                                .accessibilityHidden(true)
                            Text(item.title)
                                .font(OtoTheme.buttonFont)
                                .foregroundStyle(OtoTheme.primaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .padding(.horizontal, OtoTheme.spacing12)
                        .background(
                            accent ? OtoTheme.accentSurface : OtoTheme.surface,
                            in: RoundedRectangle(cornerRadius: OtoTheme.cardRadius)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OtoTheme.spacing16)
        }
    }
}
