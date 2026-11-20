import SwiftUI
import OtoCore

/// Màn hình phát nhạc toàn màn hình (Fullscreen Player) giao thoa Atelier Light × Spectrum Dark.
public struct FullscreenPlayerView: View {
    @Bindable var playerVM: PlayerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lyricsVM = LyricsViewModel()
    @State private var selectedArtist: ArtistReference?
    @State private var albumLookupSong: Song?
    @State private var hidesWideLyrics = false
    @State private var orientation = PlayerWindowOrientation()
    @State private var rotationDenied = false
    @State private var videoAvailableID: String?
    @State private var selectedVideoID: String?
    @State private var videoIsExpanded = false
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.22)))
    private var artworkDragOffset: CGFloat = 0

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        GeometryReader { geo in
            if geo.size.width >= (geo.size.width > geo.size.height ? 690 : 760) {
                widePlayerLayout(size: geo.size)
            } else {
                compactPlayerLayout(geo: geo).transition(layoutTransition)
            }
        }
        .accessibilityHidden(videoIsExpanded)
        .overlayPreferenceValue(PlayerVideoAnchor.self) { anchor in
            if showsVideo, let anchor {
                PlayerVideoOverlay(anchor: anchor, url: playerVM.currentSong?.artworkURL, expanded: videoIsExpanded) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.34)) { videoIsExpanded.toggle() }
                }
            }
        }
        .background(PlayerWindowAnchor(orientation: orientation).allowsHitTesting(false))
        .alert("Không thể xoay màn hình", isPresented: $rotationDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thử tắt khóa xoay hoặc mở Oto toàn màn hình rồi thử lại.")
        }
        .background {
            GeometryReader { backgroundGeometry in
                AmbientBackgroundView(
                    artworkURL: playerVM.currentSong?.artworkURL, size: backgroundGeometry.size
                )
            }
            .ignoresSafeArea()
        }
        .task(id: playerVM.currentSong?.id) {
            selectedVideoID = nil
            videoIsExpanded = false
            let availableID = await PlayerVideoAvailability.availableID(for: playerVM.currentSong)
            if !Task.isCancelled { videoAvailableID = availableID }
        }
        .onChange(of: playerVM.currentSong) { _, newSong in
            if let newSong { lyricsVM.loadLyrics(for: newSong) }
        }
        .onChange(of: playerVM.currentPosition) { _, pos in
            lyricsVM.updatePosition(pos)
        }
        .onChange(of: lyricsVM.currentDocument) {
            lyricsVM.updatePosition(playerVM.currentPosition)
        }
        .onAppear {
            if let song = playerVM.currentSong {
                lyricsVM.loadLyrics(for: song)
            }
        }
        .sheet(isPresented: $playerVM.showQueue) {
            QueueView(playerVM: playerVM)
        }
        .sheet(item: $albumLookupSong) { song in
            NavigationStack {
                PlayerAlbumLookup(song: song, playerVM: playerVM)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đóng") { albumLookupSong = nil }
                        }
                    }
            }
        }
        .sheet(item: $selectedArtist) { artist in
            NavigationStack {
                ArtistDetailView(browseId: artist.browseId, playerVM: playerVM)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đóng") { selectedArtist = nil }
                        }
                    }
            }
        }
    }

    private func compactPlayerLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            playerHeader()
                .contentShape(Rectangle())
                .simultaneousGesture(playerSwipe)

            ZStack {
                if playerVM.showLyrics {
                    SyncedLyricsView(lyricsVM: lyricsVM, onSeek: playerVM.seek)
                        .transition(layoutTransition)
                } else {
                    artworkView(geo: geo)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .simultaneousGesture(playerSwipe)
                        .transition(layoutTransition)
                }
            }
            .animation(reduceMotion ? nil : OtoTheme.smoothSpring, value: playerVM.showLyrics)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: OtoTheme.spacing24) {
                trackMetadataView
                scrubberView
                transportControls
                bottomBar(isLandscape: geo.size.width > geo.size.height)
            }
            .padding(.bottom, OtoTheme.spacing16)
        }
    }

    private func widePlayerLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            playerHeader(wide: true, isLandscape: size.width > size.height)
                .contentShape(Rectangle())
                .simultaneousGesture(playerSwipe)
            let short = size.height < 540
            HStack(alignment: .top, spacing: short ? 12 : OtoTheme.spacing32) {
                Group {
                    if showsVideo {
                        ScrollView { wideControls(size: size, short: short) }
                    } else {
                        ViewThatFits(in: .vertical) {
                            wideControls(size: size, short: short)
                            ScrollView { wideControls(size: size, short: short) }
                        }
                    }
                }
                .frame(width: min(size.width * (hidesWideLyrics ? 0.8 : 0.47), 520))
                .frame(maxHeight: .infinity)

                if !hidesWideLyrics {
                    WideLyricsPanel(lyricsVM: lyricsVM, onSeek: playerVM.seek)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, short ? 12 : OtoTheme.spacing32)
            .padding(.bottom, short ? 8 : OtoTheme.spacing24)
        }
    }

    private var playerSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($artworkDragOffset) { value, offset, _ in
                let movement = value.translation
                if !reduceMotion, abs(movement.width) > abs(movement.height) * 1.5 {
                    offset = min(100, max(-100, movement.width * 0.65))
                }
            }
            .onEnded { value in
                let movement = value.translation
                switch MiniPlayerSwipePolicy.action(translation: movement) {
                case .previous: playerVM.previous()
                case .next: playerVM.next()
                case nil:
                    if movement.height >= 64, movement.height > abs(movement.width) * 1.5 {
                        withAnimation(reduceMotion ? nil : OtoTheme.smoothSpring) { playerVM.isExpanded = false }
                    }
                }
            }
    }

    private func wideControls(size: CGSize, short: Bool) -> some View {
        let artworkHeight = size.height * (short ? (showsVideo ? 0.36 : 0.26) : 0.44)
        return VStack(spacing: short ? 6 : OtoTheme.spacing16) {
            artworkImage(size: min(size.width * (showsVideo ? 0.42 : 0.32), artworkHeight * (showsVideo ? 16 / 9 : 1)),
                         allowsModeSwitch: true)
                .contentShape(Rectangle())
                .simultaneousGesture(playerSwipe)
            trackMetadataView
            scrubberView
            playbackControls(size: short ? 44 : 64)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var layoutTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98))
    }
    private func playerHeader(wide: Bool = false, isLandscape: Bool = false) -> some View {
        FullscreenHeaderBar(
            isExpanded: $playerVM.isExpanded,
            playingFromTitle: playerVM.playbackSourceTitle ?? "",
            extraControlCount: wide ? 2 : 0
        ) {
            if !wide, canShowVideo { PlayerMediaModePicker(showsVideo: showsVideo, selectVideo: selectVideo) }
        } controls: {
            if wide {
                landscapeLyricsButton(isLandscape: isLandscape)
                wideLyricsToggle
            }
        } actions: {
            if let song = playerVM.currentSong {
                Button("Phát tiếp theo", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    playerVM.queueManager.insertNext(song: song)
                }
                Button("Thêm vào hàng đợi", systemImage: "text.badge.plus") {
                    playerVM.queueManager.append(song: song)
                }
                Button("Hàng đợi", systemImage: "list.bullet") { playerVM.showQueue = true }
                if !song.isLocal {
                    if let url = URL(string: "https://music.youtube.com/watch?v=" + song.id) {
                        ShareLink(item: url) { Label("Chia sẻ bài hát", systemImage: "square.and.arrow.up") }
                    }
                    if let album = song.album, !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Đi tới album", systemImage: "opticaldisc") { albumLookupSong = song }
                    }
                    ForEach(PlayerArtistLinks.menuArtists(for: song)) { artist in
                        Button(artist.name, systemImage: "music.mic") { selectedArtist = artist }
                    }
                }
            }
        }
    }
}

private extension FullscreenPlayerView {
    private func artworkView(geo: GeometryProxy) -> some View {
        artworkImage(size: max(0, min(geo.size.width - (showsVideo ? 24 : 64), showsVideo ? 600 : 340)))
    }

    private func artworkImage(size: CGFloat, allowsModeSwitch: Bool = false) -> some View {
        PlayerMediaArtwork(
            url: playerVM.currentSong?.artworkURL, size: size, showsVideo: showsVideo, isPlaying: playerVM.isPlaying,
            onSwitchMode: allowsModeSwitch && canShowVideo ? { selectVideo(!showsVideo) } : nil
        )
        .offset(x: artworkDragOffset)
    }

    private var canShowVideo: Bool {
        guard let id = playerVM.currentSong?.id else { return false }
        return videoAvailableID == id || playerVM.confirmedVideoSelectionID == id
    }

    private func selectVideo(_ wantsVideo: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            if wantsVideo { playerVM.showLyrics = false }
            selectedVideoID = wantsVideo ? playerVM.currentSong?.id : nil
        }
    }

    private var showsVideo: Bool {
        selectedVideoID != nil && selectedVideoID == playerVM.currentSong?.id
    }

    private var trackMetadataView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playerVM.currentSong?.title ?? "Chưa phát")
                    .font(.system(.title2, design: .default, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(OtoTheme.primaryText)

                HStack(spacing: 6) {
                    artistLinks
                        .font(OtoTheme.subtitleFont)
                        .lineLimit(1)

                    if playerVM.isBuffering {
                        ProgressView()
                            .tint(OtoTheme.accent)
                            .scaleEffect(0.7)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, OtoTheme.spacing32)
    }

    @ViewBuilder
    private var artistLinks: some View {
        let song = playerVM.currentSong
        let artists = song.map { PlayerArtistLinks.menuArtists(for: $0) } ?? []
        if artists.isEmpty {
            Text(PlayerArtistLinks.artistName(for: song) ?? "Oto Music")
                .foregroundStyle(OtoTheme.secondaryText)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OtoTheme.spacing8) {
                    ForEach(artists) { artist in
                        Button {
                            selectedArtist = artist
                        } label: {
                            Text(artist.name).underline()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(OtoTheme.secondaryText)
                    }
                }
            }
        }
    }

    private var scrubberView: some View {
        OtoScrubber(
            currentTime: playerVM.currentPosition,
            duration: playerVM.effectiveDuration,
            onSeek: { seekTime in
                playerVM.seek(to: seekTime)
            }
        )
        .padding(.horizontal, OtoTheme.spacing32)
    }

    private var transportControls: some View {
        playbackControls(size: 64)
            .padding(.vertical, 4)
    }

    private func playbackControls(size: CGFloat) -> some View {
        OtoPlaybackControls(
            isPlaying: playerVM.shouldShowPauseButton,
            isShuffleEnabled: playerVM.isShuffleEnabled,
            canShuffle: playerVM.canShuffle, repeatMode: playerVM.repeatMode,
            playButtonSize: size,
            onShuffle: { playerVM.toggleShuffle() },
            onPrevious: { playerVM.previous() },
            onTogglePlayPause: { playerVM.togglePlayPause() },
            onNext: { playerVM.next() },
            onRepeat: { playerVM.toggleRepeat() }
        )
    }

    private func bottomBar(isLandscape: Bool) -> some View {
        HStack(spacing: OtoTheme.spacing8) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(OtoTheme.smoothSpring) {
                    playerVM.showLyrics.toggle()
                }
            } label: {
                Label("Lời bài hát", systemImage: playerVM.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(OtoTheme.buttonFont)
                    .foregroundStyle(playerVM.showLyrics ? OtoTheme.accent : OtoTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: OtoTheme.minTouchTarget)
                    .background(OtoTheme.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                playerVM.showQueue = true
            } label: {
                Label("Hàng đợi", systemImage: "list.bullet")
                    .font(OtoTheme.buttonFont)
                    .foregroundStyle(OtoTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: OtoTheme.minTouchTarget)
                    .background(OtoTheme.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            landscapeLyricsButton(isLandscape: isLandscape)
        }
        .padding(.horizontal, OtoTheme.spacing32)
        .padding(.bottom, OtoTheme.spacing16)
    }

    private func landscapeLyricsButton(isLandscape: Bool) -> some View {
        LyricsLayoutButton(
            title: isLandscape ? "Trở về bố cục dọc" : "Lời bài hát ngang",
            icon: isLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        ) {
            if !isLandscape { hidesWideLyrics = false }
            orientation.request(isLandscape ? .portrait : .landscape) { rotationDenied = true }
        }
    }

    private var wideLyricsToggle: some View {
        LyricsLayoutButton(
            title: hidesWideLyrics ? "Hiện lời bài hát" : "Ẩn lời bài hát",
            icon: hidesWideLyrics ? "sidebar.right" : "rectangle"
        ) {
            withAnimation(reduceMotion ? nil : OtoTheme.smoothSpring) { hidesWideLyrics.toggle() }
        }
    }
}
