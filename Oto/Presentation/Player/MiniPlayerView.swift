import SwiftUI
import OtoCore

/// Thanh MiniPlayer nổi đặc trưng phong cách Apple Music kết hợp hệ màu Atelier × Spectrum.
public struct MiniPlayerView: View {
    @Bindable var playerVM: PlayerViewModel

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        let queue = playerVM.queueManager.snapshot()
        let currentItemID = queue.currentIndex.flatMap { index in
            queue.items.indices.contains(index) ? queue.items[index].id : nil
        }
        OtoMiniPlayer(
            song: playerVM.currentSong,
            queueItemID: currentItemID,
            isPlaying: playerVM.shouldShowPauseButton,
            currentPosition: playerVM.currentPosition,
            duration: playerVM.effectiveDuration,
            onTogglePlayPause: {
                playerVM.togglePlayPause()
            },
            onPrevious: {
                playerVM.swipeToPreviousTrack()
            },
            onNext: {
                playerVM.next()
            },
            onExpand: {
                withAnimation(OtoTheme.smoothSpring) {
                    playerVM.isExpanded = true
                }
            }
        )
    }
}
