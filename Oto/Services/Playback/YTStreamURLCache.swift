#if DEBUG && OTO_STREAM_PROBE
import AVFoundation
import Foundation
import Observation
import Network
import SwiftUI
import UIKit

/// Chính sách mạng chỉ áp dụng cho lần lấy URL tiếp theo.
@MainActor
final class StreamNetworkPolicy {
    static let shared = StreamNetworkPolicy()
    static let qualityKey = "stream_audio_quality"
    private let monitor = NWPathMonitor()
    private(set) var allowsPrefetch = false
    private var metered = true
    var onChange: (() -> Void)?

    var lowBandwidth: Bool {
        switch UserDefaults.standard.string(forKey: Self.qualityKey) {
        case "best": return false
        case "economy": return true
        default: return self.metered
        }
    }

    private init() {
        self.monitor.pathUpdateHandler = { [weak self] path in
            let metered = path.isExpensive || path.isConstrained
            let allowsPrefetch = path.status == .satisfied && !metered
            Task { @MainActor in
                guard let self else { return }
                guard self.metered != metered || self.allowsPrefetch != allowsPrefetch else { return }
                self.metered = metered
                self.allowsPrefetch = allowsPrefetch
                self.onChange?()
            }
        }
        self.monitor.start(queue: DispatchQueue(label: "com.oto.stream-network"))
    }

    func preferencesChanged() { self.onChange?() }
}

/// Kết quả lấy URL cho một bài.
enum YTStreamResolution: Sendable {
    case url(URL, mediaDuration: TimeInterval?)
    /// `unavailable`: lỗi do chính bài (bị chặn, không có định dạng phát được), nên bỏ qua bài.
    case failed(unavailable: Bool)
}

/// Bộ nhớ URL audio đã lấy bằng yt-dlp, theo hạn dùng của từng URL. Chỉ trong bộ nhớ, giới hạn số mục.
/// Gộp các yêu cầu trùng cho cùng một bài để một bài không chạy yt-dlp hai lần cùng lúc.
@MainActor
final class YTStreamURLCache {
    struct Entry {
        let url: URL
        /// Manifest HLS có hình (cùng lần lấy, cùng hạn dùng); nil nếu bài không có.
        let hlsURL: URL?
        let mediaDuration: TimeInterval?
        let expiresAt: Date
        let lowBandwidth: Bool
    }

    static let shared = YTStreamURLCache()
    /// URL còn dưới khoảng này là coi như hết hạn, để không phát một URL sắp chết giữa bài.
    static let refreshMargin: TimeInterval = 10 * 60
    private static let capacity = 40

    private var revision = 0
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<YTStreamResolution, Never>] = [:]

    func freshURL(for videoID: String, now: Date = Date()) -> URL? {
        self.freshEntry(for: videoID, now: now)?.url
    }

    func freshEntry(for videoID: String, now: Date = Date()) -> Entry? {
        guard let entry = self.entries[videoID],
              entry.lowBandwidth == StreamNetworkPolicy.shared.lowBandwidth,
              entry.expiresAt.timeIntervalSince(now) > Self.refreshMargin else {
            return nil
        }
        return entry
    }

    /// Manifest HLS còn hạn của bài, nếu lần lấy URL có trả về.
    func freshVideoURL(for videoID: String, now: Date = Date()) -> URL? {
        guard self.freshURL(for: videoID, now: now) != nil else { return nil }
        return self.entries[videoID]?.hlsURL
    }

    /// Manifest HLS cho chế độ Video. Nếu lần lấy trước không có (yt-dlp bỏ qua manifest khi mạng chậm)
    /// hoặc URL đã hết hạn thì chạy yt-dlp lại đúng một lần.
    func videoURL(for videoID: String) async -> URL? {
        if let url = self.freshVideoURL(for: videoID) { return url }
        _ = await self.resolve(videoID, reason: "video", bypassCache: true)
        return self.freshVideoURL(for: videoID)
    }

    func invalidate(_ videoID: String) {
        self.entries[videoID] = nil
        self.order.removeAll { $0 == videoID }
    }

    func clear() {
        self.revision += 1
        self.entries.removeAll()
        self.order.removeAll()
        self.inFlight.values.forEach { $0.cancel() }
        self.inFlight.removeAll()
    }

    /// Trả URL còn hạn nếu có; nếu không thì chạy yt-dlp (gộp yêu cầu trùng).
    /// `bypassCache`: chạy lại dù URL còn hạn; mục cũ vẫn dùng được cho tới khi có kết quả mới.
    func resolve(_ videoID: String, reason: String, bypassCache: Bool = false) async -> YTStreamResolution {
        if !bypassCache, let entry = self.freshEntry(for: videoID) {
            return .url(entry.url, mediaDuration: entry.mediaDuration)
        }
        let lowBandwidth = StreamNetworkPolicy.shared.lowBandwidth
        let key = "\(self.revision)-\(lowBandwidth)-\(videoID)"
        let revision = self.revision
        if let task = self.inFlight[key] { return await task.value }
        let task = Task { @MainActor [weak self] () -> YTStreamResolution in
            // Xin thêm thời gian chạy khi app ở nền (ví dụ Next từ Lock Screen sau khi Pause lâu).
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "oto.stream-resolve")
            defer {
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            let result = await PythonStreamResolver.resolve(videoID: videoID, lowBandwidth: lowBandwidth)
            StreamProbeLog.write(
                "StreamProbe resolve reason=\(reason) appState=\(UIApplication.shared.applicationState.rawValue) "
                    + "ok=\(result.url != nil) label=\(result.errorLabel ?? "none")"
            )
            guard !Task.isCancelled, self?.revision == revision else { return .failed(unavailable: false) }
            guard let url = result.url else { return .failed(unavailable: result.isTrackUnavailable) }
            let lifetime = TimeInterval(result.secondsUntilExpiry ?? 0)
            if lowBandwidth == StreamNetworkPolicy.shared.lowBandwidth {
                self?.store(
                    Entry(url: url, hlsURL: result.hlsURL, mediaDuration: result.mediaDuration,
                          expiresAt: Date().addingTimeInterval(lifetime), lowBandwidth: lowBandwidth),
                    for: videoID
                )
            }
            return .url(url, mediaDuration: result.mediaDuration)
        }
        self.inFlight[key] = task
        let result = await task.value
        self.inFlight[key] = nil
        return result
    }

    /// Lấy trước URL; gọi `completion` cho từng bài lấy được để router nạp sẵn bộ đệm.
    func prefetch(_ videoIDs: [String], completion: @escaping @MainActor (String) -> Void) {
        guard StreamNetworkPolicy.shared.allowsPrefetch else { return }
        for videoID in videoIDs.prefix(1) where YTMusicClient.isValidVideoID(videoID) {
            if self.freshURL(for: videoID) != nil {
                completion(videoID)
                continue
            }
            let revision = self.revision
            Task {
                guard self.revision == revision, StreamNetworkPolicy.shared.allowsPrefetch else { return }
                if case .url = await self.resolve(videoID, reason: "prefetch"), self.revision == revision {
                    completion(videoID)
                }
            }
        }
    }

    private func store(_ entry: Entry, for videoID: String) {
        self.entries[videoID] = entry
        self.order.removeAll { $0 == videoID }
        self.order.append(videoID)
        while self.order.count > Self.capacity {
            let oldest = self.order.removeFirst()
            self.entries[oldest] = nil
        }
    }
}

/// Player đang phát luồng video cho màn hình Video. `player` nil khi đang phát audio.
@MainActor
@Observable
final class ProbeVideoOutput {
    var player: AVPlayer?
    /// Bài hiện tại không có manifest HLS hoặc chuyển sang video thất bại.
    var failed = false
}

extension PlayerViewModel {
    /// Màn hình Video của bản khảo sát đọc player từ đây.
    var probeVideoOutput: ProbeVideoOutput? { (self.backend as? LocalMusicPlaybackRouter)?.videoOutput }

    func setProbeVideoMode(_ wantsVideo: Bool) {
        (self.backend as? LocalMusicPlaybackRouter)?.setVideoMode(wantsVideo)
    }
}

/// Mặt video bằng AVPlayerLayer. Gỡ player khỏi layer khi app vào nền để AVPlayer phát tiếp tiếng
/// (theo hướng dẫn của Apple cho phát nền), gắn lại khi app quay về.
struct ProbeVideoLayer: UIViewRepresentable {
    let player: AVPlayer
    let onReady: (Bool) -> Void

    func makeUIView(context: Context) -> ProbeVideoLayerView {
        let view = ProbeVideoLayerView()
        view.onReady = self.onReady
        view.attach(self.player)
        return view
    }

    func updateUIView(_ view: ProbeVideoLayerView, context: Context) {
        view.onReady = self.onReady
        view.attach(self.player)
    }

    static func dismantleUIView(_ view: ProbeVideoLayerView, coordinator: ()) {
        view.detach()
    }
}

final class ProbeVideoLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var onReady: ((Bool) -> Void)?
    private var player: AVPlayer?
    private var readyObserver: NSKeyValueObservation?
    private var observers: [any NSObjectProtocol] = []

    private var playerLayer: AVPlayerLayer? { self.layer as? AVPlayerLayer }

    func attach(_ player: AVPlayer) {
        guard self.player !== player else { return }
        self.player = player
        self.playerLayer?.videoGravity = .resizeAspect
        self.playerLayer?.player = UIApplication.shared.applicationState == .background ? nil : player
        self.readyObserver = self.playerLayer?.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            guard let self else { return }
            Task { @MainActor [weak self] in
                StreamProbeLog.write("StreamProbe video layer ready=\(ready ? 1 : 0)")
                self?.onReady?(ready)
            }
        }
        guard self.observers.isEmpty else { return }
        self.observers = [
            self.observe(UIApplication.didEnterBackgroundNotification, attaches: false),
            self.observe(UIApplication.willEnterForegroundNotification, attaches: true)
        ]
    }

    private func observe(_ name: Notification.Name, attaches: Bool) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.playerLayer?.player = attaches ? self.player : nil
            }
        }
    }

    func detach() {
        self.readyObserver = nil
        self.observers.forEach { NotificationCenter.default.removeObserver($0) }
        self.observers = []
        self.playerLayer?.player = nil
        self.player = nil
    }
}

/// Backend rỗng thay cho WebKit trong bản khảo sát: mọi bài YouTube Music đi qua AVPlayer.
@MainActor
final class NoopPlaybackBackend: PlaybackBackend {
    var onTrackActivated: ((String, Int) -> Void)?
    var onPlaybackStateChange: ((Int, Int, String) -> Void)?
    var onPositionUpdate: ((TimeInterval, TimeInterval, Int, String) -> Void)?
    var onTrackEnded: ((Int, String) -> Void)?
    var onError: ((Int, Int, String) -> Void)?
    var onRemoteCommand: ((PlaybackRemoteCommand) -> Void)?
    var onRecoveryRequired: (() -> Void)?

    func loadVideo(id: String, startSeconds: TimeInterval, generation: Int, shouldPlay: Bool) {
        self.onError?(-1, generation, id)
    }
    func play() {}
    func pause() {}
    func seek(to position: TimeInterval) {}
    func resetForSignOut() {}
}
#endif
