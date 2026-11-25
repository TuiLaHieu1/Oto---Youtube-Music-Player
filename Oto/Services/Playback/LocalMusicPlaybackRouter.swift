import AVFoundation
import Foundation
#if DEBUG && OTO_STREAM_PROBE
import UIKit
#endif

/// Định tuyến file local và nhạc web qua cùng phiên điều khiển.
/// Bản khảo sát (`OTO_STREAM_PROBE`) phát mọi bài YouTube Music bằng AVPlayer với URL từ yt-dlp,
/// và quay về WebKit cho bài đó nếu không lấy được URL hoặc AVPlayer báo lỗi.
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
    #if DEBUG && OTO_STREAM_PROBE
    /// Bài kế tiếp trong hàng đợi để lấy URL trước; PlayerViewModel gán khi có cờ khảo sát.
    var upcomingTrackIDs: (() -> [String])?
    private let streamCache = YTStreamURLCache.shared
    private var isProbeStream = false
    private var isResolving = false
    private var pendingStartSeconds: TimeInterval = 0
    private var lastProbeSecond = -1
    private var didPrefetchNearEnd = false
    /// Bài đang phát bằng WebKit vì lần lấy URL trước lỗi, cùng vị trí cuối WebKit báo.
    private var webFallback: WebFallback?
    private struct WebFallback {
        let id: String
        let generation: Int
        var position: TimeInterval
    }
    /// Quá thời gian này mà chưa có URL thì phát bài bằng WebKit; yt-dlp vẫn chạy tiếp để lần sau dùng.
    private static let resolveTimeout: Duration = .seconds(20)
    #endif

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
            #if DEBUG && OTO_STREAM_PROBE
            if let fallback = self.webFallback, fallback.id == id, fallback.generation == generation {
                self.webFallback?.position = position
            }
            #endif
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
        #if DEBUG && OTO_STREAM_PROBE
        self.webFallback = nil
        if !id.hasPrefix(LocalMusicStore.idPrefix), YTMusicClient.isValidVideoID(id) {
            self.loadStream(id: id, startSeconds: startSeconds, generation: generation,
                            shouldPlay: shouldPlay, wasLocal: wasLocal)
            return
        }
        self.isProbeStream = false
        #endif
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
        self.startItem(url: file, id: id, generation: generation, startSeconds: startSeconds, shouldPlay: shouldPlay)
    }

    private func startItem(url: URL, id: String, generation: Int, startSeconds: TimeInterval, shouldPlay: Bool) {
        let item = AVPlayerItem(url: url)
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
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.localID == id, self.localGeneration == generation else { return }
                if !self.publishLocalProgress(item, id: id, generation: generation) { return }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    func play() {
        #if DEBUG && OTO_STREAM_PROBE
        if localID == nil, let fallback = self.webFallback, self.streamCache.freshURL(for: fallback.id) != nil {
            // Bài đang ở WebKit vì lần lấy URL trước lỗi; nay đã có URL thì chuyển sang AVPlayer.
            self.webFallback = nil
            self.web.pause()
            self.loadStream(id: fallback.id, startSeconds: fallback.position, generation: fallback.generation,
                            shouldPlay: true, wasLocal: false)
            self.probeTrace("retryFromWeb")
            return
        }
        #endif
        guard localID != nil else { web.play(); return }
        #if DEBUG && OTO_STREAM_PROBE
        self.probeTrace("play")
        wantsPlayback = true
        if self.isResolving { return }
        if self.isProbeStream, let id = localID, self.streamCache.freshURL(for: id) == nil {
            self.refreshExpiredStream(id: id)
            return
        }
        #endif
        wantsPlayback = true
        if pendingSeek == nil { localPlayer.play() }
    }

    func pause() {
        guard localID != nil else { web.pause(); return }
        #if DEBUG && OTO_STREAM_PROBE
        self.probeTrace("pause")
        #endif
        wantsPlayback = false
        localPlayer.pause()
    }

    func seek(to position: TimeInterval) {
        guard localID != nil else { web.seek(to: position); return }
        guard position.isFinite, position >= 0 else { return }
        #if DEBUG && OTO_STREAM_PROBE
        if self.isResolving {
            self.pendingStartSeconds = position
            return
        }
        #endif
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
        #if DEBUG && OTO_STREAM_PROBE
        self.isResolving = false
        #endif
    }

    private func publishLocalProgress(_ item: AVPlayerItem, id: String, generation: Int) -> Bool {
        if item.status == .failed {
            #if DEBUG && OTO_STREAM_PROBE
            if self.isProbeStream {
                self.fallBackToWeb(id: id, generation: generation, reason: "itemFailed")
                return false
            }
            #endif
            onError?(-1, generation, id)
            return false
        }
        let position = localPlayer.currentTime().seconds
        let duration = item.duration.seconds
        #if DEBUG && OTO_STREAM_PROBE
        self.observeProbeProgress(position: position, duration: duration)
        #endif
        if position.isFinite && duration.isFinite && duration > 0 {
            onPositionUpdate?(position, duration, generation, id)
        }
        guard !didEnd else { return true }
        let state = localPlayer.timeControlStatus == .playing ? 1 : (wantsPlayback ? 3 : 2)
        if lastState != state {
            #if DEBUG && OTO_STREAM_PROBE
            self.probeTrace("state=\(state)")
            if state == 1 { self.streamCache.prefetch(self.upcomingTrackIDs?() ?? []) }
            #endif
            lastState = state
            onPlaybackStateChange?(state, generation, id)
        }
        return true
    }
}

#if DEBUG && OTO_STREAM_PROBE
extension LocalMusicPlaybackRouter {
    /// Bài YouTube Music: dùng URL còn hạn nếu có, không thì chạy yt-dlp; lỗi thì phát bài đó bằng WebKit.
    fileprivate func loadStream(
        id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool, wasLocal: Bool
    ) {
        self.localID = id
        self.localGeneration = generation
        self.isProbeStream = true
        self.lastProbeSecond = -1
        self.didPrefetchNearEnd = false
        self.wantsPlayback = shouldPlay
        self.lastState = nil
        if !wasLocal { self.web.pause() }
        if let url = self.streamCache.freshURL(for: id) {
            self.probeTrace("load cached=1")
            self.startItem(url: url, id: id, generation: generation, startSeconds: startSeconds, shouldPlay: shouldPlay)
            return
        }
        self.probeTrace("load cached=0")
        self.isResolving = true
        self.pendingStartSeconds = startSeconds
        self.onPlaybackStateChange?(shouldPlay ? 3 : 2, generation, id)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.resolveTimeout)
            guard let self, self.localID == id, self.localGeneration == generation, self.isResolving else { return }
            self.fallBackToWeb(id: id, generation: generation, reason: "resolveTimeout")
        }
        Task { @MainActor [weak self] in
            let url = await self?.streamCache.url(for: id, reason: "load")
            guard let self, self.localID == id, self.localGeneration == generation, self.isResolving else { return }
            self.isResolving = false
            guard let url else {
                self.fallBackToWeb(id: id, generation: generation, reason: "resolveFailed")
                return
            }
            self.startItem(url: url, id: id, generation: generation,
                           startSeconds: self.pendingStartSeconds, shouldPlay: self.wantsPlayback)
        }
    }

    /// Play sau khi Pause lâu mà URL đã (sắp) hết hạn: lấy URL mới rồi phát tiếp đúng vị trí.
    fileprivate func refreshExpiredStream(id: String) {
        let generation = self.localGeneration
        let position = self.localPlayer.currentTime().seconds
        self.isResolving = true
        self.pendingStartSeconds = position.isFinite ? position : 0
        self.probeTrace("refresh")
        self.onPlaybackStateChange?(3, generation, id)
        Task { @MainActor [weak self] in
            let url = await self?.streamCache.url(for: id, reason: "refresh")
            guard let self, self.localID == id, self.localGeneration == generation, self.isResolving else { return }
            self.isResolving = false
            guard let url else {
                self.fallBackToWeb(id: id, generation: generation, reason: "refreshFailed")
                return
            }
            if let endObserver = self.endObserver { NotificationCenter.default.removeObserver(endObserver) }
            self.endObserver = nil
            self.startItem(url: url, id: id, generation: generation,
                           startSeconds: self.pendingStartSeconds, shouldPlay: self.wantsPlayback)
        }
    }

    /// Không phát được bằng AVPlayer: chuyển đúng bài này sang WebKit tại vị trí hiện tại.
    fileprivate func fallBackToWeb(id: String, generation: Int, reason: String) {
        let position = self.isResolving ? self.pendingStartSeconds : self.localPlayer.currentTime().seconds
        let shouldPlay = self.wantsPlayback
        self.probeTrace("fallback reason=\(reason)")
        if reason != "resolveTimeout" { self.streamCache.invalidate(id) }
        self.stopLocal()
        self.isProbeStream = false
        let resumeAt = position.isFinite ? max(0, position) : 0
        self.webFallback = WebFallback(id: id, generation: generation, position: resumeAt)
        self.web.loadVideo(
            id: id, startSeconds: position.isFinite ? max(0, position) : 0,
            generation: generation, shouldPlay: shouldPlay
        )
    }

    fileprivate func observeProbeProgress(position: Double, duration: Double) {
        guard self.isProbeStream, position.isFinite else { return }
        if Int(position) != self.lastProbeSecond, Int(position) % 10 == 0 {
            self.probeTrace("tick")
        }
        self.lastProbeSecond = Int(position)
        // Lấy trước bài kế khi gần hết bài (hàng đợi Radio có thể chỉ có sau khi bài bắt đầu).
        if !self.didPrefetchNearEnd, duration.isFinite, duration > 0, duration - position < 45 {
            self.didPrefetchNearEnd = true
            self.streamCache.prefetch(self.upcomingTrackIDs?() ?? [])
        }
    }

    /// Trace đo: thời điểm, trạng thái app, vị trí media thật và timeControlStatus. Không có ID hay URL.
    fileprivate func probeTrace(_ event: String) {
        guard self.isProbeStream else { return }
        let position = self.localPlayer.currentTime().seconds
        let line = String(
            format: "StreamProbe avplayer event=%@ t=%.3f appState=%d position=%.2f control=%d wants=%d",
            event, ProcessInfo.processInfo.systemUptime, UIApplication.shared.applicationState.rawValue,
            position.isFinite ? position : -1, self.localPlayer.timeControlStatus.rawValue, self.wantsPlayback ? 1 : 0
        )
        StreamProbeLog.write(line)
    }
}
#endif
