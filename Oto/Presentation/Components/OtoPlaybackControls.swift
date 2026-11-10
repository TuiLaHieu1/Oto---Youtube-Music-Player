import SwiftUI
import OtoCore

/// Cụm phím điều khiển phát nhạc tái sử dụng với haptic feedback và kích thước chạm tối thiểu 44pt.
public struct OtoPlaybackControls: View {
    public let isPlaying: Bool
    public let isShuffleEnabled: Bool
    public let repeatMode: RepeatMode
    public let playButtonSize: CGFloat
    public let onShuffle: () -> Void
    public let onPrevious: () -> Void
    public let onTogglePlayPause: () -> Void
    public let onNext: () -> Void
    public let onRepeat: () -> Void

    public init(
        isPlaying: Bool,
        isShuffleEnabled: Bool = false,
        repeatMode: RepeatMode = .off,
        playButtonSize: CGFloat = 64,
        onShuffle: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onTogglePlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onRepeat: @escaping () -> Void
    ) {
        self.isPlaying = isPlaying
        self.isShuffleEnabled = isShuffleEnabled
        self.repeatMode = repeatMode
        self.playButtonSize = playButtonSize
        self.onShuffle = onShuffle
        self.onPrevious = onPrevious
        self.onTogglePlayPause = onTogglePlayPause
        self.onNext = onNext
        self.onRepeat = onRepeat
    }

    public var body: some View {
        HStack(spacing: OtoTheme.spacing24) {
            // Nút Shuffle
            Button {
                triggerLightHaptic()
                onShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 19))
                    .foregroundStyle(isShuffleEnabled ? OtoTheme.accent : OtoTheme.secondaryText)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShuffleEnabled ? "Tắt xáo trộn" : "Bật xáo trộn")

            // Nút Previous
            Button {
                triggerMediumHaptic()
                onPrevious()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(OtoTheme.primaryText)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bài trước")

            // Nút Play / Pause
            Button {
                triggerMediumHaptic()
                onTogglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(OtoTheme.accent)
                        .frame(width: playButtonSize, height: playButtonSize)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: playButtonSize * 0.40, weight: .bold))
                        .foregroundStyle(OtoTheme.onAccent)
                        .offset(x: isPlaying ? 0 : 2)
                }
                .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Tạm dừng" : "Phát")

            // Nút Next
            Button {
                triggerMediumHaptic()
                onNext()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(OtoTheme.primaryText)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bài tiếp theo")

            // Nút Repeat
            Button {
                triggerLightHaptic()
                onRepeat()
            } label: {
                Image(systemName: repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 19))
                    .foregroundStyle(repeatMode != .off ? OtoTheme.accent : OtoTheme.secondaryText)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(repeatAccessibilityLabel)
        }
    }

    private var repeatAccessibilityLabel: String {
        switch repeatMode {
        case .off:
            return "Bật lặp lại tất cả"
        case .all:
            return "Bật lặp lại một bài"
        case .one:
            return "Tắt lặp lại"
        }
    }

    private func triggerLightHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func triggerMediumHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
