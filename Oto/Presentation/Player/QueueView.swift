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
                                Text("ĐANG PHÁT")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(OtoTheme.secondaryText)
                                    .padding(.horizontal, OtoTheme.spacing16)

                                HStack(spacing: OtoTheme.spacing12) {
                                    Image(systemName: "speaker.wave.3.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(OtoTheme.accent)

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
                        }

                        // Section: Tiếp theo trong hàng đợi
                        VStack(alignment: .leading, spacing: OtoTheme.spacing8) {
                            Text("TIẾP THEO TRONG HÀNG ĐỢI")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(OtoTheme.secondaryText)
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
                                                Text("\(index - currentIndex)")
                                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(OtoTheme.secondaryText)
                                                    .frame(width: 24, alignment: .leading)

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
                                            .background(
                                                RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                                                    .fill(OtoTheme.surface)
                                                    .overlay(
                                                    RoundedRectangle(
                                                        cornerRadius: OtoTheme.cardRadius,
                                                        style: .continuous
                                                    )
                                                    .stroke(OtoTheme.separator, lineWidth: 0.5)
                                                    )
                                            )
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, OtoTheme.spacing16)
                            }
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
}
