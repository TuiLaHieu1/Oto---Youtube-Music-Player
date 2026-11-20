import SwiftUI
import OtoCore

/// Màn hình hiển thị lời bài hát đồng bộ thời gian thực chuẩn Atelier × Spectrum.
public struct SyncedLyricsView: View {
    @Bindable var lyricsVM: LyricsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onSeek: (TimeInterval) -> Void

    public init(lyricsVM: LyricsViewModel, onSeek: @escaping (TimeInterval) -> Void) {
        self.lyricsVM = lyricsVM
        self.onSeek = onSeek
    }

    public var body: some View {
        Group {
            switch lyricsVM.currentDocument.type {
            case .synced:
                syncedView
            case .plain:
                plainView
            case .instrumental:
                instrumentalView
            case .none:
                emptyView
            }
        }
    }

    @ViewBuilder
    private var syncedView: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                syncedScrollArea(proxy: proxy, edgeSpace: geometry.size.height * 0.5)
            }
        }
    }

    private func syncedScrollArea(proxy: ScrollViewProxy, edgeSpace: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OtoTheme.spacing24) {
                    let indexedLines = Array(lyricsVM.currentDocument.lines.enumerated())
                    ForEach(indexedLines, id: \.element.id) { index, line in
                        syncedLine(line, at: index)
                    }

                    HStack {
                        Text("Nguồn: \(lyricsVM.currentDocument.source)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(OtoTheme.tertiaryText)
                        Spacer()
                    }
                    .padding(.top, OtoTheme.spacing32)
                }
                .padding(.horizontal, OtoTheme.spacing24)
                .padding(.vertical, edgeSpace)
            }
            .simultaneousGesture(
                DragGesture()
                    .onChanged { _ in lyricsVM.beginManualScroll() }
                    .onEnded { _ in lyricsVM.finishManualScroll() }
            )

            if lyricsVM.userIsScrolling, lyricsVM.activeLineIndex != nil {
                Button {
                    lyricsVM.resumeAutoScroll()
                } label: {
                    Label("Về dòng hiện tại", systemImage: "location.fill")
                        .font(OtoTheme.buttonFont)
                        .padding(.horizontal, OtoTheme.spacing16)
                        .frame(minHeight: OtoTheme.minTouchTarget)
                        .background(OtoTheme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, OtoTheme.spacing16)
            }
        }
        .onAppear {
            guard let index = lyricsVM.activeLineIndex, !lyricsVM.userIsScrolling else { return }
            proxy.scrollTo(index, anchor: .center)
        }
        .onChange(of: lyricsVM.activeLineIndex) { _, newIndex in
            guard let newIndex = newIndex, !lyricsVM.userIsScrolling else { return }
            scroll(to: newIndex, using: proxy)
        }
        .onChange(of: lyricsVM.userIsScrolling) { wasScrolling, isScrolling in
            guard wasScrolling, !isScrolling, let index = lyricsVM.activeLineIndex else { return }
            scroll(to: index, using: proxy)
        }
    }

    private func scroll(to index: Int, using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(index, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.32)) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private var plainView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtoTheme.spacing16) {
                Text(lyricsVM.currentDocument.plainLyrics ?? "")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .lineSpacing(OtoTheme.spacing8)

                Text("Nguồn: \(lyricsVM.currentDocument.source) (Lời tĩnh)")
                    .font(.system(size: 13))
                    .foregroundStyle(OtoTheme.tertiaryText)
                    .padding(.top, OtoTheme.spacing24)
            }
            .padding(OtoTheme.spacing24)
            .padding(.bottom, 120)
        }
    }

    @ViewBuilder
    private var instrumentalView: some View {
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
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: OtoTheme.spacing12) {
            Spacer()
            if lyricsVM.isLoading {
                ProgressView()
                Text("Đang tải lời bài hát")
                    .foregroundStyle(OtoTheme.secondaryText)
            } else {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 44))
                    .foregroundStyle(OtoTheme.tertiaryText)
                Text("Chưa có lời cho bài hát này")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(OtoTheme.secondaryText)
            }
            Spacer()
        }
    }

    private func syncedLine(_ line: LyricsLine, at index: Int) -> some View {
        let isCurrent = lyricsVM.activeLineIndex == index
        let isUpcoming = index > (lyricsVM.activeLineIndex ?? -1)
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onSeek(line.startTime)
        } label: {
            Text(line.text)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(
                    isCurrent ? OtoTheme.primaryText : OtoTheme.secondaryText.opacity(isUpcoming ? 0.74 : 0.90)
                )
                .scaleEffect(isCurrent ? 1.06 : 1, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isCurrent)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .id(index)
    }
}
