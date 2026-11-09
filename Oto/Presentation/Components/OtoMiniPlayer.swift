import SwiftUI
import OtoCore

/// Thanh MiniPlayer dùng chung theo phong cách Apple Music kết hợp Atelier Light × Spectrum Dark.
public struct OtoMiniPlayer: View {
    public let song: Song?
    public let isPlaying: Bool
    public let currentPosition: TimeInterval
    public let onTogglePlayPause: () -> Void
    public let onNext: () -> Void
    public let onExpand: () -> Void

    public init(
        song: Song?,
        isPlaying: Bool,
        currentPosition: TimeInterval,
        onTogglePlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onExpand: @escaping () -> Void
    ) {
        self.song = song
        self.isPlaying = isPlaying
        self.currentPosition = currentPosition
        self.onTogglePlayPause = onTogglePlayPause
        self.onNext = onNext
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Thanh tiến trình mỏng 2pt
            progressBar

            HStack(spacing: OtoTheme.spacing12) {
                // Artwork hoặc Icon Placeholder
                artworkThumbnail

                // Thông tin bài hát (Chạm để mở full player)
                songInfoView

                Spacer(minLength: OtoTheme.spacing8)

                // Các nút điều khiển mini
                controlsView
            }
            .padding(.horizontal, OtoTheme.spacing16)
            .padding(.vertical, 8)
        }
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                .fill(OtoTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                        .stroke(OtoTheme.separator, lineWidth: 0.5)
                )
                .shadow(color: OtoTheme.cardShadowColor.opacity(0.12), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, OtoTheme.spacing12)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Chạm vào thông tin bài hát để mở trình phát toàn màn hình")
    }

    // MARK: - Subviews

    private var progressBar: some View {
        GeometryReader { geo in
            let duration = song?.duration ?? 0
            let progress = duration > 0 ? min(1.0, currentPosition / duration) : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(OtoTheme.secondaryText.opacity(0.15))
                Rectangle()
                    .fill(OtoTheme.accent)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 2)
        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
    }

    private var artworkThumbnail: some View {
        Button(action: onExpand) {
            if let song = song {
                AsyncImage(url: song.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous)
                            .fill(OtoTheme.secondaryText.opacity(0.12))
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(OtoTheme.secondaryText)
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous)
                        .fill(OtoTheme.secondaryText.opacity(0.10))
                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundStyle(OtoTheme.secondaryText)
                }
                .frame(width: 42, height: 42)
            }
        }
        .buttonStyle(.plain)
    }

    private var songInfoView: some View {
        Button(action: onExpand) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song?.title ?? "Chưa phát bài nào")
                    .font(OtoTheme.cardTitleFont)
                    .lineLimit(1)
                    .foregroundStyle(OtoTheme.primaryText)

                Text(song?.artist ?? "Chọn một bài hát để bắt đầu")
                    .font(OtoTheme.captionFont)
                    .lineLimit(1)
                    .foregroundStyle(OtoTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var controlsView: some View {
        HStack(spacing: OtoTheme.spacing4) {
            // Play / Pause Button
            Button {
                triggerHaptic()
                onTogglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(song != nil ? OtoTheme.primaryText : OtoTheme.disabled)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }
            .buttonStyle(.plain)
            .disabled(song == nil)
            .accessibilityLabel(isPlaying ? "Tạm dừng" : "Phát")

            // Next Track Button
            Button {
                triggerHaptic()
                onNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(song != nil ? OtoTheme.primaryText : OtoTheme.disabled)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }
            .buttonStyle(.plain)
            .disabled(song == nil)
            .accessibilityLabel("Bài tiếp theo")
        }
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
