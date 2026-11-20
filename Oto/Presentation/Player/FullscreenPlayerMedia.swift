import SwiftUI

struct PlayerMediaArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL?
    let size: CGFloat
    let showsVideo: Bool
    let isPlaying: Bool
    let onSwitchMode: (() -> Void)?

    var body: some View {
        PlayerCoverImage(url: url)
        .frame(width: size, height: showsVideo ? size * 9 / 16 : size)
        .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius)
                .strokeBorder(OtoTheme.separator.opacity(0.4), lineWidth: 0.5)
        }
        .anchorPreference(key: PlayerVideoAnchor.self, value: .bounds) { showsVideo ? $0 : nil }
        .overlay(alignment: .bottomTrailing) {
            if let onSwitchMode {
                Button(action: onSwitchMode) {
                    Color.clear
                        .contentShape(Rectangle())
                        .overlay(alignment: .topTrailing) {
                            if !showsVideo {
                                Image(systemName: "play.rectangle")
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.black.opacity(0.65), in: Capsule())
                                    .padding(6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsVideo ? "Hiện ảnh bìa" : "Xem video")
            }
        }
        .shadow(color: .black.opacity(isPlaying ? 0.25 : 0.12), radius: 20, x: 0, y: 10)
        .scaleEffect(showsVideo || reduceMotion || isPlaying ? 1 : 0.90)
        .animation(showsVideo || reduceMotion ? nil : OtoTheme.smoothSpring, value: isPlaying)
    }
}

private struct PlayerCoverImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            OtoTheme.surface.overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 72))
                    .foregroundStyle(OtoTheme.secondaryText)
            }
        }
        .id(url)
    }
}

private struct PlayerVideoSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL?
    @State private var ready: Bool?

    var body: some View {
        ZStack(alignment: .bottom) {
            if ready != false {
                PlayerWebViewContainer { result in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { ready = result }
                }
                    .accessibilityHidden(true)
            }
            if ready != true {
                PlayerCoverImage(url: url)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                if ready == false {
                    Text("Chưa hiển thị được video")
                        .font(OtoTheme.captionFont)
                        .padding(OtoTheme.spacing8)
                        .foregroundStyle(OtoTheme.primaryText)
                        .background(OtoTheme.background, in: Capsule())
                        .padding(OtoTheme.spacing8)
                }
            }
        }
    }
}

struct PlayerMediaModePicker: View {
    let showsVideo: Bool
    let selectVideo: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            option("Bài hát", selectsVideo: false)
            option("Video", selectsVideo: true)
        }
        .padding(2)
        .background(OtoTheme.backgroundSecondary, in: Capsule())
    }

    private func option(_ title: LocalizedStringKey, selectsVideo: Bool) -> some View {
        let selected = showsVideo == selectsVideo
        return Button { selectVideo(selectsVideo) } label: {
            Text(title)
                .font(OtoTheme.captionFont.weight(.semibold))
                .padding(.horizontal, OtoTheme.spacing8)
                .frame(minHeight: OtoTheme.minTouchTarget)
                .foregroundStyle(selected ? OtoTheme.onAccent : OtoTheme.secondaryText)
                .background(selected ? OtoTheme.accent : Color.clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PlayerVideoAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

/// Một mặt video được giữ nguyên khi đổi kích thước để WebView không phải gắn lại.
struct PlayerVideoOverlay: View {
    let anchor: Anchor<CGRect>
    let url: URL?
    let expanded: Bool
    let onResize: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let inline = geometry[anchor]
            let fullWidth = min(geometry.size.width, geometry.size.height * 16 / 9)
            let frame = expanded
                ? CGRect(x: (geometry.size.width - fullWidth) / 2, y: (geometry.size.height - fullWidth * 9 / 16) / 2,
                         width: fullWidth, height: fullWidth * 9 / 16)
                : inline
            let scale = frame.width / max(fullWidth, 1)
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)
                PlayerVideoSurface(url: url)
                    .frame(width: fullWidth, height: fullWidth * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : OtoTheme.cardRadius / max(scale, 0.1)))
                    .scaleEffect(scale)
                    .allowsHitTesting(false)
                    .position(x: frame.midX, y: frame.midY)
                VideoSizeButton(expanded: expanded, action: onResize)
                    .position(x: frame.maxX - 26, y: frame.maxY - 26)
            }
        }
        .accessibilityAction(.escape) { if expanded { onResize() } }
    }
}

private struct VideoSizeButton: View {
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .frame(width: OtoTheme.minTouchTarget, height: OtoTheme.minTouchTarget)
                .foregroundStyle(.white)
                .background(.black.opacity(0.7), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Thu video" : "Mở video toàn màn hình")
    }
}
