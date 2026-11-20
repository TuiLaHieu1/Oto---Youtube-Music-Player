import Foundation
import OtoCore

@MainActor
extension PlayerViewModel {
    func startEngine(_ payload: PlaybackEffects.StartEnginePayload) {
        guard payload.generation == stateMachine.currentGeneration,
              payload.songId == stateMachine.currentSong?.id else { return }

        playbackErrorMessage = nil
        runtimeDuration = nil
        let position = stateMachine.currentPosition
        let shouldPlay = stateMachine.userIntent == .playing
            && stateMachine.interruptionState == .active
        clock.pause(at: position)
        hasRecordedCurrentTrack = false
        backend.loadVideo(
            id: payload.songId,
            startSeconds: position,
            generation: payload.generation,
            shouldPlay: shouldPlay
        )
        if shouldPlay {
            clock.play(from: position, rate: 1.0)
            startPositionTracking()
        }
    }

    func resumeEngine() {
        guard stateMachine.userIntent == .playing,
              stateMachine.interruptionState == .active else { return }
        playbackErrorMessage = nil
        clock.play(from: stateMachine.currentPosition, rate: 1.0)
        backend.play()
        startPositionTracking()
    }

    func setupAudioSessionObserver() {
        AudioSessionObserver.shared.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.applyEffects(self.stateMachine.interruptionBegan())
        }
        AudioSessionObserver.shared.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            self.applyEffects(self.stateMachine.interruptionEnded(shouldResume: shouldResume))
        }
        AudioSessionObserver.shared.onHeadphonesUnplugged = { [weak self] in
            guard let self else { return }
            self.applyEffects(self.stateMachine.routeUnplugged())
        }
    }

    func setupPlayerBridge() {
        backend.onTrackActivated = { [weak self] trackId, generation in
            guard let self,
                  generation == self.stateMachine.currentGeneration,
                  trackId == self.stateMachine.currentSong?.id else { return }
            self.logger.info("Engine đã xác nhận bài active: \(trackId), gen: \(generation)")
        }
        backend.onPlaybackStateChange = { [weak self] code, generation, trackId in
            self?.handleBridgeStateChange(stateCode: code, generation: generation, trackId: trackId)
        }
        backend.onPositionUpdate = { [weak self] current, duration, generation, trackId in
            self?.handleBridgePositionUpdate(
                current: current,
                duration: duration,
                generation: generation,
                trackId: trackId
            )
        }
        backend.onTrackEnded = { [weak self] generation, trackId in
            self?.handleBridgeTrackEnded(generation: generation, trackId: trackId)
        }
        backend.onError = { [weak self] code, generation, trackId in
            self?.handleBridgeError(code: code, generation: generation, trackId: trackId)
        }
        backend.onRemoteCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .play: self.resume()
            case .pause: self.pause()
            case .next: self.next()
            case .previous: self.previous()
            case .seek(let position): self.seek(to: position)
            }
        }
        backend.onRecoveryRequired = { [weak self] in
            guard let self else { return }
            self.logger.warning("Đang thực hiện khôi phục playback sau sự cố crash...")
            self.applyEffects(self.stateMachine.engineCrashed())
        }
    }

    private func handleBridgeStateChange(stateCode: Int, generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }
        let engineState: EnginePlaybackState
        switch stateCode {
        case 1: engineState = .playing
        case 2: engineState = .paused
        default: engineState = .buffering
        }
        applyEffects(stateMachine.engineStateChanged(engineState, generation: generation))
        if engineState == .playing {
            if !clock.isPlaying { clock.play(from: currentPosition, rate: 1.0) }
            startPositionTracking()
            if !hasRecordedCurrentTrack, let song = stateMachine.currentSong {
                hasRecordedCurrentTrack = true
                RecentlyPlayedStore.shared.recordPlayedSong(song)
                onTrackStartedPlaying?(song)
            }
        } else if engineState == .paused || engineState == .buffering {
            clock.pause()
        }
    }

    private func handleBridgePositionUpdate(
        current: TimeInterval,
        duration: TimeInterval,
        generation: Int,
        trackId: String
    ) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }
        guard current.isFinite, current >= 0 else { return }
        let previous = stateMachine.currentPosition
        if duration.isFinite, duration > 15, previous >= duration - 3,
           current < 3, previous - current > 10 {
            logger.warning("""
                Media position reset t=\(ProcessInfo.processInfo.systemUptime) \
                gen=\(generation) previous=\(previous) current=\(current) \
                mode=\(self.repeatMode.rawValue, privacy: .public)
                """)
        }

        // Tự phục hồi: nhận được position update (> 0s) trong lúc buffering, chuyển engineState sang .playing
        if stateMachine.engineState == .buffering, stateMachine.userIntent == .playing, current > 0 {
            logger.info(
                "Tự phục hồi: nhận được position update (\(current)s) trong lúc buffering, chuyển engine sang .playing"
            )
            applyEffects(stateMachine.engineStateChanged(.playing, generation: generation))
            if !clock.isPlaying { clock.play(from: current, rate: 1.0) }
            startPositionTracking()
            if !hasRecordedCurrentTrack, let song = stateMachine.currentSong {
                hasRecordedCurrentTrack = true
                RecentlyPlayedStore.shared.recordPlayedSong(song)
                onTrackStartedPlaying?(song)
            }
        }

        let isInitialDuration = runtimeDuration == nil && duration > 0
        if duration.isFinite, duration > 0 { runtimeDuration = duration }
        stateMachine.engineTimeUpdated(currentTime: current, generation: generation)
        if abs(clock.currentPosition() - current) > 0.5 { clock.seek(to: current) }
        currentPosition = current
        if abs(current - lastPersistedPosition) >= 10 {
            persistPlaybackSnapshot()
            lastPersistedPosition = current
        }

        let shouldUpdateNowPlaying: Bool
        if isInitialDuration {
            shouldUpdateNowPlaying = true
        } else if let lastInstant = lastNowPlayingUpdateInstant {
            let elapsed = ContinuousClock.now - lastInstant
            let elapsedSeconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            let expectedPosition = lastNowPlayingReportedPosition + (isPlaying ? elapsedSeconds : 0)
            shouldUpdateNowPlaying = abs(current - expectedPosition) >= 1.0
        } else {
            shouldUpdateNowPlaying = true
        }
        if shouldUpdateNowPlaying { updateNowPlayingInfo(position: current) }
    }

    private func handleBridgeTrackEnded(generation: Int, trackId: String) {
        guard generation == stateMachine.currentGeneration, trackId == stateMachine.currentSong?.id else { return }
        let effects = stateMachine.engineTrackEnded(generation: generation)
        logger.info("""
            Engine ended t=\(ProcessInfo.processInfo.systemUptime) \
            gen=\(generation) advance=\(effects.shouldAdvanceToNextTrack) \
            mode=\(self.repeatMode.rawValue, privacy: .public) \
            index=\(self.queueManager.currentIndex ?? -1)
            """)
        applyEffects(effects)
    }
}
