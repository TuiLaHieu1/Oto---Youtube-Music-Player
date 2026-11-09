import SwiftUI
import OtoCore

/// Hàng bài hát chuẩn của Oto hiển thị ảnh thumbnail, tên bài hát, nghệ sĩ và hiệu ứng đang phát.
public struct OtoSongRow: View {
    public let song: Song
    public let isPlaying: Bool
    public let action: () -> Void

    public init(song: Song, isPlaying: Bool, action: @escaping () -> Void) {
        self.song = song
        self.isPlaying = isPlaying
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: OtoTheme.spacing12) {
                // Ảnh bìa thu nhỏ
                AsyncImage(url: song.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous)
                            .fill(OtoTheme.secondaryText.opacity(0.12))
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundStyle(OtoTheme.secondaryText)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous))

                // Thông tin bài hát
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(OtoTheme.rowTitleFont)
                        .foregroundStyle(isPlaying ? OtoTheme.accent : OtoTheme.primaryText)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(OtoTheme.subtitleFont)
                        .foregroundStyle(OtoTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: OtoTheme.spacing8)

                // Biểu đồ sóng âm khi đang phát
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(OtoTheme.accent)
                        .accessibilityLabel("Đang phát")
                }
            }
            .padding(.horizontal, OtoTheme.spacing12)
            .padding(.vertical, 8)
            .frame(minHeight: OtoTheme.minTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                    .fill(isPlaying ? OtoTheme.accentSurface : OtoTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                            .stroke(isPlaying ? OtoTheme.accent.opacity(0.3) : OtoTheme.separator, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title), nghệ sĩ \(song.artist)")
        .accessibilityHint("Nhấn đúp để phát bài hát này")
    }
}
