import SwiftUI
import OtoCore

/// Màn hình thư viện nhạc cá nhân và cài đặt ứng dụng theo chuẩn Atelier × Spectrum.
public struct LibraryView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var libraryVM = LibraryViewModel()
    @State private var sessionStore = SessionStore.shared
    @State private var showSettings: Bool = false
    @State private var selectedCategory: Category = .all
    @Environment(\.displayScale) private var displayScale

    private enum Category: String, CaseIterable {
        case all = "Tất cả"
        case playlists = "Playlist"
        case albums = "Album"
        case artists = "Nghệ sĩ"
    }

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    private var librarySessionID: Int? {
        sessionStore.isAuthenticated ? sessionStore.sessionGeneration : nil
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OtoTheme.spacing24) {
                    HStack {
                        Text("Thư viện của bạn")
                            .font(OtoTheme.largeTitleFont)
                            .foregroundStyle(OtoTheme.primaryText)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(OtoTheme.controlInactive)
                                .frame(width: OtoTheme.minTouchTarget, height: OtoTheme.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                    }

                    categoryChips

                    if selectedCategory == .all {
                        likedSongsLink
                        NavigationLink {
                            LocalMusicView(playerVM: playerVM)
                        } label: {
                            Label("Nhạc trên thiết bị", systemImage: "folder")
                                .font(OtoTheme.sectionTitleFont)
                                .foregroundStyle(OtoTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(OtoTheme.spacing16)
                                .background(OtoTheme.surface, in: RoundedRectangle(
                                    cornerRadius: OtoTheme.cardRadius
                                ))
                        }
                        .buttonStyle(.plain)
                    }
                    if selectedCategory == .all || selectedCategory == .playlists {
                        playlistsSection
                    }
                    if selectedCategory == .all || selectedCategory == .albums {
                        collectionSection(.albums, title: "Album", icon: "square.stack")
                    }
                    if selectedCategory == .all || selectedCategory == .artists {
                        collectionSection(.artists, title: "Nghệ sĩ", icon: "music.mic")
                    }
                }
                .padding(.horizontal, OtoTheme.spacing16)
                .padding(.top, OtoTheme.spacing8)
                .padding(.bottom, 120)
            }
            .background(OtoTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                sessionStore.refreshSessionState()
                libraryVM.updateCacheSize()
            }
            .task(id: librarySessionID) {
                if sessionStore.isAuthenticated {
                    if libraryVM.likedSongs.isEmpty {
                        await libraryVM.loadLikedSongs()
                    }
                    if libraryVM.playlists.isEmpty {
                        await libraryVM.loadPlaylists()
                    }
                }
            }
            .refreshable {
                if sessionStore.isAuthenticated {
                    await libraryVM.loadLikedSongs()
                    await libraryVM.loadPlaylists()
                    await libraryVM.loadCollection(.albums)
                    await libraryVM.loadCollection(.artists)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(playerVM: playerVM, libraryVM: libraryVM)
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OtoTheme.spacing8) {
                ForEach(Category.allCases, id: \.self) { category in
                    let selected = category == selectedCategory
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(LocalizedStringKey(category.rawValue))
                            .font(OtoTheme.captionFont)
                            .foregroundStyle(selected ? OtoTheme.accent : OtoTheme.secondaryText)
                            .padding(.horizontal, OtoTheme.spacing12)
                            .frame(minHeight: OtoTheme.minTouchTarget)
                            .background(selected ? OtoTheme.accentSurface : OtoTheme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var likedSongsLink: some View {
        if sessionStore.isAuthenticated {
            NavigationLink {
                LikedSongsView(playerVM: playerVM, libraryVM: libraryVM)
            } label: {
                libraryCard
            }
            .buttonStyle(.plain)
        } else {
            Button {
                playerVM.showAuth = true
            } label: {
                libraryCard
            }
            .buttonStyle(.plain)
        }
    }

    private var libraryCard: some View {
        HStack {
            Image(systemName: "heart")
                .foregroundStyle(OtoTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bài hát đã thích")
                    .font(OtoTheme.sectionTitleFont)
                    .foregroundStyle(OtoTheme.primaryText)
                Group {
                    if sessionStore.isAuthenticated {
                        Text("\(libraryVM.likedSongs.count) bài hát")
                    } else {
                        Text("Đăng nhập để xem thư viện")
                    }
                }
                .font(OtoTheme.captionFont)
                .foregroundStyle(OtoTheme.secondaryText)
            }
            Spacer()
        }
        .padding(OtoTheme.spacing16)
        .background(OtoTheme.accentSurface)
        .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous))
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
            OtoSectionHeader(title: "Danh sách phát của bạn")
            if sessionStore.isAuthenticated {
                Text("\(libraryVM.playlists.count) danh sách phát")
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.secondaryText)
            }

            if libraryVM.playlists.isEmpty {
                Text("Chưa có nội dung")
                    .font(OtoTheme.rowTitleFont)
                    .foregroundStyle(OtoTheme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: OtoTheme.spacing12)],
                          alignment: .leading, spacing: OtoTheme.spacing12) {
                    ForEach(libraryVM.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist, playerVM: playerVM)
                        } label: {
                            playlistTile(playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private func playlistTile(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncImage(url: OtoArtworkURL.forDisplay(playlist.artworkURL, points: 200, scale: displayScale)) {
                        $0.resizable().scaledToFill()
                    } placeholder: {
                        OtoTheme.surface.overlay(Image(systemName: "music.note.list"))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius))
                .accessibilityHidden(true)
            Text(playlist.title)
                .font(OtoTheme.cardTitleFont)
                .lineLimit(2)
            if !playlist.subtitle.isEmpty {
                Text(playlist.subtitle)
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(OtoTheme.primaryText)
        .padding(OtoTheme.spacing12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OtoTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: OtoTheme.cardRadius))
    }

}

extension LibraryView {
    private func collectionSection(_ kind: LibraryCollection, title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
            if let page = libraryVM.collections[kind], !page.items.isEmpty {
                OtoSectionHeader(title: title)
                ForEach(page.items) { item in
                    NavigationLink {
                        if kind == .albums {
                            AlbumDetailView(browseId: item.id, playerVM: playerVM)
                        } else {
                            ArtistDetailView(browseId: item.id, playerVM: playerVM)
                        }
                    } label: {
                        collectionRow(item, icon: icon, roundArtwork: kind == .artists)
                    }
                }
            } else if libraryVM.loadingCollections.contains(kind) || libraryVM.failedCollections.contains(kind) {
                OtoSectionHeader(title: title)
            } else {
                librarySection(title: title, icon: icon)
            }

            if libraryVM.loadingCollections.contains(kind) {
                ProgressView()
            } else if libraryVM.failedCollections.contains(kind) || libraryVM.collections[kind]?.nextToken != nil {
                if libraryVM.failedCollections.contains(kind) {
                    Text("Không thể tải dữ liệu")
                }
                let failed = libraryVM.failedCollections.contains(kind)
                let action: LocalizedStringKey = failed ? "Thử lại" : "Tải thêm kết quả"
                Button(action) {
                    let hasNextPage = libraryVM.collections[kind]?.nextToken != nil
                    Task { await libraryVM.loadCollection(kind, loadMore: hasNextPage) }
                }
            }
        }
        .task(id: librarySessionID) {
            guard sessionStore.isAuthenticated, libraryVM.collections[kind] == nil else { return }
            await libraryVM.loadCollection(kind)
        }
    }

    private func collectionRow(
        _ item: Playlist, icon: String, roundArtwork: Bool = false, subtitle: String? = nil
    ) -> some View {
        let size: CGFloat = 48
        let artwork = OtoArtworkURL.forDisplay(item.artworkURL, points: size, scale: displayScale)
        return HStack(spacing: OtoTheme.spacing12) {
            AsyncImage(url: artwork) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: icon)
                    .foregroundStyle(OtoTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OtoTheme.surface)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: roundArtwork ? size / 2 : OtoTheme.smallArtworkRadius))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(OtoTheme.rowTitleFont)
                    .foregroundStyle(OtoTheme.primaryText)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(LocalizedStringKey(subtitle))
                        .font(OtoTheme.captionFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            if subtitle != nil {
                Spacer(minLength: OtoTheme.spacing8)
                Image(systemName: "chevron.right")
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func librarySection(title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
            Text(LocalizedStringKey(title))
                .font(OtoTheme.sectionTitleFont)
                .foregroundStyle(OtoTheme.primaryText)
            HStack(spacing: OtoTheme.spacing12) {
                RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous)
                    .fill(OtoTheme.backgroundSecondary)
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: icon).foregroundStyle(OtoTheme.tertiaryText))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chưa có nội dung")
                        .font(OtoTheme.rowTitleFont)
                    Text("Nội dung khả dụng sẽ xuất hiện tại đây.")
                        .font(OtoTheme.captionFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                }
            }
        }
    }
}
