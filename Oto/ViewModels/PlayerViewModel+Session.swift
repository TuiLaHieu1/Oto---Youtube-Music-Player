import Foundation
import OtoCore

@MainActor
extension PlayerViewModel {
    /// Dừng playback và xóa queue/state khi phiên tài khoản bị đăng xuất.
    public func clearForSignOut() {
        playbackSourceTitle = nil
        confirmedVideoSelectionID = nil
        cancelPendingCatalogPlayback()
        audioSessionTask?.cancel()
        audioSessionTask = nil
        audioSessionActivationPending = false
        audioSessionActivationGeneration = nil
        queueStore.clear()
        stopPositionTracking()
        isExpanded = false
        showLyrics = false
        showQueue = false
        showAuth = false
        queueManager.setQueue(songs: [])
        runtimeDuration = nil
        playbackErrorMessage = nil
        hasRecordedCurrentTrack = false
        clock.pause(at: 0)
        applyEffects(stateMachine.stopAndClear())
        backend.resetForSignOut()
        Task { [audioSession] in await audioSession.deactivate() }
    }
}
