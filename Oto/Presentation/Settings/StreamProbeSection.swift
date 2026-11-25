#if DEBUG && OTO_STREAM_PROBE
import OSLog
import SwiftUI
import OtoCore

/// Mục Debug để chủ dự án tự bấm đo M2 cho bài đang phát. Chỉ hiện tóm tắt, không hiện URL.
struct StreamProbeSection: View {
    let playerVM: PlayerViewModel
    let client: YTMusicClient
    @State private var lines: [String] = []
    @State private var isRunning = false
    @State private var probeTask: Task<Void, Never>?
    @State private var resolved: (videoID: String, url: URL)?

    init(playerVM: PlayerViewModel, client: YTMusicClient = .shared) {
        self.playerVM = playerVM
        self.client = client
    }

    var body: some View {
        Section("Khảo sát stream · Debug") {
            Button(self.isRunning ? "Đang đo…" : "Đo player cho bài đang phát (M2)") {
                self.runProbe()
            }
            .disabled(self.isRunning || self.currentVideoID == nil)
            Button("Bước 1: lấy URL M4A bằng yt-dlp") {
                self.runYtdlp()
            }
            .disabled(self.isRunning || self.currentVideoID == nil)
            Button("Bước 2: phát bài này bằng AVPlayer") {
                self.playWithAVPlayer()
            }
            .disabled(self.isRunning || self.resolved == nil || self.resolved?.videoID != self.currentVideoID)
            if self.currentVideoID == nil {
                Text("Cần phát một bài YouTube Music trước.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(self.lines, id: \.self) { line in
                Text(line)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .onDisappear {
            self.probeTask?.cancel()
            self.probeTask = nil
            self.isRunning = false
        }
    }

    private var currentVideoID: String? {
        guard let id = self.playerVM.currentSong?.id, YTMusicClient.isValidVideoID(id) else { return nil }
        return id
    }

    private func runYtdlp() {
        guard let videoID = self.currentVideoID else { return }
        self.isRunning = true
        self.lines = []
        self.probeTask = Task { @MainActor in
            let result = await PythonStreamResolver.resolve(videoID: videoID)
            guard !Task.isCancelled else { return }
            self.lines.append(result.logLine)
            if let url = result.url {
                self.resolved = (videoID, url)
                self.lines.append(await Self.fetchCheck(url))
            }
            self.isRunning = false
            self.probeTask = nil
        }
    }

    /// Tải 64 KB đầu để xác nhận URL dùng được; chỉ ghi mã trạng thái, số byte và kiểu nội dung.
    static func fetchCheck(_ url: URL) async -> String {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20
        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let type = http?.value(forHTTPHeaderField: "Content-Type") == "audio/mp4" ? "audio/mp4" : "other"
            let line = String(
                format: "YtdlpFetch status=%d bytes=%d type=%@ seconds=%.1f",
                http?.statusCode ?? -1, data.count, type, Date().timeIntervalSince(started)
            )
            StreamProbeLog.write(line)
            return line
        } catch {
            return "YtdlpFetch error=\(StreamProbeRequestError(error).rawValue)"
        }
    }

    private func playWithAVPlayer() {
        guard let resolved = self.resolved, resolved.videoID == self.currentVideoID,
              let index = self.playerVM.queueManager.currentIndex else { return }
        StreamProbeOverride.set(resolved.url, for: resolved.videoID)
        self.playerVM.playQueueItem(at: index)
        self.lines.append("Đang phát bằng AVPlayer. Lọc log 'StreamProbe avplayer' trong Console.")
    }

    private func runProbe() {
        guard let videoID = self.currentVideoID else { return }
        self.isRunning = true
        self.lines = []
        self.probeTask = Task { @MainActor in
            for variant in [StreamProbeVariant.iphone, .safariMac] {
                guard !Task.isCancelled else { break }
                let result = await self.client.probePlayer(videoId: videoID, variant: variant)
                guard !Task.isCancelled else { break }
                self.lines.append(result.summary.logLine(variant: variant))
            }
            self.isRunning = false
            self.probeTask = nil
        }
    }
}
#endif
