import AVFoundation
import Foundation
#if DEBUG && OTO_STREAM_PROBE
import UIKit
#endif

/// Định tuyến file local và nhạc web qua cùng phiên điều khiển.
/// Bản khảo sát (`OTO_STREAM_PROBE`) phát mọi bài YouTube Music bằng AVPlayer với URL từ yt-dlp;
/// không dùng WebKit, lỗi lấy URL được báo qua `onError`.
@MainActor
/// Thành viên không `private` là để phần khảo sát ở `LocalMusicPlaybackRouter+StreamProbe.swift` dùng được.
final class LocalMusicPlaybackRouter: PlaybackBackend {
    var onTrackActivated: ((String, Int) -> Void)?
    var onPlaybackStateChange: ((Int, Int, String) -> Void)?
    var onPositionUpdate: ((TimeInterval, TimeInterval, Int, String) -> Void)?
    var onTrackEnded: ((Int, String) -> Void)?
    var onError: ((Int, Int, String) -> Void)?
    var onRemoteCommand: ((PlaybackRemoteCommand) -> Void)?
    var onRecoveryRequired: (() -> Void)?

    let web: any PlaybackBackend
    var localPlayer = AVPlayer()
    var localID: String?
    var localGeneration = 0
    private var monitor: Task<Void, Never>?
    var wantsPlayback = false
    var lastState: Int?
    private var didEnd = false
    private var pendingSeek: UUID?
    private var endObserver: (any NSObjectProtocol)?
    #if DEBUG && OTO_STREAM_PROBE
    /// Bài kế tiếp trong hàng đợi để lấy URL trước; PlayerViewModel gán khi có cờ khảo sát.
    var upcomingTrackIDs: (() -> [String])?
    let streamCache = YTStreamURLCache.shared
    var isProbeStream = false
    var isResolving = false
    var pendingStartSeconds: TimeInterval = 0
    var lastProbeSecond = -1
    var didPrefetchNearEnd = false
    var didRetryFailedItem = false
    let preloader = ProbePreloader()
    /// Player đang phát manifest HLS có hình cho màn hình Video; nil khi phát audio.
    let videoOutput = ProbeVideoOutput()
    /// Luồng đang phát là manifest HLS có hình (giữ tới hết bài kể cả khi người dùng tắt Video).
    var isVideoItem = false
    /// Lựa chọn Video mới nhất của người dùng cho bài hiện tại; áp lại sau khi lấy URL mới.
    var wantsVideoItem = false
    /// Vị trí phát cuối đã ghi nhận; item lỗi thường báo currentTime 0.
    var lastKnownPosition: TimeInterval = 0
    var resolveTimeoutTask: Task<Void, Never>?
    var resolveRequestID: UUID?
    /// Tắt Video mà vẫn phát HLS thì giới hạn ở biến thể nhỏ nhất (144p) để đỡ tốn mạng.
    static let hiddenVideoSize = CGSize(width: 256, height: 144)
    var videoSwitchToken = 0
    /// Quá thời gian này mà chưa có URL thì báo lỗi rõ ràng thay vì quay mãi.
    static let resolveTimeout: Duration = .seconds(40)
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
        self.leaveVideoMode()
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

    func startItem(
        url: URL, id: String, generation: Int, startSeconds: TimeInterval, shouldPlay: Bool,
        prepared: AVPlayerItem? = nil, activates: Bool = true
    ) {
        let item = prepared ?? AVPlayerItem(url: url)
        if localPlayer.currentItem !== item { localPlayer.replaceCurrentItem(with: item) }
        wantsPlayback = shouldPlay
        didEnd = false
        lastState = nil
        if activates { onTrackActivated?(id, generation) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let itemIdentity = ObjectIdentifier(item)
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: nil
        ) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, self.localID == id, self.localGeneration == generation,
                      let currentItem = self.localPlayer.currentItem,
                      ObjectIdentifier(currentItem) == itemIdentity, !self.didEnd else { return }
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
        self.resolveRequestID = nil
        self.resolveTimeoutTask?.cancel()
        self.resolveTimeoutTask = nil
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
