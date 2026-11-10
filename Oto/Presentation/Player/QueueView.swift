import SwiftUI
import OtoCore

/// Màn hình danh sách phát tiếp theo (Queue / Up Next) theo phong cách Atelier × Spectrum.
public struct QueueView: View {
    @Bindable var playerVM: PlayerViewModel

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                OtoTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OtoTheme.spacing24) {
                        // Section: Đang phát
                        if let currentSong = playerVM.currentSong {
                            VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
                                Text("Đang phát")
                                    .font(OtoTheme.sectionTitleFont)
                                    .foregroundStyle(OtoTheme.primaryText)
                                    .padding(.horizontal, OtoTheme.spacing16)

                                HStack(spacing: OtoTheme.spacing12) {
                                    artwork(for: currentSong)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(currentSong.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(OtoTheme.accent)
                                            .lineLimit(1)

                                        Text(currentSong.artist)
                                            .font(.system(size: 13))
                                            .foregroundStyle(OtoTheme.secondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, OtoTheme.spacing16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                                        .fill(OtoTheme.accentSurface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                                                .stroke(OtoTheme.accent.opacity(0.3), lineWidth: 0.5)
                                        )
                                )
                                .padding(.horizontal, OtoTheme.spacing16)
                            }

                            HStack(spacing: OtoTheme.spacing8) {
                                queueModeButton(
                                    title: playerVM.isShuffleEnabled ? "Đang trộn" : "Trộn tắt",
                                    active: playerVM.isShuffleEnabled,
                                    action: playerVM.toggleShuffle
                                )
                                queueModeButton(
                                    title: repeatTitle,
                                    active: playerVM.repeatMode != .off,
                                    action: playerVM.toggleRepeat
                                )
                            }
                            .padding(.horizontal, OtoTheme.spacing16)
                        }

                        // Section: Tiếp theo trong hàng đợi
                        VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
                            Text("Tiếp theo")
                                .font(OtoTheme.sectionTitleFont)
                                .foregroundStyle(OtoTheme.primaryText)
                                .padding(.horizontal, OtoTheme.spacing16)

                            let items = playerVM.queueManager.items
                            let currentIndex = playerVM.queueManager.currentIndex ?? 0
                            let upcomingIndices = Array(items.indices.filter { $0 > currentIndex })

                            if upcomingIndices.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("Không có bài hát tiếp theo")
                                        .font(.system(size: 14))
                                        .foregroundStyle(OtoTheme.secondaryText)
                                        .padding(.vertical, OtoTheme.spacing24)
                                    Spacer()
                                }
                            } else {
                                LazyVStack(spacing: OtoTheme.spacing8) {
                                    ForEach(upcomingIndices, id: \.self) { index in
                                        let item = items[index]
                                        Button {
                                            #if os(iOS)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            #endif
                                            playerVM.playQueueItem(at: index)
                                        } label: {
                                            HStack(spacing: OtoTheme.spacing12) {
                                                artwork(for: item.song)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.song.title)
                                                        .font(.system(size: 15, weight: .medium))
                                                        .foregroundStyle(OtoTheme.primaryText)
                                                        .lineLimit(1)

                                                    Text(item.song.artist)
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(OtoTheme.secondaryText)
                                                        .lineLimit(1)
                                                }

                                                Spacer()
                                            }
                                            .padding(.horizontal, OtoTheme.spacing16)
                                            .padding(.vertical, 10)
                                            .frame(minHeight: OtoTheme.minTouchTarget)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, OtoTheme.spacing16)
                            }
                        }

                        if playerVM.effectiveDuration > 0 {
                            OtoScrubber(
                                currentTime: playerVM.currentPosition,
                                duration: playerVM.effectiveDuration,
                                onSeek: playerVM.seek
                            )
                            .padding(.horizontal, OtoTheme.spacing16)
                        }
                    }
                    .padding(.top, OtoTheme.spacing16)
                    .padding(.bottom, OtoTheme.spacing32)
                }
            }
            .navigationTitle("Hàng đợi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        playerVM.showQueue = false
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OtoTheme.accent)
                }
            }
        }
    }

    private var repeatTitle: String {
        switch playerVM.repeatMode {
        case .off: return "Lặp tắt"
        case .all: return "Lặp tất cả"
        case .one: return "Lặp một bài"
        }
    }

    private func queueModeButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OtoTheme.captionFont)
                .fontWeight(.semibold)
                .foregroundStyle(active ? OtoTheme.accent : OtoTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: OtoTheme.minTouchTarget)
                .background(active ? OtoTheme.accentSurface : OtoTheme.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: OtoTheme.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func artwork(for song: Song) -> some View {
        AsyncImage(url: song.artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous)
                .fill(OtoTheme.backgroundSecondary)
                .overlay(Image(systemName: "music.note").foregroundStyle(OtoTheme.tertiaryText))
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: OtoTheme.smallArtworkRadius, style: .continuous))
    }
}
