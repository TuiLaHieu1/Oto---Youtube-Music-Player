import SwiftUI
import UIKit
import ImageIO
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
                    OtoTrackArtwork(url: OtoArtworkURL.forDisplay(song.artworkURL, points: 44, scale: displayScale), points: 44) {
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
    let points: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var localImage: UIImage?

    init(url: URL?, points: CGFloat = 384, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.points = points
        self.placeholder = placeholder
    }

    private var pixelSize: Int { min(768, max(1, Int((self.points * self.displayScale).rounded(.up)))) }

    var body: some View {
        if let url, url.isFileURL {
            Group {
                if let image = self.localImage {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    self.placeholder()
                }
            }
            .task(id: "\(url.absoluteString)-\(self.pixelSize)") {
                self.localImage = nil
                let image = await LocalArtworkCache.shared.image(url: url, pixels: self.pixelSize)
                guard !Task.isCancelled else { return }
                self.localImage = image
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

/// Ảnh local được giải mã theo kích thước hiển thị, dùng chung bộ đệm có giới hạn.
@MainActor
private final class LocalArtworkCache {
    static let shared = LocalArtworkCache()
    private let images = NSCache<NSString, UIImage>()
    private let decoder = LocalArtworkDecoder()
    private var pending: [String: Task<CGImage?, Never>] = [:]
    private var revision = 0
    private var memoryTask: Task<Void, Never>?

    private init() {
        self.images.totalCostLimit = 20 * 1024 * 1024
        self.images.countLimit = 100
        self.memoryTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                guard !Task.isCancelled else { return }
                self?.revision += 1
                self?.images.removeAllObjects()
            }
        }
    }

    deinit { self.memoryTask?.cancel() }

    func image(url: URL, pixels: Int) async -> UIImage? {
        let key = "\(url.absoluteString)-\(pixels)"
        if let image = self.images.object(forKey: key as NSString) { return image }
        let revision = self.revision
        let task: Task<CGImage?, Never>
        if let existing = self.pending[key] {
            task = existing
        } else {
            task = Task { [decoder] in await decoder.thumbnail(url: url, pixels: pixels) }
            self.pending[key] = task
        }
        let thumbnail = await task.value
        self.pending[key] = nil
        guard let thumbnail else { return nil }
        let image = UIImage(cgImage: thumbnail)
        if self.revision == revision {
            self.images.setObject(image, forKey: key as NSString, cost: thumbnail.bytesPerRow * thumbnail.height)
        }
        return image
    }
}

private actor LocalArtworkDecoder {
    func thumbnail(url: URL, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
