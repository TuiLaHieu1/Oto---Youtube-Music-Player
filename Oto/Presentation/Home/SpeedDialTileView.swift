import SwiftUI
import OtoCore

/// Thẻ hiển thị trên lưới Speed Dial (Quay số nhanh 3x3) theo chuẩn YouTube Music.
public struct SpeedDialTileView: View {
    @Environment(\.displayScale) private var displayScale

    public let item: SpeedDialItem
    public let isCurrent: Bool
    public let size: CGFloat
    public let onSelect: () -> Void
    public let onTogglePin: () -> Void

    public init(
        item: SpeedDialItem,
        isCurrent: Bool,
        size: CGFloat,
        onSelect: @escaping () -> Void,
        onTogglePin: @escaping () -> Void
    ) {
        self.item = item
        self.isCurrent = isCurrent
        self.size = size
        self.onSelect = onSelect
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        Button {
            triggerHaptic()
            onSelect()
        } label: {
            ZStack(alignment: .bottomLeading) {
                artwork

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                tileLabels
                topBadges
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isCurrent ? OtoTheme.accent : OtoTheme.separator.opacity(0.4),
                        lineWidth: isCurrent ? 1.5 : 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTogglePin()
            } label: {
                Label(
                    item.isPinned ? "Bỏ ghim trong Oto" : "Ghim trong Oto",
                    systemImage: item.isPinned ? "pin.slash" : "pin"
                )
            }
        }
        .accessibilityLabel("\(item.title), \(item.subtitle)")
        .accessibilityHint(accessibilityHint)
    }

    private var tileLabels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(item.subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(8)
    }

    private var accessibilityHint: String {
        switch item.kind {
        case .song: "Phát bài hát"
        case .album, .playlist, .artist: "Mở trang chi tiết"
        }
    }

    private var topBadges: some View {
        VStack {
            HStack {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(OtoTheme.accent)
                        .padding(5)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .padding(6)
                }
                Spacer()
                if isCurrent {
                    Circle()
                        .fill(OtoTheme.accent)
                        .frame(width: 8, height: 8)
                        .padding(8)
                }
            }
            Spacer()
        }
    }

    private var artwork: some View {
        AsyncImage(url: OtoArtworkURL.forDisplay(item.artworkURL, points: size, scale: displayScale)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure, .empty:
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(OtoTheme.surface)
                    Image(systemName: item.kind == .song ? "music.note" : "square.stack")
                        .font(.system(size: 24))
                        .foregroundStyle(OtoTheme.secondaryText)
                }
            @unknown default:
                Color.clear
            }
        }
        .id(item.artworkURL)
        .frame(width: size, height: size)
        .clipped()
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

struct HomeShelfTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(OtoTheme.captionFont)
                .foregroundStyle(OtoTheme.secondaryText)
                .padding(.horizontal, OtoTheme.spacing16)
        }
        OtoSectionHeader(title: title)
    }
}

struct HomeTileShelf<Content: View>: View {
    let title: String
    let subtitle: String?
    let size: CGFloat
    let items: [SpeedDialItem]
    @ViewBuilder let tile: (SpeedDialItem) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: OtoTheme.spacing12) {
            HomeShelfTitle(title: title, subtitle: subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(size), spacing: 8),
                                      count: min(3, items.count)), spacing: 8) {
                    ForEach(items, content: tile)
                }
                .scrollTargetLayout()
                .padding(.horizontal, OtoTheme.spacing16)
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

struct HomeRecommendationsTail: View {
    var body: some View {
        Text("Chưa tải được thêm gợi ý")
            .font(OtoTheme.captionFont)
            .foregroundStyle(OtoTheme.secondaryText)
            .padding(.horizontal, OtoTheme.spacing16)
    }
}
