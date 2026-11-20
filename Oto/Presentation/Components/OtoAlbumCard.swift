import SwiftUI
import OtoCore

enum OtoArtworkURL {
    static func forDisplay(_ url: URL?, points: CGFloat, scale: CGFloat) -> URL? {
        guard let url else { return nil }
        let pixels = max(1, points * scale)
        let size = [160, 256, 384, 512, 800].first { CGFloat($0) >= pixels } ?? 800
        let source = url.absoluteString
        let resized = source
            .replacingOccurrences(of: "=w800-h800-l90-rj", with: "=w\(size)-h\(size)-l90-rj")
            .replacingOccurrences(of: "=s800-c", with: "=s\(size)-c")
        return resized == source ? url : URL(string: resized) ?? url
    }
}

/// Thẻ hiển thị bài hát/album theo dạng khối vuông chuẩn Atelier Light × Spectrum Dark.
public struct OtoAlbumCard: View {
    @Environment(\.displayScale) private var displayScale

    public let title: String
    public let subtitle: String
    public let artworkURL: URL?
    public let isPlaying: Bool
    public let size: CGFloat
    public let action: (() -> Void)?

    public init(
        title: String,
        subtitle: String,
        artworkURL: URL? = nil,
        isPlaying: Bool = false,
        size: CGFloat = 144,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.isPlaying = isPlaying
        self.size = size
        self.action = action
    }

    public init(
        item: SpeedDialItem,
        isPlaying: Bool = false,
        size: CGFloat = 144,
        action: (() -> Void)? = nil
    ) {
        self.title = item.title
        self.subtitle = item.subtitle
        self.artworkURL = item.artworkURL
        self.isPlaying = isPlaying
        self.size = size
        self.action = action
    }

    public init(
        song: Song,
        isPlaying: Bool = false,
        size: CGFloat = 144,
        action: (() -> Void)? = nil
    ) {
        self.title = song.title
        self.subtitle = song.artist
        self.artworkURL = song.artworkURL
        self.isPlaying = isPlaying
        self.size = size
        self.action = action
    }

    public init(
        song: Song,
        isPlaying: Bool,
        size: CGFloat = 144,
        action: @escaping () -> Void
    ) {
        self.title = song.title
        self.subtitle = song.artist
        self.artworkURL = song.artworkURL
        self.isPlaying = isPlaying
        self.size = size
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) {
                cardContent
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(subtitle)")
            .accessibilityHint("Nhấn đúp để phát")
        } else {
            cardContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title), \(subtitle)")
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
            // Artwork Container
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: OtoArtworkURL.forDisplay(artworkURL, points: size, scale: displayScale)) { image in
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
                Text(title)
                    .font(OtoTheme.cardTitleFont)
                    .foregroundStyle(isPlaying ? OtoTheme.accent : OtoTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(OtoTheme.captionFont)
                    .foregroundStyle(OtoTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
        }
    }
}
