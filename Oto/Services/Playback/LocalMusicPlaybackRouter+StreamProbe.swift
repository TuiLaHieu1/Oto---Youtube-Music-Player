#if DEBUG && OTO_STREAM_PROBE
import AVFoundation
import Foundation
import UIKit

extension LocalMusicPlaybackRouter {
    /// Bài YouTube Music: dùng item nạp sẵn hoặc URL còn hạn nếu có, không thì chạy yt-dlp.
    func loadStream(
        id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool, wasLocal: Bool
    ) {
        self.localID = id
        self.localGeneration = generation
        self.isProbeStream = true
        self.lastProbeSecond = -1
        self.lastKnownPosition = startSeconds
        self.didPrefetchNearEnd = false
        self.didRetryFailedItem = false
        self.wantsPlayback = shouldPlay
        self.lastState = nil
        self.leaveVideoMode()
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
        // Mỗi lần lấy URL có một hẹn giờ riêng; hẹn giờ cũ bị hủy để không báo timeout nhầm cho lần sau.
        self.resolveTimeoutTask?.cancel()
        self.resolveTimeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: Self.resolveTimeout) } catch { return }
            guard let self, self.localID == id, self.localGeneration == generation, self.isResolving else { return }
            self.isResolving = false
            self.probeTrace("error reason=timeout")
            self.onError?(-1001, generation, id)
        }
        Task { @MainActor [weak self] in
            guard let resolution = await self?.streamCache.resolve(id, reason: reason) else { return }
            guard let self, self.localID == id, self.localGeneration == generation, self.isResolving else { return }
            self.isResolving = false
            self.resolveTimeoutTask?.cancel()
            switch resolution {
            case .url(let url):
                self.leaveVideoMode(keepsRequest: true)
                self.startItem(url: url, id: id, generation: generation,
                               startSeconds: self.pendingStartSeconds, shouldPlay: self.wantsPlayback)
                // Người dùng đã bật Video trong lúc chờ URL: áp lại sau khi bài chạy.
                if self.wantsVideoItem { self.setVideoMode(true) }
            case .failed(let unavailable):
                // 150: bài không phát được, PlayerViewModel tự chuyển bài nếu còn bài kế. -1009: lỗi mạng.
                self.probeTrace("error reason=\(unavailable ? "unavailable" : "network")")
                self.onError?(unavailable ? 150 : -1009, generation, id)
            }
        }
    }

    /// Play sau khi Pause lâu mà URL đã (sắp) hết hạn: lấy URL mới rồi phát tiếp đúng vị trí.
    func refreshExpiredStream(id: String) {
        let position = self.localPlayer.currentTime().seconds
        self.probeTrace("refresh")
        self.resolveAndStart(id: id, generation: self.localGeneration,
                             startSeconds: position.isFinite ? position : 0, reason: "refresh")
    }

    /// AVPlayer báo lỗi (URL bị từ chối hoặc hết hạn): lấy URL mới một lần tại vị trí cuối, rồi mới báo lỗi.
    /// Item lỗi thường trả currentTime 0, nên dùng vị trí cuối đã ghi nhận.
    func recoverFailedItem(id: String, generation: Int) {
        if self.isVideoItem, let audio = self.streamCache.freshURL(for: id) {
            // Luồng video lỗi: quay về audio còn hạn, báo lỗi Video, không tính vào lượt thử lại của audio.
            self.probeTrace("video failed")
            self.leaveVideoMode()
            self.videoOutput.failed = true
            self.startItem(url: audio, id: id, generation: generation, startSeconds: self.lastKnownPosition,
                           shouldPlay: self.wantsPlayback, activates: false)
            return
        }
        self.streamCache.invalidate(id)
        guard !self.didRetryFailedItem else {
            self.probeTrace("error reason=itemFailed")
            self.onError?(-1, generation, id)
            return
        }
        self.didRetryFailedItem = true
        self.probeTrace("retry reason=itemFailed")
        self.resolveAndStart(id: id, generation: generation, startSeconds: self.lastKnownPosition, reason: "retry")
    }

    // MARK: - Chế độ Video

    /// Bật Video: chuyển sang manifest HLS có hình của cùng bài, giữ vị trí và trạng thái phát.
    /// Tắt Video: chỉ gỡ hình, phát tiếp HLS (có tiếng) tới hết bài để không ngắt tiếng khi nạp lại audio;
    /// giới hạn HLS ở mức hình thấp nhất để đỡ tốn mạng. Đang chờ URL thì `resolveAndStart` áp lại yêu cầu.
    func setVideoMode(_ wantsVideo: Bool) {
        guard self.isProbeStream, let id = self.localID else { return }
        self.wantsVideoItem = wantsVideo
        self.videoOutput.failed = false
        self.videoSwitchToken += 1
        guard wantsVideo, !self.isVideoItem else {
            self.videoOutput.player = wantsVideo ? self.localPlayer : nil
            self.localPlayer.currentItem?.preferredMaximumResolution = wantsVideo ? .zero : Self.hiddenVideoSize
            return
        }
        let token = self.videoSwitchToken
        let generation = self.localGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let videoURL = await self.streamCache.videoURL(for: id)
            guard self.videoSwitchToken == token, self.localID == id, self.localGeneration == generation,
                  !self.isResolving, !self.isVideoItem else { return }
            guard let url = videoURL else {
                self.probeTrace("video unavailable")
                self.videoOutput.failed = true
                return
            }
            let position = self.localPlayer.currentTime().seconds
            self.isVideoItem = true
            self.startItem(url: url, id: id, generation: generation,
                           startSeconds: position.isFinite ? position : 0, shouldPlay: self.wantsPlayback,
                           activates: false)
            self.videoOutput.player = self.localPlayer
            self.probeTrace("video mode=1")
        }
    }

    /// Bài mới hoặc URL mới luôn là audio. `keepsRequest`: giữ lựa chọn Video của người dùng cho cùng bài.
    func leaveVideoMode(keepsRequest: Bool = false) {
        if !keepsRequest { self.wantsVideoItem = false }
        self.videoSwitchToken += 1
        self.isVideoItem = false
        self.videoOutput.player = nil
        self.videoOutput.failed = false
    }

    // MARK: - Lấy trước và nạp sẵn bài kế

    func prefetchUpcoming() {
        self.preloader.prefetch(self.upcomingTrackIDs?() ?? [], cache: self.streamCache) { [weak self] in
            self?.localID
        }
    }

    /// Lấy item nạp sẵn của đúng bài; player phụ đang giữ item trở thành player chính.
    private func takePreloaded(_ videoID: String) -> AVPlayerItem? {
        guard let handoff = self.preloader.take(videoID, replacing: self.localPlayer) else { return nil }
        self.localPlayer = handoff.player
        return handoff.item
    }

    func observeProbeProgress(position: Double, duration: Double) {
        guard self.isProbeStream, position.isFinite else { return }
        if position > 0 { self.lastKnownPosition = position }
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
    func probeTrace(_ event: String) {
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
