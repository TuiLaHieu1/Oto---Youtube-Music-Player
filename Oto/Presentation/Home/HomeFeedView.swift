import SwiftUI
import OtoCore

/// Màn hình Trang chủ (Home Feed) của Oto theo ngôn ngữ Atelier Light × Spectrum Dark.
public struct HomeFeedView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var homeVM = HomeViewModel()
    @State private var selectedSpeedDialCollection: SpeedDialItem?
    @AppStorage("app_language") private var selectedLanguage = AppLanguage.system.rawValue

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                GeometryReader { geometry in
                    RadialGradient(
                        stops: [
                            .init(color: OtoTheme.homeAmbient.opacity(0.84), location: 0),
                            .init(color: OtoTheme.homeAmbient.opacity(0.40), location: 0.55),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: hypot(geometry.size.width, geometry.size.height) * 0.55
                    )
                    .background(OtoTheme.background)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                Group {
                    if homeVM.isLoading && !hasVisibleContent {
                        OtoLoadingSkeleton()
                    } else if let error = homeVM.errorMessage, !hasVisibleContent {
                        OtoErrorState(message: error) { Task { await homeVM.refresh() } }
                    } else if !hasVisibleContent {
                        OtoEmptyState(
                            title: "Chưa có gợi ý âm nhạc",
                            message: "Vuốt xuống để tải lại từ YouTube Music hoặc mở tab Tìm kiếm để chọn bài hát.",
                            actionTitle: "Tải gợi ý"
                        ) { Task { await homeVM.refresh() } }
                    } else {
                        feedScrollView
                    }
                }
            }
            .navigationTitle("Trang chủ")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await homeVM.refresh() }
            .task { await homeVM.loadIfNeeded() }
            .onChange(of: selectedLanguage) { _, _ in
                Task { await homeVM.refresh() }
            }
            .navigationDestination(item: $selectedSpeedDialCollection) { item in
                collectionDetail(for: item)
            }
        }
    }

}

private extension HomeFeedView {
    private var hasVisibleContent: Bool { self.homeVM.hasVisibleContent || !self.playerVM.recentlyPlayed.isEmpty }

    // MARK: - Feed Content

    private var feedScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing24) {
                if homeVM.refreshIncomplete {
                    Button {
                        Task { await homeVM.refresh() }
                    } label: {
                        Label("Chưa tải đủ gợi ý mới · Thử lại", systemImage: "arrow.clockwise")
                            .font(OtoTheme.captionFont)
                            .foregroundStyle(OtoTheme.accent)
                            .frame(minHeight: OtoTheme.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, OtoTheme.spacing16)
                }
                VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: OtoTheme.spacing4) {
                            Text("Dành cho bạn")
                                .font(.system(.largeTitle, design: .serif, weight: .bold))
                                .foregroundStyle(OtoTheme.primaryText)
                            Text("Một khoảng nhỏ để lắng nghe.")
                                .font(OtoTheme.subtitleFont)
                                .foregroundStyle(OtoTheme.secondaryText)
                        }
                        Spacer()
                        Button {
                            playerVM.showAuth = true
                        } label: {
                            let isAuth = SessionStore.shared.isAuthenticated
                            Image(systemName: isAuth ? "person.crop.circle.badge.checkmark" : "person.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(isAuth ? OtoTheme.accent : OtoTheme.controlInactive)
                                .frame(width: OtoTheme.minTouchTarget, height: OtoTheme.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                    }
                    if let song = homeVM.quickPicks.first ?? playerVM.recentlyPlayed.first {
                        featuredSong(song).contextMenu { pinAction(SpeedDialItem(song: song)) }
                    }
                }
                .padding(OtoTheme.spacing16)
                .background {
                    RoundedRectangle(cornerRadius: OtoTheme.cardRadius)
                        .fill(LinearGradient(
                            colors: [OtoTheme.accentSurface, OtoTheme.surface],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .overlay {
                            RoundedRectangle(cornerRadius: OtoTheme.cardRadius)
                                .strokeBorder(OtoTheme.separator.opacity(0.65))
                        }
                }
                .padding(.horizontal, OtoTheme.spacing16)
                .padding(.top, OtoTheme.spacing8)

                if !homeVM.pinnedItems.isEmpty {
                    tileShelf(title: "Đã ghim trong Oto", subtitle: nil, items: homeVM.pinnedItems)
                }

                if !homeVM.sections.isEmpty {
                    ForEach(homeVM.sections) { section in
                        if section.id.hasPrefix("server_speed_dial_") {
                            tileShelf(title: section.title, subtitle: section.subtitle, items: section.items)
                        } else if !section.items.isEmpty {
                            serverShelf(section)
                        }
                    }
                } else {
                    if !homeVM.quickPicks.isEmpty {
                        fallbackSection(title: "Lựa chọn nhanh", songs: homeVM.quickPicks)
                    }
                    if !homeVM.listenAgain.isEmpty {
                        fallbackSection(title: "Nghe lại gần đây", songs: homeVM.listenAgain)
                    }
                }

                if homeVM.moreRecommendationsUnavailable { HomeRecommendationsTail() }
                if !playerVM.recentlyPlayed.isEmpty {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
                        OtoSectionHeader(title: "Đã phát gần đây")

                        VStack(spacing: OtoTheme.spacing8) {
                            ForEach(playerVM.recentlyPlayed) { song in
                                let isCurrent = (playerVM.currentSong?.id == song.id) && playerVM.isPlaying
                                OtoSongRow(song: song, isPlaying: isCurrent) {
                                    play(song, in: playerVM.recentlyPlayed, sourceTitle: "Đã phát gần đây")
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

    private func tileShelf(title: String, subtitle: String?, items: [SpeedDialItem]) -> some View {
        HomeTileShelf(title: title, subtitle: subtitle, size: tileSize, items: items) { item in
            let displayedItem = markedPin(item)
            SpeedDialTileView(
                item: displayedItem,
                isCurrent: playerVM.currentSong?.id == item.id && playerVM.isPlaying,
                size: tileSize,
                onSelect: { openSpeedDialItem(item, sourceTitle: title) },
                onTogglePin: { homeVM.togglePin(for: item) }
            )
        }
    }

    private func serverShelf(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
            HomeShelfTitle(title: section.title, subtitle: section.subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: OtoTheme.spacing12) {
                    ForEach(section.items) { item in
                        sectionCard(for: item, sourceTitle: section.title)
                            .contextMenu { pinAction(item) }
                    }
                }
                .padding(.horizontal, OtoTheme.spacing16)
            }
        }
    }

    private func markedPin(_ item: SpeedDialItem) -> SpeedDialItem {
        var copy = item
        copy.isPinned = homeVM.pinnedItems.contains { $0.id == item.id }
        return copy
    }

    private func pinAction(_ item: SpeedDialItem) -> some View {
        let isPinned = markedPin(item).isPinned
        return Button(isPinned ? LocalizedStringKey("Bỏ ghim trong Oto") : "Ghim trong Oto",
                      systemImage: isPinned ? "pin.slash" : "pin") {
            homeVM.togglePin(for: item)
        }
    }

    private func featuredSong(_ song: Song) -> some View {
        Button {
            let songs = homeVM.quickPicks.isEmpty ? playerVM.recentlyPlayed : homeVM.quickPicks
            play(song, in: songs, sourceTitle: "Dành cho bạn")
        } label: {
            HStack(spacing: OtoTheme.spacing16) {
                VStack(alignment: .leading, spacing: OtoTheme.spacing4) {
                    Text(song.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .lineLimit(2)
                    Text(song.artist)
                        .font(OtoTheme.subtitleFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                        .lineLimit(2)
                    Image(systemName: "play.fill")
                        .foregroundStyle(OtoTheme.accent)
                        .padding(.top, OtoTheme.spacing4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                OtoTrackArtwork(url: song.artworkURL, points: 116) {
                    OtoTheme.surface.overlay(Image(systemName: "music.note"))
                }
                .frame(width: 116, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.artworkRadius))
                .accessibilityHidden(true)
            }
            .foregroundStyle(OtoTheme.primaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Nhấn đúp để phát bài hát này")
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func play(_ song: Song, in songs: [Song], sourceTitle: String) {
        triggerHaptic()
        let index = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        playerVM.playQueue(songs: songs, startIndex: index, sourceTitle: sourceTitle)
    }

    private func openSpeedDialItem(_ item: SpeedDialItem, sourceTitle: String) {
        switch item.kind {
        case .song:
            if let song = item.asSong { playerVM.playWithRadio(song: song, sourceTitle: sourceTitle) }
        case .album, .playlist, .artist:
            selectedSpeedDialCollection = item
        }
    }

    @ViewBuilder
    private func collectionDetail(for item: SpeedDialItem) -> some View {
        switch item.kind {
        case .album:
            AlbumDetailView(browseId: item.id, playerVM: playerVM)
        case .playlist:
            let playlist = Playlist(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                artworkURL: item.artworkURL
            )
            PlaylistDetailView(playlist: playlist, playerVM: playerVM)
        case .artist:
            ArtistDetailView(
                browseId: item.id,
                initialArtist: .init(id: item.id, name: item.title, thumbnailURL: item.artworkURL),
                playerVM: playerVM
            )
        case .song:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sectionCard(for item: SpeedDialItem, sourceTitle: String) -> some View {
        let isCurrent = (playerVM.currentSong?.id == item.id) && playerVM.isPlaying
        let card = OtoAlbumCard(item: item, isPlaying: isCurrent, size: 152)
        switch item.kind {
        case .song:
            HomeLandscapeSongCard(
                title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL, isPlaying: isCurrent
            ) {
                if let song = item.asSong { playerVM.playWithRadio(song: song, sourceTitle: sourceTitle) }
            }
        case .album:
            NavigationLink { AlbumDetailView(browseId: item.id, playerVM: playerVM) } label: { card }
                .buttonStyle(.plain)
        case .playlist:
            let pl = Playlist(id: item.id, title: item.title, subtitle: item.subtitle, artworkURL: item.artworkURL)
            NavigationLink { PlaylistDetailView(playlist: pl, playerVM: playerVM) } label: { card }
                .buttonStyle(.plain)
        case .artist:
            NavigationLink {
                ArtistDetailView(
                    browseId: item.id,
                    initialArtist: .init(id: item.id, name: item.title, thumbnailURL: item.artworkURL),
                    playerVM: playerVM
                )
            } label: { card }
                .buttonStyle(.plain)
        }
    }

    private func fallbackSection(title: String, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
            OtoSectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: OtoTheme.spacing12) {
                    ForEach(songs) { song in
                        let isCur = (playerVM.currentSong?.id == song.id) && playerVM.isPlaying
                        HomeLandscapeSongCard(
                            title: song.title, subtitle: song.artist, artworkURL: song.artworkURL, isPlaying: isCur
                        ) {
                            play(song, in: songs, sourceTitle: title)
                        }
                        .contextMenu { pinAction(SpeedDialItem(song: song)) }
                    }
                }
                .padding(.horizontal, OtoTheme.spacing16)
            }
        }
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

private struct HomeLandscapeSongCard: View {
    @Environment(\.displayScale) private var displayScale

    let title: String
    let subtitle: String
    let artworkURL: URL?
    let isPlaying: Bool
    let action: () -> Void

    private let width: CGFloat = 208

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OtoTheme.spacing4) {
                OtoTheme.surface
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: OtoArtworkURL.forDisplay(artworkURL, points: width, scale: displayScale)) {
                            $0.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "music.note")
                                .foregroundStyle(OtoTheme.secondaryText)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: OtoTheme.artworkRadius))
                    .accessibilityHidden(true)

                HStack(spacing: OtoTheme.spacing4) {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .lineLimit(1)
                }
                .font(OtoTheme.cardTitleFont)
                .foregroundStyle(isPlaying ? OtoTheme.accent : OtoTheme.primaryText)
                Text(subtitle)
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Nhấn đúp để phát bài hát này")
    }
}
