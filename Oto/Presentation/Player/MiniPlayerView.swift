import SwiftUI
import OtoCore

/// Thanh MiniPlayer nổi đặc trưng phong cách Apple Music.
public struct MiniPlayerView: View {
    @Bindable var playerVM: PlayerViewModel

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        if let song = playerVM.currentSong {
            VStack(spacing: 0) {
                // Thanh tiến trình mỏng ở đỉnh
                GeometryReader { geo in
                    let progress = song.duration > 0 ? min(1.0, playerVM.currentPosition / song.duration) : 0
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: max(0, geo.size.width * progress))
                    }
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    // Artwork Thumbnail
                    AsyncImage(url: song.artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                    // Song Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Text(song.artist)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                playerVM.togglePlayPause()
                            }
                        } label: {
                            Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                playerVM.next()
                            }
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            )
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    playerVM.isExpanded = true
                }
            }
        }
    }
}
