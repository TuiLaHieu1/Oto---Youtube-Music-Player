#if DEBUG && OTO_STREAM_PROBE
import SwiftUI
import OtoCore

/// Mục Debug để chủ dự án tự bấm đo M2 cho bài đang phát. Chỉ hiện tóm tắt, không hiện URL.
struct StreamProbeSection: View {
    let playerVM: PlayerViewModel
    let client: YTMusicClient
    @State private var lines: [String] = []
    @State private var isRunning = false
    @State private var probeTask: Task<Void, Never>?

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
