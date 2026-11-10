import SwiftUI

/// Thanh trượt thời lượng bài hát chuẩn với số hiển thị monospaced và cử chỉ tua chính xác.
public struct OtoScrubber: View {
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    public let onSeek: (TimeInterval) -> Void

    @State private var isScrubbing: Bool = false
    @State private var scrubPosition: TimeInterval = 0

    public init(
        currentTime: TimeInterval,
        duration: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.onSeek = onSeek
    }

    public var body: some View {
        let displayedTime = isScrubbing ? scrubPosition : currentTime
        let remainingTime = max(0, duration - displayedTime)

        VStack(spacing: OtoTheme.spacing8) {
            progressTrack(displayedTime: displayedTime)

            HStack {
                Text(formatDuration(displayedTime))
                    .font(OtoTheme.timeFont)
                    .foregroundStyle(OtoTheme.secondaryText)

                Spacer()

                Text("-\(formatDuration(remainingTime))")
                    .font(OtoTheme.timeFont)
                    .foregroundStyle(OtoTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tiến trình phát: \(formatDuration(displayedTime)) trên \(formatDuration(duration))")
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = 10
            switch direction {
            case .increment:
                onSeek(min(duration, currentTime + step))
            case .decrement:
                onSeek(max(0, currentTime - step))
            @unknown default:
                break
            }
        }
    }

    private func progressTrack(displayedTime: TimeInterval) -> some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let progress = duration > 0 ? min(1, max(0, displayedTime / duration)) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(OtoTheme.secondaryText.opacity(0.24))
                    .frame(height: isScrubbing ? 6 : 4)

                Capsule()
                    .fill(OtoTheme.accent)
                    .frame(width: width * progress, height: isScrubbing ? 6 : 4)

                Circle()
                    .fill(OtoTheme.primaryText)
                    .frame(width: 12, height: 12)
                    .offset(x: min(max(0, width * progress - 6), width - 12))
                    .opacity(isScrubbing ? 1 : 0)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        scrubPosition = seekPosition(for: value.location.x, width: width)
                    }
                    .onEnded { value in
                        let target = seekPosition(for: value.location.x, width: width)
                        scrubPosition = target
                        onSeek(target)
                        isScrubbing = false
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    }
            )
        }
        .frame(height: OtoTheme.minTouchTarget)
        .accessibilityHidden(true)
    }

    private func seekPosition(for locationX: CGFloat, width: CGFloat) -> TimeInterval {
        guard duration > 0 else { return 0 }
        let fraction = min(1, max(0, locationX / max(1, width)))
        return duration * fraction
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN, !seconds.isInfinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        let hours = mins / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins % 60, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
