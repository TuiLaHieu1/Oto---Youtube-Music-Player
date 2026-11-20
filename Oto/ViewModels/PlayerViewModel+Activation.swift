import Foundation
import OtoCore

@MainActor
extension PlayerViewModel {
    func scheduleEngineOperation() {
        activationTask?.cancel()
        engineOperationRevision += 1
        let revision = engineOperationRevision
        let interruption = interruptionTask
        let generation = stateMachine.currentGeneration
        if stateMachine.userIntent == .playing, !isWatchdogActive {
            startLoadingWatchdog(for: generation)
        }
        activationTask = Task { [weak self] in
            guard let self else { return }
            do {
                await interruption?.value
                try Task.checkCancellation()
                if self.stateMachine.userIntent == .playing {
                    try await self.audioSession.prepareForPlayback()
                }
                guard !Task.isCancelled, revision == self.engineOperationRevision,
                      generation == self.stateMachine.currentGeneration else { return }
                self.activationTask = nil
                let shouldPlay = self.stateMachine.userIntent == .playing
                    && self.stateMachine.interruptionState == .active
                if let payload = self.pendingEngineLoad {
                    self.pendingEngineLoad = nil
                    self.backend.loadVideo(
                        id: payload.songId,
                        startSeconds: self.stateMachine.currentPosition,
                        generation: payload.generation,
                        shouldPlay: shouldPlay
                    )
                } else if shouldPlay {
                    self.backend.play()
                }
                if shouldPlay, !self.isWatchdogActive { self.startLoadingWatchdog(for: generation) }
                self.syncPublicState()
            } catch {
                guard !Task.isCancelled, revision == self.engineOperationRevision,
                      generation == self.stateMachine.currentGeneration else { return }
                self.activationTask = nil
                self.pendingEngineLoad = nil
                self.playbackErrorMessage = "Không thể kích hoạt âm thanh. Hãy thử lại."
                self.pause()
            }
        }
    }

    func invalidateAudioSessionForInterruption() {
        let previousInterruption = interruptionTask
        let previous = activationTask
        previous?.cancel()
        activationTask = nil
        engineOperationRevision += 1
        cancelLoadingWatchdog()
        let audio = audioSession
        interruptionTask = Task {
            await previousInterruption?.value
            await previous?.value
            await audio.invalidateForInterruption()
        }
    }

    func waitForPendingAudioOperation() async {
        await activationTask?.value
    }
}
