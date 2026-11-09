import SwiftUI
import OtoCore

/// Màn hình hiển thị lời bài hát đồng bộ thời gian thực chuẩn Atelier × Spectrum.
public struct SyncedLyricsView: View {
    @Bindable var lyricsVM: LyricsViewModel
    var onSeek: (TimeInterval) -> Void

    public init(lyricsVM: LyricsViewModel, onSeek: @escaping (TimeInterval) -> Void) {
        self.lyricsVM = lyricsVM
        self.onSeek = onSeek
    }

    public var body: some View {
        Group {
            switch lyricsVM.currentDocument.type {
            case .synced:
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: OtoTheme.spacing24) {
                            let indexedLines = Array(lyricsVM.currentDocument.lines.enumerated())
                            ForEach(indexedLines, id: \.element.id) { index, line in
                                let isCurrent = lyricsVM.activeLineIndex == index

                                Text(line.text)
                                    .font(.system(size: isCurrent ? 28 : 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        isCurrent ? OtoTheme.primaryText : OtoTheme.secondaryText.opacity(0.35)
                                    )
                                    .blur(radius: isCurrent ? 0 : 0.4)
                                    .scaleEffect(isCurrent ? 1.05 : 1.0, anchor: .leading)
                                    .animation(OtoTheme.smoothSpring, value: isCurrent)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        onSeek(line.startTime)
                                    }
                            }

                            // Nguồn lời và ghi nhận bản quyền
                            HStack {
                                Text("Nguồn: \(lyricsVM.currentDocument.source)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(OtoTheme.tertiaryText)
                                Spacer()
                            }
                            .padding(.top, OtoTheme.spacing32)
                            .padding(.bottom, 60)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, OtoTheme.spacing32)
                    }
                    .simultaneousGesture(
                        DragGesture().onChanged { _ in
                            lyricsVM.userDidScroll()
                        }
                    )
                    .onChange(of: lyricsVM.activeLineIndex) { _, newIndex in
                        guard let newIndex = newIndex, !lyricsVM.userIsScrolling else { return }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

            case .plain:
                ScrollView {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing16) {
                        Text(lyricsVM.currentDocument.plainLyrics ?? "")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(OtoTheme.primaryText)
                            .lineSpacing(8)

                        Text("Nguồn: \(lyricsVM.currentDocument.source) (Lời tĩnh)")
                            .font(.system(size: 13))
                            .foregroundStyle(OtoTheme.tertiaryText)
                            .padding(.top, OtoTheme.spacing24)
                    }
                    .padding(28)
                }

            case .instrumental:
                VStack(spacing: OtoTheme.spacing16) {
                    Spacer()
                    Image(systemName: "guitars.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(OtoTheme.tertiaryText)
                    Text("Bài hát không lời (Instrumental)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OtoTheme.secondaryText)
                    Spacer()
                }

            case .none:
                VStack(spacing: OtoTheme.spacing12) {
                    Spacer()
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 44))
                        .foregroundStyle(OtoTheme.tertiaryText)
                    Text("Chưa có lời cho bài hát này")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(OtoTheme.secondaryText)
                    Spacer()
                }
            }
        }
    }
}
