import SwiftUI
import OtoCore

/// Trang nghệ sĩ với bài hát, album và các đề xuất liên quan.
public struct ArtistDetailView: View {
    public let browseId: String
    public let initialArtist: YTMusicParsers.ArtistDetail?
    @Bindable var playerVM: PlayerViewModel

    @State private var artist: YTMusicParsers.ArtistDetail?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var expandedSongs: [Song]?
    @State private var nextSongsToken: String?
    @State private var requestedSongsTokens = Set<String>()
    @State private var songsRequest = 0
    @State private var songsLoading = false
    @State private var songsFailed = false

    public init(
        browseId: String,
        initialArtist: YTMusicParsers.ArtistDetail? = nil,
        playerVM: PlayerViewModel
    ) {
        self.browseId = browseId
        self.initialArtist = initialArtist
        self.playerVM = playerVM
        self._artist = State(initialValue: initialArtist)
        self._isLoading = State(initialValue: initialArtist == nil)
    }

    public var body: some View {
        ZStack {
            OtoTheme.background.ignoresSafeArea()

            Group {
                if isLoading && currentSongs.isEmpty && currentAlbums.isEmpty && currentSections.isEmpty {
                    loadingView
                } else if let error = errorMessage,
                          currentSongs.isEmpty && currentAlbums.isEmpty && currentSections.isEmpty {
                    OtoErrorState(title: "Không thể tải thông tin nghệ sĩ", message: error) {
                        Task { await loadArtist() }
                    }
                } else if !isLoading && currentSongs.isEmpty && currentAlbums.isEmpty && currentSections.isEmpty {
                    OtoEmptyState(
                        title: "Chưa có thông tin",
                        message: "Nghệ sĩ này hiện chưa có bài hát hoặc album khả dụng."
                    )
                } else {
                    contentView
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await loadArtist() }
    }
}

extension ArtistDetailView {
    private var loadingView: some View {
        VStack(spacing: OtoTheme.spacing16) {
            ArtistHeaderView(
                name: displayName,
                description: displayDescription,
                thumbnailURL: displayThumbnailURL
            )
            ProgressView().tint(OtoTheme.accent)
            Text("Đang tải thông tin nghệ sĩ...")
                .font(OtoTheme.captionFont)
                .foregroundStyle(OtoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var contentView: some View {
        ScrollView {
            VStack(spacing: OtoTheme.spacing24) {
                ArtistHeaderView(
                    name: displayName,
                    description: displayDescription,
                    thumbnailURL: displayThumbnailURL
                )

                if !currentSongs.isEmpty {
                    actionButtons
                    topSongsSection
                }

                if !currentSections.isEmpty {
                    artistSections
                }

                if !standaloneAlbums.isEmpty {
                    albumsSection
                }
            }
            .padding(.bottom, 140)
        }
    }
    private func playArtistQueue(_ songs: [Song], startIndex: Int = 0) {
        playerVM.playQueue(songs: songs, startIndex: startIndex, continuesWithRadio: true, sourceTitle: displayName)
    }
    private var actionButtons: some View {
        HStack(spacing: OtoTheme.spacing12) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                playArtistQueue(currentSongs)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Phát tất cả").fontWeight(.semibold)
                }
                .font(OtoTheme.buttonFont)
                .foregroundStyle(OtoTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: OtoTheme.minTouchTarget)
                .background(RoundedRectangle(cornerRadius: OtoTheme.buttonRadius).fill(OtoTheme.accent))
            }
            .buttonStyle(.plain)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                playArtistQueue(currentSongs.shuffled())
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                    Text("Trộn bài").fontWeight(.semibold)
                }
                .font(OtoTheme.buttonFont)
                .foregroundStyle(OtoTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: OtoTheme.minTouchTarget)
                .background(
                    RoundedRectangle(cornerRadius: OtoTheme.buttonRadius)
                        .fill(OtoTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: OtoTheme.buttonRadius)
                                .stroke(OtoTheme.separator, lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OtoTheme.spacing16)
    }
    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
            OtoSectionHeader(title: expandedSongs == nil ? "Bài hát nổi bật" : "Tất cả bài hát")
                .padding(.horizontal, OtoTheme.spacing16)

            LazyVStack(spacing: OtoTheme.spacing4) {
                ForEach(Array(currentSongs.enumerated()), id: \.element.id) { index, song in
                    let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                    OtoSongRow(song: song, isPlaying: isCurrent) {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        playArtistQueue(currentSongs, startIndex: index)
                    }
                }
            }
            .padding(.horizontal, OtoTheme.spacing16)
            if artist?.songsEndpoint != nil, expandedSongs == nil || nextSongsToken != nil {
                Button {
                    songsRequest += 1
                } label: {
                    Text(expandedSongs == nil ? LocalizedStringKey("Xem tất cả bài hát") : "Tải thêm bài hát")
                }
                .disabled(songsLoading)
                .padding(.horizontal, OtoTheme.spacing16)
                if songsLoading { ProgressView() }
                if songsFailed { Text("Không thể tải danh sách bài hát. Vui lòng thử lại.") }
            }
            if expandedSongs != nil {
                Button("Thu gọn", action: collapseSongs)
                    .disabled(songsLoading)
                    .padding(.horizontal, OtoTheme.spacing16)
            }
        }
        .task(id: songsRequest) {
            guard songsRequest > 0, let endpoint = artist?.songsEndpoint else { return }
            await loadSongsPage(endpoint)
        }
    }
    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
            OtoSectionHeader(title: "Album & Đĩa đơn")
                .padding(.horizontal, OtoTheme.spacing16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: OtoTheme.spacing12) {
                    ForEach(standaloneAlbums) { albumPlaylist in
                        NavigationLink {
                            AlbumDetailView(
                                browseId: albumPlaylist.id,
                                initialAlbum: Album(
                                    id: albumPlaylist.id,
                                    title: albumPlaylist.title,
                                    artist: displayName,
                                    artworkURL: albumPlaylist.artworkURL
                                ),
                                playerVM: playerVM
                            )
                        } label: {
                            ArtistAlbumCard(playlist: albumPlaylist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, OtoTheme.spacing16)
            }
        }
    }
    private var artistSections: some View {
        ForEach(currentSections) { section in
            VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                OtoSectionHeader(title: section.title)

                if let subtitle = section.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OtoTheme.captionFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                        .padding(.horizontal, OtoTheme.spacing16)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: OtoTheme.spacing12) {
                        ForEach(section.items) { item in
                            artistSectionCard(for: item)
                        }
                    }
                    .padding(.horizontal, OtoTheme.spacing16)
                }
            }
        }
    }

    @ViewBuilder
    private func artistSectionCard(for item: SpeedDialItem) -> some View {
        switch item.kind {
        case .song:
            OtoAlbumCard(item: item, size: 140) {
                if let song = item.asSong { playerVM.playWithRadio(song: song, sourceTitle: displayName) }
            }
        case .album:
            NavigationLink { AlbumDetailView(browseId: item.id, playerVM: playerVM) } label: {
                OtoAlbumCard(item: item, size: 140)
            }
            .buttonStyle(.plain)
        case .playlist:
            NavigationLink {
                PlaylistDetailView(
                    playlist: Playlist(id: item.id, title: item.title,
                                       subtitle: item.subtitle, artworkURL: item.artworkURL),
                    playerVM: playerVM
                )
            } label: {
                OtoAlbumCard(item: item, size: 140)
            }
            .buttonStyle(.plain)
        case .artist:
            NavigationLink {
                ArtistDetailView(browseId: item.id, playerVM: playerVM)
            } label: {
                OtoAlbumCard(item: item, size: 140)
            }
            .buttonStyle(.plain)
        }
    }
    private var displayName: String { artist?.name ?? initialArtist?.name ?? "Nghệ sĩ" }
    private var displayDescription: String? { artist?.description ?? initialArtist?.description }
    private var displayThumbnailURL: URL? { artist?.thumbnailURL ?? initialArtist?.thumbnailURL }
    private func loadSongsPage(_ endpoint: YTMusicParsers.ArtistSongsEndpoint) async {
        songsLoading = true
        songsFailed = false
        defer { songsLoading = false }
        let token = nextSongsToken
        do {
            let page = try await YTMusicClient.shared.fetchArtistSongs(endpoint: endpoint, continuation: token)
            guard !Task.isCancelled else { return }
            var seen = Set((expandedSongs ?? []).map(\.id))
            let added = page.songs.filter { seen.insert($0.id).inserted }
            guard expandedSongs != nil || !added.isEmpty else {
                songsFailed = true
                return
            }
            expandedSongs = (expandedSongs ?? []) + added
            if let token { requestedSongsTokens.insert(token) }
            nextSongsToken = page.nextToken.flatMap { requestedSongsTokens.contains($0) ? nil : $0 }
        } catch {
            if !Task.isCancelled { songsFailed = true }
        }
    }
    private func collapseSongs() {
        expandedSongs = nil
        nextSongsToken = nil
        requestedSongsTokens.removeAll()
        songsRequest = 0
        songsFailed = false
    }
    private var currentSongs: [Song] { expandedSongs ?? artist?.songs ?? initialArtist?.songs ?? [] }
    private var currentAlbums: [Playlist] { artist?.albums ?? initialArtist?.albums ?? [] }
    private var currentSections: [HomeSection] { artist?.sections ?? initialArtist?.sections ?? [] }
    private var standaloneAlbums: [Playlist] {
        let shownIDs = Set(currentSections.flatMap(\.items).filter { $0.kind == .album }.map(\.id))
        return currentAlbums.filter { !shownIDs.contains($0.id) }
    }

    private func loadArtist() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await YTMusicClient.shared.fetchArtistDetail(browseId: browseId)
            guard !Task.isCancelled else { return }
            self.artist = fetched
            self.isLoading = false
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}

private struct ArtistHeaderView: View {
    let name: String
    let description: String?
    let thumbnailURL: URL?
    var body: some View {
        VStack(spacing: OtoTheme.spacing12) {
            AsyncImage(url: thumbnailURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(OtoTheme.surface)
                    .overlay(
                        Image(systemName: "music.mic")
                            .font(.system(size: 52))
                            .foregroundStyle(OtoTheme.secondaryText)
                    )
            }
            .frame(width: 160, height: 160)
            .clipShape(Circle())
            .overlay(Circle().stroke(OtoTheme.separator.opacity(0.5), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 6)
            VStack(spacing: OtoTheme.spacing8) {
                Text(name)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(OtoTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let desc = description, !desc.isEmpty {
                    Text(desc)
                        .font(OtoTheme.captionFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, OtoTheme.spacing16)
                }
            }
            .padding(.horizontal, OtoTheme.spacing16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OtoTheme.spacing24)
        .background(OtoTheme.accentSurface, in: RoundedRectangle(cornerRadius: OtoTheme.cardRadius))
        .padding(.horizontal, OtoTheme.spacing16)
        .padding(.top, OtoTheme.spacing16)
    }
}
private struct ArtistAlbumCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: playlist.artworkURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: OtoTheme.artworkRadius)
                    .fill(OtoTheme.surface)
                    .overlay(Image(systemName: "opticaldisc").foregroundStyle(OtoTheme.secondaryText))
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: OtoTheme.artworkRadius))

            Text(playlist.title)
                .font(OtoTheme.rowTitleFont)
                .foregroundStyle(OtoTheme.primaryText)
                .lineLimit(1)

            Text(playlist.subtitle)
                .font(OtoTheme.captionFont)
                .foregroundStyle(OtoTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 140)
    }
}
