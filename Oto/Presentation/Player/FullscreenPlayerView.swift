import SwiftUI
import OtoCore

/// Màn hình phát nhạc toàn màn hình (Fullscreen Player) giao thoa Atelier Light × Spectrum Dark.
public struct FullscreenPlayerView: View {
    @Bindable var playerVM: PlayerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lyricsVM = LyricsViewModel()

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                AmbientBackgroundView(artworkURL: playerVM.currentSong?.artworkURL, size: geo.size)
                if geo.size.width >= 760, geo.size.height >= 540 {
                    widePlayerLayout(geo: geo)
                } else {
                    compactPlayerLayout(geo: geo)
                }
            }
        }
        .onChange(of: playerVM.currentSong) { _, newSong in
            if let song = newSong {
                lyricsVM.loadLyrics(for: song)
            }
        }
        .onChange(of: playerVM.currentPosition) { _, pos in
            lyricsVM.updatePosition(pos)
        }
        .onAppear {
            if let song = playerVM.currentSong {
                lyricsVM.loadLyrics(for: song)
            }
        }
        .sheet(isPresented: $playerVM.showQueue) {
            QueueView(playerVM: playerVM)
        }
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 80 && abs(value.translation.width) < 100 {
                    withAnimation(OtoTheme.smoothSpring) {
                        playerVM.isExpanded = false
                    }
                }
            }
        )
    }

    private func compactPlayerLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            FullscreenHeaderBar(isExpanded: $playerVM.isExpanded)

            if playerVM.showLyrics {
                SyncedLyricsView(lyricsVM: lyricsVM) { seekTime in
                    playerVM.seek(to: seekTime)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                artworkView(geo: geo)
            }

            VStack(spacing: OtoTheme.spacing24) {
                trackMetadataView
                scrubberView
                transportControls
                bottomBar
            }
            .padding(.bottom, OtoTheme.spacing16)
        }
    }

    /// iPad và cửa sổ rộng giữ player bên trái, lời bên phải theo cùng geometry Light/Dark.
    private func widePlayerLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            FullscreenHeaderBar(isExpanded: $playerVM.isExpanded)

            HStack(alignment: .top, spacing: OtoTheme.spacing32) {
                VStack(spacing: OtoTheme.spacing24) {
                    artworkImage(size: min(geo.size.width * 0.34, geo.size.height * 0.46))
                    trackMetadataView
                    scrubberView
                    transportControls
                    bottomBar
                }
                .frame(maxWidth: 480, maxHeight: .infinity)

                SyncedLyricsView(lyricsVM: lyricsVM) { seekTime in
                    playerVM.seek(to: seekTime)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                        .fill(OtoTheme.surface.opacity(0.78))
                        .overlay(
                            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                                .stroke(OtoTheme.separator, lineWidth: 0.5)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous))
            }
            .padding(.horizontal, OtoTheme.spacing32)
            .padding(.bottom, OtoTheme.spacing24)
        }
    }
}

private extension FullscreenPlayerView {

    // MARK: - Artwork Component

    @ViewBuilder
    private func artworkView(geo: GeometryProxy) -> some View {
        Spacer()
        let artSize = max(0, min(geo.size.width - 64, 340))
        artworkImage(size: artSize)
        Spacer()
    }

    private func artworkImage(size: CGFloat) -> some View {
        AsyncImage(url: playerVM.currentSong?.artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                    .fill(OtoTheme.secondaryText.opacity(0.12))
                Image(systemName: "music.note")
                    .font(.system(size: 72))
                    .foregroundStyle(OtoTheme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                .stroke(OtoTheme.separator.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(playerVM.isPlaying ? 0.25 : 0.12), radius: 20, x: 0, y: 10)
        .scaleEffect(reduceMotion ? 1 : (playerVM.isPlaying ? 1.0 : 0.90))
        .animation(reduceMotion ? nil : OtoTheme.smoothSpring, value: playerVM.isPlaying)
        .accessibilityLabel("Ảnh bìa \(playerVM.currentSong?.title ?? "bài hát")")
    }

    // MARK: - Track Metadata

    private var trackMetadataView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playerVM.currentSong?.title ?? "Chưa phát")
                    .font(.system(.title2, design: .default, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(OtoTheme.primaryText)

                HStack(spacing: 6) {
                    Text(playerVM.currentSong?.artist ?? "Oto Music")
                        .font(OtoTheme.subtitleFont)
                        .lineLimit(1)
                        .foregroundStyle(OtoTheme.secondaryText)

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

    // MARK: - Scrubber

    private var scrubberView: some View {
        OtoScrubber(
            currentTime: playerVM.currentPosition,
            duration: playerVM.currentSong?.duration ?? 0,
            onSeek: { seekTime in
                playerVM.seek(to: seekTime)
            }
        )
        .padding(.horizontal, OtoTheme.spacing32)
    }

    // MARK: - Controls

    private var transportControls: some View {
        OtoPlaybackControls(
            isPlaying: playerVM.isPlaying,
            isShuffleEnabled: playerVM.isShuffleEnabled,
            isRepeatEnabled: playerVM.repeatMode != .off,
            playButtonSize: 64,
            onShuffle: { playerVM.toggleShuffle() },
            onPrevious: { playerVM.previous() },
            onTogglePlayPause: { playerVM.togglePlayPause() },
            onNext: { playerVM.next() },
            onRepeat: { playerVM.toggleRepeat() }
        )
        .padding(.vertical, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 48) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(OtoTheme.smoothSpring) {
                    playerVM.showLyrics.toggle()
                }
            } label: {
                Image(systemName: playerVM.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 20))
                    .foregroundStyle(playerVM.showLyrics ? OtoTheme.accent : OtoTheme.secondaryText)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                playerVM.showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20))
                    .foregroundStyle(OtoTheme.secondaryText)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }
        }
        .padding(.bottom, OtoTheme.spacing16)
    }
}

// MARK: - Helper Views

private struct AmbientBackgroundView: View {
    let artworkURL: URL?
    let size: CGSize

    var body: some View {
        ZStack {
            // Nền dự phòng bảo đảm khả năng đọc tuyệt đối theo theme
            OtoTheme.background.ignoresSafeArea()

            if let artworkURL {
                AsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .blur(radius: 60)
                        .opacity(0.35)
                } placeholder: {
                    Color.clear
                }
                .ignoresSafeArea()
            }
        }
    }
}

private struct FullscreenHeaderBar: View {
    @Binding var isExpanded: Bool

    var body: some View {
        HStack {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(OtoTheme.smoothSpring) {
                    isExpanded = false
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(OtoTheme.secondaryText)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
                    .contentShape(Rectangle())
            }

            Spacer()

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(OtoTheme.smoothSpring) {
                    isExpanded = false
                }
            } label: {
                Capsule()
                    .fill(OtoTheme.secondaryText.opacity(0.35))
                    .frame(width: 36, height: 5)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Spacer()
            Color.clear.frame(width: OtoTheme.minTouchTarget, height: OtoTheme.minTouchTarget)
        }
        .padding(.horizontal, OtoTheme.spacing16)
        .padding(.top, OtoTheme.spacing8)
    }
}
