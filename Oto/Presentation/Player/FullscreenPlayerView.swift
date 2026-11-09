import SwiftUI
import OtoCore

/// Màn hình phát nhạc toàn màn hình (Fullscreen Now Playing) chuẩn Apple Music.
public struct FullscreenPlayerView: View {
    @Bindable var playerVM: PlayerViewModel
    @State private var lyricsVM = LyricsViewModel()

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background Gradient
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.35),
                        Color.black.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Thanh gạt đóng sheet ở trên cùng
                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    if playerVM.showLyrics {
                        // Chế độ xem lời bài hát đồng bộ
                        SyncedLyricsView(lyricsVM: lyricsVM) { seekTime in
                            playerVM.seek(to: seekTime)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Chế độ đĩa nhạc (Artwork)
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

                    // Thông tin bài hát & Controls
                    VStack(spacing: 20) {
                        // Tên bài & Nghệ sĩ
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

                        // Thanh tua nhạc (Scrubber)
                        VStack(spacing: 8) {
                            let duration = playerVM.currentSong?.duration ?? 0
                            Slider(
                                value: Binding(
                                    get: { playerVM.currentPosition },
                                    set: { newPos in playerVM.seek(to: newPos) }
                                ),
                                in: 0...max(1.0, duration)
                            )
                            .tint(.primary)

                            HStack {
                                Text(formatTime(playerVM.currentPosition))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("-\(formatTime(max(0, duration - playerVM.currentPosition)))")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 32)

                        // Nút điều khiển phát (Transport controls)
                        HStack(spacing: 36) {
                            Button {
                                playerVM.toggleShuffle()
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(playerVM.isShuffleEnabled ? Color.accentColor : Color.secondary)
                            }

                            Button {
                                playerVM.previous()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.primary)
                            }

                            Button {
                                playerVM.togglePlayPause()
                            } label: {
                                Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.primary)
                            }

                            Button {
                                playerVM.next()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.primary)
                            }

                            Button {
                                playerVM.toggleRepeat()
                            } label: {
                                Image(systemName: repeatIconName)
                                    .font(.system(size: 20))
                                    .foregroundStyle(playerVM.repeatMode != .off ? Color.accentColor : Color.secondary)
                            }
                        }
                        .padding(.vertical, 8)

                        // Thanh công cụ phụ: Lời bài hát & Hàng đợi
                        HStack(spacing: 48) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    playerVM.showLyrics.toggle()
                                }
                            } label: {
                                Image(systemName: playerVM.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                                    .font(.system(size: 20))
                                    .foregroundStyle(playerVM.showLyrics ? Color.accentColor : Color.secondary)
                            }

                            Button {
                                playerVM.showQueue = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .padding(.bottom, 24)
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
