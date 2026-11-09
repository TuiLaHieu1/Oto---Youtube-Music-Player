import SwiftUI
import OtoCore

/// Thanh MiniPlayer nổi đặc trưng phong cách Apple Music kết hợp hệ màu Atelier × Spectrum.
public struct MiniPlayerView: View {
    @Bindable var playerVM: PlayerViewModel

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        if let song = playerVM.currentSong {
            VStack(spacing: 0) {
                // Thanh tiến trình mỏng ở đỉnh dùng màu Accent theo theme
                GeometryReader { geo in
                    let progress = song.duration > 0 ? min(1.0, playerVM.currentPosition / song.duration) : 0
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(OtoTheme.secondaryText.opacity(0.2))
                        Rectangle()
                            .fill(OtoTheme.accent)
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
                            RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous)
                                .fill(OtoTheme.secondaryText.opacity(0.15))
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(OtoTheme.secondaryText)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)

                    // Song Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(OtoTheme.primaryText)

                        Text(song.artist)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundStyle(OtoTheme.secondaryText)
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 16) {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            withAnimation(OtoTheme.standardSpring) {
                                playerVM.togglePlayPause()
                            }
                        } label: {
                            Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(OtoTheme.primaryText)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
                        .accessibilityLabel(playerVM.isPlaying ? "Tạm dừng" : "Phát")

                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(OtoTheme.standardSpring) {
                                playerVM.next()
                            }
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(OtoTheme.primaryText)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
                        .accessibilityLabel("Bài tiếp theo")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                    .fill(OtoTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                            .stroke(OtoTheme.separator, lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(OtoTheme.smoothSpring) {
                    playerVM.isExpanded = true
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityHint("Chạm vào thông tin bài hát để mở trình phát toàn màn hình")
        }
    }
}
