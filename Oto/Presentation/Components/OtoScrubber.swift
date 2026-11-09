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
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(1.0, duration),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onSeek(scrubPosition)
                    } else {
                        scrubPosition = currentTime
                    }
                }
            )
            .tint(OtoTheme.accent)

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
