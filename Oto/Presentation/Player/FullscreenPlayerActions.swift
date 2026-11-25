import SwiftUI
import UIKit
import OtoCore

struct FullscreenHeaderBar<Mode: View, Controls: View, Actions: View>: View {
    @Binding var isExpanded: Bool
    var playingFromTitle: String = "Quick Picks"
    var extraControlCount = 0
    @ViewBuilder var mode: () -> Mode
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        let spacing: CGFloat = 8
        let sideWidth = OtoTheme.minTouchTarget * CGFloat(extraControlCount + 1)
            + spacing * CGFloat(extraControlCount)
        HStack(spacing: spacing) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(OtoTheme.smoothSpring) {
                    isExpanded = false
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(OtoTheme.secondaryText)
                    .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .frame(width: sideWidth, alignment: .leading)

            VStack(spacing: 2) {
                if !playingFromTitle.isEmpty {
                    Text("PLAYING FROM")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(OtoTheme.secondaryText)
                    Text(LocalizedStringKey(playingFromTitle))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OtoTheme.primaryText)
                        .lineLimit(1)
                }
                mode()
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: spacing) {
                controls()

                Menu(content: actions) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OtoTheme.secondaryText)
                        .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn bài hát")
            }
            .frame(width: sideWidth, alignment: .trailing)
        }
        .padding(.horizontal, OtoTheme.spacing16)
        .padding(.top, OtoTheme.spacing8)
    }
}

struct PlayerAlbumLookup: View {
    let song: Song
    let playerVM: PlayerViewModel
    @State private var album: Album?
    @State private var finished = false
    @State private var failed = false

    var body: some View {
        Group {
            if let album {
                AlbumDetailView(browseId: album.id, initialAlbum: album, playerVM: playerVM)
            } else if finished {
                Text(failed
                    ? LocalizedStringKey("Không thể tải album")
                    : LocalizedStringKey("Không tìm thấy album chứa bài này"))
                    .padding()
            } else {
                ProgressView("Đang tải thông tin album...")
            }
        }
        .task { await findAlbum() }
    }

    private func findAlbum() async {
        guard let title = song.album else {
            finished = true
            return
        }
        let client = YTMusicClient.shared
        do {
            let page = try await client.searchMusic(query: "\(title) \(song.artist)", scope: .albums)
            let results = [page.topResult].compactMap { $0 } + page.results
            var checked = Set<String>()
            for result in results {
                guard case .album(let candidate) = result,
                      candidate.title.compare(
                        title, options: [.caseInsensitive, .diacriticInsensitive]
                      ) == .orderedSame,
                      checked.insert(candidate.id).inserted else { continue }
                let detail = try await client.fetchAlbumDetail(browseId: candidate.id)
                try Task.checkCancellation()
                if detail.songs.contains(where: { $0.id == song.id }) {
                    album = detail
                    break
                }
                if checked.count == 3 { break }
            }
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
        finished = true
    }
}

struct AmbientBackgroundView: View {
    let artworkURL: URL?
    let size: CGSize

    var body: some View {
        ZStack {
            OtoTheme.background.ignoresSafeArea()

            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .blur(radius: 50)
                            .opacity(0.50)
                            .transition(.opacity)
                    default:
                        Color.clear
                    }
                }
                .id(artworkURL)
                .animation(.easeInOut(duration: 0.35), value: artworkURL)
                .ignoresSafeArea()
            }

            RadialGradient(
                colors: [OtoTheme.atmosphere.opacity(0.72), .clear],
                center: .topLeading, startRadius: 0, endRadius: max(size.width, size.height) * 0.8
            )
            LinearGradient(
                colors: [.clear, OtoTheme.background.opacity(0.92)], startPoint: .center, endPoint: .bottom
            )
        }
    }
}

@MainActor
final class PlayerWindowOrientation {
    weak var anchor: UIView?

    func restorePortrait() {
        guard let scene = anchor?.window?.windowScene else { return }
        let isLandscape: Bool
        if #available(iOS 26, *) {
            isLandscape = scene.effectiveGeometry.interfaceOrientation.isLandscape
        } else {
            isLandscape = scene.interfaceOrientation.isLandscape
        }
        if isLandscape { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
    }

    func request(_ mask: UIInterfaceOrientationMask, onDenied: @escaping @MainActor () -> Void) {
        guard let scene = anchor?.window?.windowScene else {
            onDenied()
            return
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
            Task { @MainActor in onDenied() }
        }
    }
}

struct PlayerWindowAnchor: UIViewRepresentable {
    let orientation: PlayerWindowOrientation

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        orientation.anchor = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        orientation.anchor = uiView
    }
}

struct LyricsLayoutButton: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(OtoTheme.accent)
                .frame(minWidth: OtoTheme.minTouchTarget, minHeight: OtoTheme.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

struct WideLyricsPanel: View {
    let lyricsVM: LyricsViewModel
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        SyncedLyricsView(lyricsVM: lyricsVM, onSeek: onSeek)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                .fill(OtoTheme.surface.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous)
                        .stroke(OtoTheme.separator, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OtoTheme.cardRadius, style: .continuous))
    }
}

/// Chỉ hiện nút Video khi endpoint khớp ID đang phát và có loại video rõ ràng.
enum PlayerVideoAvailability {
    /// Có mặt hiển thị video: WebKit ở bản thường, AVPlayerLayer + manifest HLS ở bản khảo sát.
    static let hasVideoSurface = true

    static func availableID(for song: Song?) async -> String? {
        guard hasVideoSurface, let song, !song.isLocal,
              let data = try? await YTMusicClient.shared.fetchLyricsNext(videoId: song.id),
              YTMusicParsers.supportsVideo(in: data, id: song.id) else { return nil }
        return song.id
    }
}

@MainActor
enum PlayerArtistLinks {
    static func artistName(for song: Song?) -> String? {
        guard let name = song?.artist.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, !YTMusicParsers.isNonArtistLabel(name) else { return nil }
        return name
    }

    static func menuArtists(for song: Song) -> [ArtistReference] {
        var seen = Set<String>()
        return song.artists.filter {
            $0.browseId.hasPrefix("UC") && !$0.name.isEmpty && seen.insert($0.id).inserted
        }
    }
}

extension View {
    /// Bản khảo sát: đổi luồng AVPlayer theo chế độ Bài hát/Video và cấp player cho mặt video.
    /// Đóng trình phát toàn màn hình thì gỡ hình; tiếng vẫn phát liền mạch.
    /// Phải gắn ngoài `overlayPreferenceValue`, vì mặt video nằm trong overlay đó và cần đọc player từ environment.
    @ViewBuilder
    func probeVideoMode(_ playerVM: PlayerViewModel, showsVideo: Bool) -> some View {
        #if DEBUG && OTO_STREAM_PROBE
        self.environment(playerVM.probeVideoOutput)
            .onChange(of: showsVideo) { _, wantsVideo in playerVM.setProbeVideoMode(wantsVideo) }
            .onDisappear { playerVM.setProbeVideoMode(false) }
        #else
        self
        #endif
    }
}
