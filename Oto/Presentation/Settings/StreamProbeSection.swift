#if DEBUG && OTO_STREAM_PROBE
import SwiftUI
import OtoCore

/// Mục Debug để chủ dự án tự bấm đo M2 cho bài đang phát. Chỉ hiện tóm tắt, không hiện URL.
struct StreamProbeSection: View {
    let playerVM: PlayerViewModel
    let client: YTMusicClient
    @State private var lines: [String] = []
    @State private var isRunning = false

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
    }

    private var currentVideoID: String? {
        guard let id = self.playerVM.currentSong?.id, YTMusicClient.isValidVideoID(id) else { return nil }
        return id
    }

    private func runProbe() {
        guard let videoID = self.currentVideoID else { return }
        self.isRunning = true
        self.lines = []
        Task { @MainActor in
            for variant in [StreamProbeVariant.iphone, .safariMac] {
                let result = await self.client.probePlayer(videoId: videoID, variant: variant)
                self.lines.append(result.summary.logLine(variant: variant))
            }
            self.isRunning = false
        }
    }
}
#endif
