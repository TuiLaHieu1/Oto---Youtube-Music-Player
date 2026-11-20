import Foundation
import OtoCore
import os

@MainActor
extension PlayerViewModel {
    func retryCurrentTrack() {
        guard let currentSong = queueManager.currentSong else { return }
        cancelPendingCatalogPlayback()
        backend.resetCrashRecoveryBudget()
        applyEffects(stateMachine.userPlay(song: currentSong))
    }

    func handleBridgeError(code: Int, generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration,
              trackId == stateMachine.currentSong?.id else { return }
        Logger(subsystem: "com.oto.music", category: "PlayerViewModel")
            .error("Lỗi playback YouTube Web (code: \(code), gen: \(generation)).")

        let isUnavailable = code == 100 || code == 101 || code == 150 || code == 152
        let canAdvance = queueManager.remainingCount > 0
            || (repeatMode == .all && queueManager.items.count > 1)
        if isUnavailable,
           stateMachine.userIntent == .playing,
           canAdvance,
           repeatMode != .one {
            next()
            return
        }

        playbackErrorMessage = code == -999
            ? "Trình phát đã dừng sau nhiều lần khôi phục. Hãy thử lại bài hát."
            : "Không thể phát bài hát này (mã lỗi \(code))."
        pause()
    }
}
