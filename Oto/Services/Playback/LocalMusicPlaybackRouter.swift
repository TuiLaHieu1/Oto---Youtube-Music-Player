import AVFoundation
import Foundation
#if DEBUG && OTO_STREAM_PROBE
import UIKit
#endif

/// Định tuyến file local và nhạc web qua cùng phiên điều khiển.
/// Bản khảo sát (`OTO_STREAM_PROBE`) phát mọi bài YouTube Music bằng AVPlayer với URL từ yt-dlp;
/// không dùng WebKit, lỗi lấy URL được báo qua `onError`.
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
    private var localPlayer = AVPlayer()
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
    private var didRetryFailedItem = false
    /// AVPlayer thứ hai giữ sẵn item của bài kế để nạp bộ đệm trước, luôn tắt tiếng.
    /// Khi chuyển sang bài đó thì đổi vai hai player, vì một AVPlayerItem không được gắn sang player khác.
    private var preloadPlayer = AVPlayer()
    private var preloaded: (id: String, item: AVPlayerItem)?
    private var preloadStatusObserver: NSKeyValueObservation?
    /// Quá thời gian này mà chưa có URL thì báo lỗi rõ ràng thay vì quay mãi.
    private static let resolveTimeout: Duration = .seconds(40)
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

    private func startItem(
        url: URL, id: String, generation: Int, startSeconds: TimeInterval, shouldPlay: Bool,
        prepared: AVPlayerItem? = nil
    ) {
        let item = prepared ?? AVPlayerItem(url: url)
        if localPlayer.currentItem !== item { localPlayer.replaceCurrentItem(with: item) }
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
                self.recoverFailedItem(id: id, generation: generation)
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
            if state == 1 { self.prefetchUpcoming() }
            #endif
            lastState = state
            onPlaybackStateChange?(state, generation, id)
        }
        return true
    }
}

#if DEBUG && OTO_STREAM_PROBE
extension LocalMusicPlaybackRouter {
    /// Bài YouTube Music: dùng item nạp sẵn hoặc URL còn hạn nếu có, không thì chạy yt-dlp.
    fileprivate func loadStream(
        id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool, wasLocal: Bool
    ) {
        self.localID = id
        self.localGeneration = generation
        self.isProbeStream = true
        self.lastProbeSecond = -1
        self.didPrefetchNearEnd = false
        self.didRetryFailedItem = false
        self.wantsPlayback = shouldPlay
        self.lastState = nil
        if !wasLocal { self.web.pause() }
        if let url = self.streamCache.freshURL(for: id) {
            let prepared = self.takePreloaded(id)
            self.probeTrace("load cached=1 preloaded=\(prepared != nil ? 1 : 0)")
            self.startItem(url: url, id: id, generation: generation, startSeconds: startSeconds,
                           shouldPlay: shouldPlay, prepared: prepared)
            return
        }
        self.probeTrace("load cached=0")
        self.resolveAndStart(id: id, generation: generation, startSeconds: startSeconds, reason: "load")
    }

    private func resolveAndStart(id: String, generation: Int, startSeconds: TimeInterval, reason: String) {
        self.isResolving = true
        self.pendingStartSeconds = startSeconds
        self.onPlaybackStateChange?(self.wantsPlayback ? 3 : 2, generation, id)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.resolveTimeout)
            guard let self, self.localID == id, self.localGeneration == generation, self.isResolving else { return }
            self.isResolving = false
            self.probeTrace("error reason=timeout")
            self.onError?(-1001, generation, id)
        }
        Task { @MainActor [weak self] in
            guard let resolution = await self?.streamCache.resolve(id, reason: reason) else { return }
            guard let self, self.localID == id, self.localGeneration == generation, self.isResolving else { return }
            self.isResolving = false
            switch resolution {
            case .url(let url):
                if let endObserver = self.endObserver { NotificationCenter.default.removeObserver(endObserver) }
                self.endObserver = nil
                self.startItem(url: url, id: id, generation: generation,
                               startSeconds: self.pendingStartSeconds, shouldPlay: self.wantsPlayback)
            case .failed(let unavailable):
                // 150: bài không phát được, PlayerViewModel tự chuyển bài nếu còn bài kế. -1009: lỗi mạng.
                self.probeTrace("error reason=\(unavailable ? "unavailable" : "network")")
                self.onError?(unavailable ? 150 : -1009, generation, id)
            }
        }
    }

    /// Play sau khi Pause lâu mà URL đã (sắp) hết hạn: lấy URL mới rồi phát tiếp đúng vị trí.
    fileprivate func refreshExpiredStream(id: String) {
        let position = self.localPlayer.currentTime().seconds
        self.probeTrace("refresh")
        self.resolveAndStart(id: id, generation: self.localGeneration,
                             startSeconds: position.isFinite ? position : 0, reason: "refresh")
    }

    /// AVPlayer báo lỗi (URL bị từ chối hoặc hết hạn): lấy URL mới một lần tại vị trí hiện tại, rồi mới báo lỗi.
    fileprivate func recoverFailedItem(id: String, generation: Int) {
        self.streamCache.invalidate(id)
        guard !self.didRetryFailedItem else {
            self.probeTrace("error reason=itemFailed")
            self.onError?(-1, generation, id)
            return
        }
        self.didRetryFailedItem = true
        let position = self.localPlayer.currentTime().seconds
        self.probeTrace("retry reason=itemFailed")
        self.resolveAndStart(id: id, generation: generation,
                             startSeconds: position.isFinite ? position : 0, reason: "retry")
    }

    // MARK: - Lấy trước và nạp sẵn bài kế

    fileprivate func prefetchUpcoming() {
        let upcoming = self.upcomingTrackIDs?() ?? []
        self.streamCache.prefetch(upcoming) { [weak self] videoID in
            guard let self, videoID == upcoming.first else { return }
            self.preload(videoID)
        }
    }

    /// Gắn item của bài kế vào AVPlayer phụ để nó nạp sẵn bộ đệm. Không phát tiếng.
    private func preload(_ videoID: String) {
        guard self.preloaded?.id != videoID, videoID != self.localID,
              let url = self.streamCache.freshURL(for: videoID) else { return }
        let item = AVPlayerItem(url: url)
        self.preloaded = (videoID, item)
        self.preloadPlayer.isMuted = true
        self.preloadPlayer.replaceCurrentItem(with: item)
        self.preloadStatusObserver = item.observe(\.status, options: [.new]) { @Sendable [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in
                guard let self, self.preloaded?.item === item else { return }
                self.preloadPlayer.preroll(atRate: 1) { _ in }
            }
        }
        self.probeTrace("preload")
    }

    /// Lấy item đã nạp sẵn cho đúng bài bằng cách đổi vai: player phụ (đang giữ item) thành player chính.
    /// Item không bị tách khỏi player của nó. Bài khác thì bỏ item nạp sẵn đi.
    private func takePreloaded(_ videoID: String) -> AVPlayerItem? {
        guard let preloaded = self.preloaded else { return nil }
        self.preloaded = nil
        self.preloadStatusObserver = nil
        self.preloadPlayer.cancelPendingPrerolls()
        guard preloaded.id == videoID, preloaded.item.status != .failed,
              self.preloadPlayer.currentItem === preloaded.item else {
            self.preloadPlayer.replaceCurrentItem(with: nil)
            return nil
        }
        self.localPlayer.pause()
        self.localPlayer.replaceCurrentItem(with: nil)
        swap(&self.localPlayer, &self.preloadPlayer)
        self.localPlayer.isMuted = false
        self.preloadPlayer.isMuted = true
        return preloaded.item
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
            self.prefetchUpcoming()
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
