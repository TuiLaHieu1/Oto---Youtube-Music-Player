import SwiftUI
import OtoCore

/// Thẻ hiển thị trên lưới Speed Dial (Quay số nhanh 3x3) theo chuẩn YouTube Music.
public struct SpeedDialTileView: View {
    public let item: SpeedDialItem
    public let isCurrent: Bool
    public let size: CGFloat
    public let onPlay: () -> Void
    public let onTogglePin: () -> Void

    public init(
        item: SpeedDialItem,
        isCurrent: Bool,
        size: CGFloat,
        onPlay: @escaping () -> Void,
        onTogglePin: @escaping () -> Void
    ) {
        self.item = item
        self.isCurrent = isCurrent
        self.size = size
        self.onPlay = onPlay
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        Button {
            triggerHaptic()
            onPlay()
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
                    item.isPinned ? "Bỏ ghim khỏi Speed dial" : "Ghim vào Speed dial",
                    systemImage: item.isPinned ? "pin.slash" : "pin"
                )
            }
        }
        .accessibilityLabel("\(item.title), \(item.subtitle)")
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
        AsyncImage(url: item.artworkURL) { phase in
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
