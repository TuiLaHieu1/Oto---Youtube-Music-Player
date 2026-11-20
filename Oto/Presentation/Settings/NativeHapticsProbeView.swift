#if DEBUG && os(iOS) && OTO_HAPTICS_PILOT
import SwiftUI
import AVFoundation
import MediaAccessibility
import MediaPlayer
import UIKit
import UniformTypeIdentifiers
import os

@available(iOS 18.0, *)
@MainActor
struct NativeHapticsProbeView: View {
    let playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var showMusicPicker = false
    @State private var player: AVPlayer?
    @State private var session: MPNowPlayingSession?
    @State private var scopedURL: URL?
    @State private var statusToken: (any NSCopying)?
    @State private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @State private var result: String?
    @State private var playbackProbeID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Text("Chọn file audio đúng bản I'm Not the Only One trong album In the Lonely Hour (2014).")
                Button("Chọn từ thư viện Music") { showMusicPicker = true }
                Button("Chọn file và phát") { showImporter = true }
                if player != nil {
                    Button("Dừng phát", action: stop)
                }
                if let result { Text(verbatim: result) }
            }
            .navigationTitle("Music Haptics · Native")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .sheet(isPresented: $showMusicPicker) {
                HapticsMusicPicker { item in
                    showMusicPicker = false
                    guard let item else { return }
                    playPurchasedItem(item)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { selection in
                do {
                    try play(selection.get())
                } catch {
                    result = error.localizedDescription
                }
            }
        }
        .task(id: playbackProbeID) {
            guard playbackProbeID != nil, let player else { return }
            for delay in [2, 4] {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                reportPlayback(player)
            }
        }
        .onDisappear(perform: stop)
    }

    private func playPurchasedItem(_ item: MPMediaItem) {
        let sample = MusicHapticsPilotSample.song
        guard item.title?.compare(sample.title, options: [.caseInsensitive]) == .orderedSame,
              item.artist?.compare(sample.artist, options: [.caseInsensitive]) == .orderedSame,
              let album = sample.album,
              item.albumTitle?.compare(album, options: [.caseInsensitive]) == .orderedSame
        else {
            result = "Hãy chọn đúng bản Sam Smith trong album In the Lonely Hour."
            return
        }
        guard let url = item.assetURL, !item.hasProtectedAsset else {
            result = "Music chưa cung cấp audio cho Oto. Hãy kiểm tra bài đã tải xuống trong Music."
            return
        }
        do {
            try play(url)
        } catch {
            result = error.localizedDescription
        }
    }

    private func play(_ url: URL) throws {
        stop()
        playerVM.pause(reason: "nativeHapticsProbe")
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)

        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let player = AVPlayer(url: url)
        let session = MPNowPlayingSession(players: [player])
        session.automaticallyPublishesNowPlayingInfo = false
        let sample = MusicHapticsPilotSample.song
        session.nowPlayingInfoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: sample.title,
            MPMediaItemPropertyArtist: sample.artist,
            MPNowPlayingInfoPropertyMediaType: MPMediaType.music.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyInternationalStandardRecordingCode: MusicHapticsPilotSample.isrc
        ]
        self.player = player
        self.session = session
        let probeID = UUID()
        playbackProbeID = probeID
        registerRemoteCommands(for: session, probeID: probeID)
        let logger = Logger(subsystem: "com.oto.music", category: "MusicHapticsPilot")
        let report: @Sendable (String, Bool) -> Void = { code, active in
            logger.info("Haptics native status sample=\(code == MusicHapticsPilotSample.isrc) active=\(active)")
        }
        statusToken = MAMusicHapticsManager.shared.addStatusObserver(report)
        result = "ISRC \(MusicHapticsPilotSample.isrc) · AVPlayer"
        player.play()
        session.becomeActiveIfPossible { @Sendable active in
            logger.info("Haptics native Now Playing active=\(active)")
        }
    }

    private func registerRemoteCommands(for session: MPNowPlayingSession, probeID: UUID) {
        let commands = session.remoteCommandCenter
        for (command, shouldPlay) in [(commands.playCommand, true), (commands.pauseCommand, false)] {
            command.isEnabled = true
            let token = command.addTarget { @Sendable _ in
                Task { @MainActor in
                    guard playbackProbeID == probeID, let player = self.player, let session = self.session,
                          player.currentItem != nil else { return }
                    if shouldPlay { player.play() } else { player.pause() }
                    let center = session.nowPlayingInfoCenter
                    if var info = center.nowPlayingInfo {
                        info[MPNowPlayingInfoPropertyPlaybackRate] = shouldPlay ? 1.0 : 0.0
                        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
                        center.nowPlayingInfo = info
                    }
                }
                return .success
            }
            remoteTargets.append((command, token))
        }
    }

    private func reportPlayback(_ player: AVPlayer) {
        let position = player.currentTime().seconds
        let item = player.currentItem
        let duration = item?.duration.seconds ?? 0
        if duration.isFinite, duration > 0, position.isFinite,
           let center = session?.nowPlayingInfoCenter, var info = center.nowPlayingInfo {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
            info[MPNowPlayingInfoPropertyPlaybackRate] = Double(player.rate)
            center.nowPlayingInfo = info
        }
        let error = (item?.error ?? player.error) as NSError?
        let status = item?.status.rawValue ?? -1
        let message = """
            Haptics native audio position=\(String(format: "%.2f", position)) \
            duration=\(String(format: "%.2f", duration)) \
            playing=\(player.timeControlStatus == .playing) itemStatus=\(status) \
            error=\(error?.domain ?? "none")/\(error?.code ?? 0)
            """
        Logger(subsystem: "com.oto.music", category: "MusicHapticsPilot").info("\(message, privacy: .public)")
        result = message
    }

    private func stop() {
        playbackProbeID = nil
        for (command, token) in remoteTargets { command.removeTarget(token) }
        remoteTargets.removeAll()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        session?.nowPlayingInfoCenter.nowPlayingInfo = nil
        session = nil
        player = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        if let statusToken { MAMusicHapticsManager.shared.removeStatusObserver(statusToken) }
        statusToken = nil
    }
}
private struct HapticsMusicPicker: UIViewControllerRepresentable {
    let onSelection: (MPMediaItem?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onSelection: (MPMediaItem?) -> Void

        init(onSelection: @escaping (MPMediaItem?) -> Void) { self.onSelection = onSelection }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems items: MPMediaItemCollection) {
            onSelection(items.items.first)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) { onSelection(nil) }
    }
}
#endif
