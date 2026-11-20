import SwiftUI
import OtoCore

/// Thanh MiniPlayer dùng chung theo phong cách Apple Music kết hợp Atelier Light × Spectrum Dark.
public struct OtoMiniPlayer: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var horizontalDrag: CGFloat = 0
    @State private var swipeDirection: MiniPlayerSwipeAction = .next

    public let song: Song?
    public let queueItemID: UUID?
    public let isPlaying: Bool
    public let currentPosition: TimeInterval
    public let duration: TimeInterval
    public let onTogglePlayPause: () -> Void
    public let onPrevious: () -> Void
    public let onNext: () -> Void
    public let onExpand: () -> Void

    public init(
        song: Song?,
        queueItemID: UUID? = nil,
        isPlaying: Bool,
        currentPosition: TimeInterval,
        duration: TimeInterval = 0,
        onTogglePlayPause: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onExpand: @escaping () -> Void
    ) {
        self.song = song
        self.queueItemID = queueItemID
        self.isPlaying = isPlaying
        self.currentPosition = currentPosition
        self.duration = duration
        self.onTogglePlayPause = onTogglePlayPause
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Thanh tiến trình mỏng 2pt
            progressBar

            HStack(spacing: OtoTheme.spacing12) {
                ZStack(alignment: .leading) {
                    Button(action: onExpand) {
                        HStack(spacing: OtoTheme.spacing12) {
                            artworkThumbnail
                            songInfoView
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(queueItemID)
                    .transition(songTransition)
                    .offset(x: reduceMotion ? 0 : horizontalDrag)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .clipped()
                .highPriorityGesture(swipeGesture)

                // Các nút điều khiển mini
                controlsView
            }
            .padding(.horizontal, OtoTheme.spacing16)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                .fill(OtoTheme.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                .stroke(OtoTheme.separator, lineWidth: 0.5)
        )
        .shadow(color: OtoTheme.cardShadowColor.opacity(0.12), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Chạm vào thông tin bài hát để mở trình phát toàn màn hình. Vuốt ngang để đổi bài.")
        .accessibilityAction(named: Text("Bài trước")) {
            performSwipe(.previous)
        }
        .accessibilityAction(named: Text("Bài tiếp theo")) {
            performSwipe(.next)
        }
    }

    private var songTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        switch swipeDirection {
        case .next:
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .previous:
            return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }

    /// Nội dung theo ngón tay khi kéo; các nút điều khiển đứng yên.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !reduceMotion, song != nil,
                      abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                horizontalDrag = max(-240, min(240, value.translation.width))
            }
            .onEnded { value in
                guard let action = MiniPlayerSwipePolicy.action(translation: value.translation) else {
                    withAnimation(.easeOut(duration: 0.18)) { horizontalDrag = 0 }
                    return
                }
                swipeDirection = action
                withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.86)) {
                    horizontalDrag = 0
                    performSwipe(action)
                }
            }
    }

    private func performSwipe(_ action: MiniPlayerSwipeAction) {
        guard song != nil else { return }
        triggerHaptic()
        switch action {
        case .previous:
            onPrevious()
        case .next:
            onNext()
        }
    }

    // MARK: - Subviews

    private var progressBar: some View {
        GeometryReader { geo in
            let totalDuration = duration > 0 ? duration : (song?.duration ?? 0)
            let progress = totalDuration > 0 ? min(1.0, currentPosition / totalDuration) : 0
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

    @ViewBuilder
    private var artworkThumbnail: some View {
        if let song = song {
            AsyncImage(url: OtoArtworkURL.forDisplay(song.artworkURL, points: 42, scale: displayScale)) { image in
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
            .id(song.artworkURL)
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

    private var songInfoView: some View {
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
