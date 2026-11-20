import SwiftUI
import OtoCore

/// Màn hình chi tiết Album âm nhạc (Figma D01 Album Detail).
/// Hiển thị ảnh bìa lớn bo góc 16pt, thông tin tiêu đề, nghệ sĩ, năm phát hành, số lượng bài,
/// các nút "Phát tất cả" / "Trộn bài", và danh sách bài hát qua OtoSongRow.
public struct AlbumDetailView: View {
    public let browseId: String
    public let initialAlbum: Album?
    @Bindable var playerVM: PlayerViewModel

    @State private var album: Album?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    public init(
        browseId: String,
        initialAlbum: Album? = nil,
        playerVM: PlayerViewModel
    ) {
        self.browseId = browseId
        self.initialAlbum = initialAlbum
        self.playerVM = playerVM
        self._album = State(initialValue: initialAlbum)
        self._isLoading = State(initialValue: initialAlbum == nil)
    }

    public var body: some View {
        ZStack {
            OtoTheme.background.ignoresSafeArea()

            Group {
                if isLoading && currentSongs.isEmpty {
                    loadingView
                } else if let error = errorMessage, currentSongs.isEmpty {
                    OtoErrorState(title: "Không thể tải album", message: error) {
                        Task { await loadAlbum() }
                    }
                } else if !isLoading && currentSongs.isEmpty {
                    OtoEmptyState(
                        title: "Chưa có bài hát",
                        message: "Album này hiện chưa có bài hát khả dụng."
                    )
                } else {
                    contentView
                }
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await loadAlbum()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: OtoTheme.spacing16) {
            ProgressView()
                .tint(OtoTheme.accent)
            Text("Đang tải thông tin album...")
                .font(OtoTheme.captionFont)
                .foregroundStyle(OtoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: OtoTheme.spacing20) {
                headerView

                if !currentSongs.isEmpty {
                    actionButtons
                    songsListView
                }
            }
            .padding(.bottom, 140)
        }
    }

    private var headerView: some View {
        VStack(spacing: OtoTheme.spacing12) {
            artworkView

            VStack(spacing: OtoTheme.spacing4) {
                Text(displayTitle)
                    .font(.system(.title, design: .serif, weight: .bold))
                    .foregroundStyle(OtoTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(displayArtist)
                    .font(OtoTheme.subtitleFont)
                    .foregroundStyle(OtoTheme.secondaryText)
                    .lineLimit(1)

                metadataSubtitle
            }
            .padding(.horizontal, OtoTheme.spacing16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OtoTheme.spacing24)
        .background(OtoTheme.accentSurface, in: RoundedRectangle(cornerRadius: OtoTheme.cardRadius))
        .padding(.horizontal, OtoTheme.spacing16)
        .padding(.top, OtoTheme.spacing16)
    }

    private var artworkView: some View {
        AsyncImage(url: displayArtworkURL) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                .fill(OtoTheme.surface)
                .overlay(
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 48))
                        .foregroundStyle(OtoTheme.secondaryText)
                )
        }
        .frame(width: 180, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private var metadataSubtitle: some View {
        let parts = metadataParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " • "))
                .font(OtoTheme.captionFont)
                .foregroundStyle(OtoTheme.tertiaryText)
        }
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        if let year = album?.year ?? initialAlbum?.year {
            parts.append(String(year))
        }
        let count = currentSongs.count
        if count > 0 {
            parts.append("\(count) bài hát")
        }
        return parts
    }

    private var actionButtons: some View {
        HStack(spacing: OtoTheme.spacing12) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                playerVM.playQueue(songs: currentSongs, startIndex: 0, sourceTitle: displayTitle)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Phát tất cả")
                        .fontWeight(.semibold)
                }
                .font(OtoTheme.buttonFont)
                .foregroundStyle(OtoTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: OtoTheme.minTouchTarget)
                .background(
                    RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                        .fill(OtoTheme.accent)
                )
            }
            .buttonStyle(.plain)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                var shuffled = currentSongs
                shuffled.shuffle()
                playerVM.playQueue(songs: shuffled, startIndex: 0, sourceTitle: displayTitle)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                    Text("Trộn bài")
                        .fontWeight(.semibold)
                }
                .font(OtoTheme.buttonFont)
                .foregroundStyle(OtoTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: OtoTheme.minTouchTarget)
                .background(
                    RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                        .fill(OtoTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                                .stroke(OtoTheme.separator, lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OtoTheme.spacing16)
    }

    private var songsListView: some View {
        LazyVStack(spacing: OtoTheme.spacing4) {
            ForEach(Array(currentSongs.enumerated()), id: \.element.id) { index, song in
                let isCurrent = playerVM.currentSong?.id == song.id && playerVM.isPlaying
                OtoSongRow(song: song, isPlaying: isCurrent) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    playerVM.playQueue(songs: currentSongs, startIndex: index, sourceTitle: displayTitle)
                }
            }
        }
        .padding(.horizontal, OtoTheme.spacing16)
    }

    // MARK: - Computed Properties

    private var displayTitle: String {
        album?.title ?? initialAlbum?.title ?? "Album"
    }

    private var displayArtist: String {
        album?.artist ?? initialAlbum?.artist ?? "Nghệ sĩ"
    }

    private var displayArtworkURL: URL? {
        album?.artworkURL ?? initialAlbum?.artworkURL
    }

    private var currentSongs: [Song] {
        album?.songs ?? initialAlbum?.songs ?? []
    }

    // MARK: - Data Loading

    private func loadAlbum() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await YTMusicClient.shared.fetchAlbumDetail(browseId: browseId)
            guard !Task.isCancelled else { return }
            self.album = fetched
            self.isLoading = false
        } catch is CancellationError {
            // Task bị huỷ bình thường khi người dùng rời màn hình
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}
