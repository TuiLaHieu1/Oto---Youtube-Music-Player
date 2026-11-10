import SwiftUI
import OtoCore

/// Thanh MiniPlayer nổi đặc trưng phong cách Apple Music kết hợp hệ màu Atelier × Spectrum.
public struct MiniPlayerView: View {
    @Bindable var playerVM: PlayerViewModel

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        OtoMiniPlayer(
            song: playerVM.currentSong,
            isPlaying: playerVM.shouldShowPauseButton,
            currentPosition: playerVM.currentPosition,
            duration: playerVM.effectiveDuration,
            onTogglePlayPause: {
                playerVM.togglePlayPause()
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
