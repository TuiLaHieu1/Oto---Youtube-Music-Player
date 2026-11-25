#if DEBUG && OTO_STREAM_PROBE
import AVFoundation

/// Nạp sẵn bộ đệm của bài kế trên một AVPlayer phụ luôn tắt tiếng.
/// Một AVPlayerItem không được gắn sang AVPlayer khác (làm app crash), nên khi chuyển sang bài đó
/// thì đổi vai: player phụ thành player chính, player chính cũ thành player phụ.
@MainActor
final class ProbePreloader {
    private var player = AVPlayer()
    private var preloaded: (id: String, item: AVPlayerItem)?
    private var statusObserver: NSKeyValueObservation?

    /// Lấy trước URL của các bài kế; bài ngay sau được nạp sẵn bộ đệm khi đã có URL.
    func prefetch(_ upcoming: [String], cache: YTStreamURLCache, isStillNext: @escaping @MainActor (String) -> Bool) {
        cache.prefetch(upcoming) { [weak self, weak cache] videoID in
            guard let self, videoID == upcoming.first, isStillNext(videoID),
                  let url = cache?.freshURL(for: videoID) else { return }
            self.preload(videoID, url: url)
        }
    }

    private func preload(_ videoID: String, url: URL) {
        guard self.preloaded?.id != videoID else { return }
        StreamProbeLog.write("StreamProbe avplayer event=preload t=\(ProcessInfo.processInfo.systemUptime)")
        let item = AVPlayerItem(url: url)
        self.preloaded = (videoID, item)
        self.player.isMuted = true
        self.player.replaceCurrentItem(with: item)
        self.statusObserver = item.observe(\.status, options: [.new]) { @Sendable [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in
                // preroll yêu cầu player đã sẵn sàng, nếu không AVFoundation có thể ném exception.
                guard let self, self.preloaded?.item === item, self.player.status == .readyToPlay else { return }
                self.player.preroll(atRate: 1) { _ in }
            }
        }
    }

    /// Trả player phụ đang giữ item của bài `videoID` để làm player chính, và nhận `current` làm player phụ.
    /// Bài khác hoặc item lỗi thì bỏ item nạp sẵn và trả nil.
    func take(_ videoID: String, replacing current: AVPlayer) -> (player: AVPlayer, item: AVPlayerItem)? {
        guard let preloaded = self.preloaded else { return nil }
        self.preloaded = nil
        self.statusObserver = nil
        self.player.cancelPendingPrerolls()
        guard preloaded.id == videoID, preloaded.item.status != .failed,
              self.player.currentItem === preloaded.item else {
            self.player.replaceCurrentItem(with: nil)
            return nil
        }
        current.pause()
        current.replaceCurrentItem(with: nil)
        current.isMuted = true
        let next = self.player
        next.isMuted = false
        self.player = current
        return (next, preloaded.item)
    }
}
#endif
