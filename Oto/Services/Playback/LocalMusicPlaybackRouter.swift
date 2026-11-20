import AVFoundation
import Foundation

/// Định tuyến file local và nhạc web qua cùng phiên điều khiển.
@MainActor
final class LocalMusicPlaybackRouter: PlaybackBackend {
    var onTrackActivated: ((String, Int) -> Void)?
    var onPlaybackStateChange: ((Int, Int, String) -> Void)?
    var onPositionUpdate: ((TimeInterval, TimeInterval, Int, String) -> Void)?
    var onTrackEnded: ((Int, String) -> Void)?
    var onError: ((Int, Int, String) -> Void)?
    var onRemoteCommand: ((PlaybackRemoteCommand) -> Void)?
    var onRecoveryRequired: (() -> Void)?

    private let web: any PlaybackBackend
    private let localPlayer = AVPlayer()
    private var localID: String?
    private var localGeneration = 0
    private var monitor: Task<Void, Never>?
    private var wantsPlayback = false
    private var lastState: Int?
    private var didEnd = false
    private var pendingSeek: UUID?
    private var endObserver: (any NSObjectProtocol)?

    init(web: any PlaybackBackend) {
        self.web = web
        web.onTrackActivated = { [weak self] id, generation in
            guard let self, self.localID == nil else { return }
            self.onTrackActivated?(id, generation)
        }
        web.onPlaybackStateChange = { [weak self] state, generation, id in
            guard let self, self.localID == nil else { return }
            self.onPlaybackStateChange?(state, generation, id)
        }
        web.onPositionUpdate = { [weak self] position, duration, generation, id in
            guard let self, self.localID == nil else { return }
            self.onPositionUpdate?(position, duration, generation, id)
        }
        web.onTrackEnded = { [weak self] generation, id in
            guard let self, self.localID == nil else { return }
            self.onTrackEnded?(generation, id)
        }
        web.onError = { [weak self] code, generation, id in
            guard let self, self.localID == nil else { return }
            self.onError?(code, generation, id)
        }
        web.onRemoteCommand = { [weak self] command in
            guard let self, self.localID == nil else { return }
            self.onRemoteCommand?(command)
        }
        web.onRecoveryRequired = { [weak self] in
            guard let self, self.localID == nil else { return }
            self.onRecoveryRequired?()
        }
    }

    func loadVideo(id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool) {
        let wasLocal = localID != nil
        stopLocal()
        guard id.hasPrefix(LocalMusicStore.idPrefix) else {
            web.loadVideo(id: id, startSeconds: startSeconds, generation: generation, shouldPlay: shouldPlay)
            return
        }
        localID = id
        localGeneration = generation
        if !wasLocal { web.pause() }
        guard let file = LocalMusicStore.file(for: id) else {
            onError?(-1, generation, id)
            return
        }

        let item = AVPlayerItem(url: file)
        localPlayer.replaceCurrentItem(with: item)
        wantsPlayback = shouldPlay
        didEnd = false
        lastState = nil
        onTrackActivated?(id, generation)
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: nil
        ) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, self.localID == id, self.localGeneration == generation, !self.didEnd else { return }
                self.didEnd = true
                self.onTrackEnded?(generation, id)
            }
        }
        if startSeconds > 0 { seek(to: startSeconds) }
        if shouldPlay && pendingSeek == nil { localPlayer.play() }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.localID == id, self.localGeneration == generation else { return }
                if !self.publishLocalProgress(item, id: id, generation: generation) { return }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    func play() {
        guard localID != nil else { web.play(); return }
        wantsPlayback = true
        if pendingSeek == nil { localPlayer.play() }
    }

    func pause() {
        guard localID != nil else { web.pause(); return }
        wantsPlayback = false
        localPlayer.pause()
    }

    func seek(to position: TimeInterval) {
        guard localID != nil else { web.seek(to: position); return }
        guard position.isFinite, position >= 0 else { return }
        let token = UUID()
        didEnd = false
        pendingSeek = token
        localPlayer.seek(to: CMTime(seconds: position, preferredTimescale: 600),
                         toleranceBefore: .zero, toleranceAfter: .zero) { @Sendable [weak self] finished in
            Task { @MainActor in
                guard let self, self.pendingSeek == token else { return }
                self.pendingSeek = nil
                guard finished else { return }
                if self.wantsPlayback { self.localPlayer.play() }
            }
        }
    }

    func resetForSignOut() {
        stopLocal()
        web.resetForSignOut()
    }

    private func stopLocal() {
        monitor?.cancel()
        monitor = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        localPlayer.pause()
        localPlayer.replaceCurrentItem(with: nil)
        localID = nil
        pendingSeek = nil
    }

    private func publishLocalProgress(_ item: AVPlayerItem, id: String, generation: Int) -> Bool {
        if item.status == .failed {
            onError?(-1, generation, id)
            return false
        }
        let position = localPlayer.currentTime().seconds
        let duration = item.duration.seconds
        if position.isFinite && duration.isFinite && duration > 0 {
            onPositionUpdate?(position, duration, generation, id)

        }
        guard !didEnd else { return true }
        let state = localPlayer.timeControlStatus == .playing ? 1 : (wantsPlayback ? 3 : 2)
        if lastState != state {
            lastState = state
            onPlaybackStateChange?(state, generation, id)
        }
        return true
    }
}
