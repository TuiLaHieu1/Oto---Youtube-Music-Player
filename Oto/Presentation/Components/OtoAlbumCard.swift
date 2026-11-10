import SwiftUI
import OtoCore

/// Thẻ hiển thị bài hát/album theo dạng khối vuông chuẩn Atelier Light × Spectrum Dark.
public struct OtoAlbumCard: View {
    public let song: Song
    public let isPlaying: Bool
    public let size: CGFloat
    public let action: () -> Void

    public init(
        song: Song,
        isPlaying: Bool,
        size: CGFloat = 144,
        action: @escaping () -> Void
    ) {
        self.song = song
        self.isPlaying = isPlaying
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
                // Artwork Container
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: song.artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: OtoTheme.artworkRadius, style: .continuous)
                                .fill(OtoTheme.secondaryText.opacity(0.12))
                            Image(systemName: "music.note")
                                .font(.system(size: 28))
                                .foregroundStyle(OtoTheme.secondaryText)
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: OtoTheme.artworkRadius, style: .continuous))

                    if isPlaying {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(OtoTheme.surface)
                            .padding(6)
                            .background(OtoTheme.accent)
                            .clipShape(Circle())
                            .padding(8)
                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                }

                // Metadata
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(OtoTheme.cardTitleFont)
                        .foregroundStyle(isPlaying ? OtoTheme.accent : OtoTheme.primaryText)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(OtoTheme.captionFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(width: size, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title), nghệ sĩ \(song.artist)")
        .accessibilityHint("Nhấn đúp để phát bài hát này")
    }
}
