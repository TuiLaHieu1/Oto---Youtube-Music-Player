import SwiftUI
import OtoCore

/// Màn hình phát nhạc toàn màn hình (Fullscreen Now Playing) chuẩn Apple Music.
public struct FullscreenPlayerView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var lyricsVM = LyricsViewModel()
    @State private var isScrubbing: Bool = false
    @State private var scrubPosition: TimeInterval = 0

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                AmbientBackgroundView(artworkURL: playerVM.currentSong?.artworkURL, size: geo.size)

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

                    VStack(spacing: 20) {
                        trackMetadataView
                        scrubberView
                        transportControls
                        bottomBar
                    }
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        playerVM.isExpanded = false
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func artworkView(geo: GeometryProxy) -> some View {
        Spacer()
        AsyncImage(url: playerVM.currentSong?.artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: max(0, min(geo.size.width - 64, 340)),
            height: max(0, min(geo.size.width - 64, 340))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 12)
        .scaleEffect(playerVM.isPlaying ? 1.0 : 0.88)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: playerVM.isPlaying)
        Spacer()
    }

    private var trackMetadataView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playerVM.currentSong?.title ?? "Chưa phát")
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(playerVM.currentSong?.artist ?? "Oto Music")
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var scrubberView: some View {
        VStack(spacing: 8) {
            let duration = playerVM.currentSong?.duration ?? 0
            let displayedTime = isScrubbing ? scrubPosition : playerVM.currentPosition
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(1.0, duration),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        playerVM.seek(to: scrubPosition)
                    } else {
                        scrubPosition = playerVM.currentPosition
                    }
                }
            )
            .tint(.primary)

            HStack {
                Text(formatTime(displayedTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-\(formatTime(max(0, duration - displayedTime)))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
    }

    private var transportControls: some View {
        HStack(spacing: 36) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                playerVM.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20))
                    .foregroundStyle(playerVM.isShuffleEnabled ? Color.accentColor : Color.secondary)
            }

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                playerVM.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
            }

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                playerVM.togglePlayPause()
            } label: {
                Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.primary)
            }

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                playerVM.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
            }

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                playerVM.toggleRepeat()
            } label: {
                Image(systemName: repeatIconName)
                    .font(.system(size: 20))
                    .foregroundStyle(playerVM.repeatMode != .off ? Color.accentColor : Color.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 48) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    playerVM.showLyrics.toggle()
                }
            } label: {
                Image(systemName: playerVM.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 20))
                    .foregroundStyle(playerVM.showLyrics ? Color.accentColor : Color.secondary)
            }

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                playerVM.showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.bottom, 24)
    }

    private var repeatIconName: String {
        switch playerVM.repeatMode {
        case .off, .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Helper Views

private struct AmbientBackgroundView: View {
    let artworkURL: URL?
    let size: CGSize

    var body: some View {
        if let artworkURL {
            AsyncImage(url: artworkURL) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .blur(radius: 65)
                    .overlay(Color.black.opacity(0.6))
            } placeholder: {
                Color.black
            }
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.35), Color.black.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded = false
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .contentShape(Rectangle())
            }

            Spacer()

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded = false
                }
            } label: {
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
