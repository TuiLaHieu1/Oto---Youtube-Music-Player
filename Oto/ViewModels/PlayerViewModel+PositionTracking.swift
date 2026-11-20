import Foundation

@MainActor
extension PlayerViewModel {
    func setupNowPlayingCommands() {
        let manager = NowPlayingManager.shared
        manager.onPlayCommand = { [weak self] in self?.resume() }
        manager.onPauseCommand = { [weak self] in self?.pause() }
        manager.onTogglePlayPauseCommand = { [weak self] in self?.togglePlayPause() }
        manager.onNextCommand = { [weak self] in self?.next() }
        manager.onPreviousCommand = { [weak self] in self?.previous() }
        manager.onSeekCommand = { [weak self] position in self?.seek(to: position) }
    }

    func startPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    break
                }
                guard let self, self.stateMachine.userIntent == .playing else { break }
                if self.isPlaying {
                    self.currentPosition = self.clock.currentPosition()
                }
            }
        }
    }

    func stopPositionTracking() {
        positionTimerTask?.cancel()
        positionTimerTask = nil
    }
}
