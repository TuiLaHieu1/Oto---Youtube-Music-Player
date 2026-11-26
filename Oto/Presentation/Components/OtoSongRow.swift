import SwiftUI
import UIKit
import OtoCore

/// Hàng bài hát chuẩn của Oto hiển thị ảnh thumbnail, tên bài hát, nghệ sĩ và hiệu ứng đang phát.
public struct OtoSongRow: View {
    @Environment(\.displayScale) private var displayScale

    public let song: Song
    public let isPlaying: Bool
    public let action: () -> Void
    public let playNext: (() -> Void)?
    public let addToQueue: (() -> Void)?
    public let addToPlaylist: (() -> Void)?

    public init(
        song: Song,
        isPlaying: Bool,
        playNext: (() -> Void)? = nil,
        addToQueue: (() -> Void)? = nil,
        addToPlaylist: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.song = song
        self.isPlaying = isPlaying
        self.playNext = playNext
        self.addToQueue = addToQueue
        self.addToPlaylist = addToPlaylist
        self.action = action
    }

    public var body: some View {
        HStack(spacing: OtoTheme.spacing12) {
            Button(action: action) {
                HStack(spacing: OtoTheme.spacing12) {
                    // Ảnh bìa thu nhỏ
                    OtoTrackArtwork(url: OtoArtworkURL.forDisplay(song.artworkURL, points: 44, scale: displayScale)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous)
                                .fill(OtoTheme.secondaryText.opacity(0.12))
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(OtoTheme.secondaryText)
                        }
                    }
                    .frame(width: 44, height: 44)
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

                    if song.duration > 0, !isPlaying {
                        Text(formatDuration(song.duration))
                            .font(OtoTheme.timeFont)
                            .foregroundStyle(OtoTheme.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(song.title), nghệ sĩ \(song.artist)")
            .accessibilityHint("Nhấn đúp để phát bài hát này")

            Menu {
                Button("Phát bài hát", systemImage: "play.fill", action: action)
                if let playNext {
                    Button("Phát tiếp theo", systemImage: "text.line.first.and.arrowtriangle.forward", action: playNext)
                }
                if let addToQueue {
                    Button("Thêm vào hàng đợi", systemImage: "text.badge.plus", action: addToQueue)
                }
                if let addToPlaylist, !song.isLocal {
                    Button("Thêm vào playlist YouTube", systemImage: "text.badge.plus", action: addToPlaylist)
                }
                if !song.isLocal,
                   let url = URL(string: "https://music.youtube.com/watch?v=" + song.id) {
                    ShareLink(item: url) { Label("Chia sẻ bài hát", systemImage: "square.and.arrow.up") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OtoTheme.controlInactive)
                    .frame(width: OtoTheme.minTouchTarget, height: OtoTheme.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Thao tác với \(song.title)")
        }
        .padding(.horizontal, OtoTheme.spacing4)
        .padding(.vertical, OtoTheme.spacing4)
        .frame(minHeight: OtoTheme.minTouchTarget)
        .background(
            RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous)
                .fill(isPlaying ? OtoTheme.accentSurface : Color.clear)
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}

struct OtoTrackArtwork<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder
    @State private var localImage: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    var body: some View {
        if let url, url.isFileURL {
            Group {
                if let image = self.localImage {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    self.placeholder()
                }
            }
            .task(id: url) {
                self.localImage = UIImage(contentsOfFile: url.path)
            }
        } else {
            AsyncImage(url: self.url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                self.placeholder()
            }
        }
    }
}
