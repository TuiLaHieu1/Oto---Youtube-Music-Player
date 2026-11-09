import SwiftUI
import OtoCore

/// Màn hình danh sách phát tiếp theo (Queue / Up Next).
public struct QueueView: View {
    @Bindable var playerVM: PlayerViewModel

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Đang phát") {
                    if let currentSong = playerVM.currentSong {
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(currentSong.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text(currentSong.artist)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Tiếp theo trong hàng đợi") {
                    let items = playerVM.queueManager.items
                    let currentIndex = playerVM.queueManager.currentIndex ?? 0
                    let upcomingIndices = Array(items.indices.filter { $0 > currentIndex })

                    if upcomingIndices.isEmpty {
                        Text("Không có bài hát tiếp theo")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcomingIndices, id: \.self) { index in
                            let item = items[index]
                            HStack(spacing: 12) {
                                Text("\(index - currentIndex)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.song.title)
                                        .font(.system(size: 15, weight: .medium))

                                    Text(item.song.artist)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playerVM.play(song: item.song)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hàng đợi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        playerVM.showQueue = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
