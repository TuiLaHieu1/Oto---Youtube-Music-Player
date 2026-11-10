import SwiftUI
import OtoCore

/// View gốc điều phối giao diện thích ứng thông minh giữa iPhone và iPadOS.
public struct RootView: View {
    @Bindable var playerVM: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: TabItem? = .home

    public enum TabItem: String, Hashable, CaseIterable {
        case home = "Trang chủ"
        case search = "Tìm kiếm"
        case library = "Thư viện"

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .search: return "magnifyingglass"
            case .library: return "square.stack.fill"
            }
        }
    }

    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }

    public var body: some View {
        ZStack {
            // Gắn SingletonPlayerWebView vào view hierarchy nền để WebKit luôn duy trì render âm thanh
            PlayerWebViewContainer()
                .frame(width: 320, height: 240)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(-1)

            mainContentView
        }
        .background(OtoTheme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $playerVM.isExpanded) {
            FullscreenPlayerView(playerVM: playerVM)
        }
        .sheet(isPresented: $playerVM.showAuth) {
            AuthView {
                Task { @MainActor in
                    SingletonPlayerWebView.shared.reloadAfterLogin()
                }
            }
        }
    }

    @ViewBuilder
    private var mainContentView: some View {
        if horizontalSizeClass == .regular {
            // Layout iPadOS (NavigationSplitView)
            NavigationSplitView {
                List(selection: $selectedTab) {
                    ForEach(TabItem.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .navigationTitle("Oto")
            } detail: {
                ZStack(alignment: .bottom) {
                    detailView(for: selectedTab ?? .home)
                    if shouldShowMiniPlayer {
                        MiniPlayerView(playerVM: playerVM)
                            .padding(.bottom, OtoTheme.spacing16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        } else {
            phoneLayout
        }
    }

    @ViewBuilder
    private var phoneLayout: some View {
        if #available(iOS 26.0, *) {
            phoneTabView
                .tabViewBottomAccessory {
                    miniPlayerAccessory
                }
        } else {
            phoneTabView
                .safeAreaInset(edge: .bottom, spacing: OtoTheme.spacing8) {
                    miniPlayerAccessory
                }
        }
    }

    private var phoneTabView: some View {
        TabView(selection: Binding(
            get: { selectedTab ?? .home },
            set: { selectedTab = $0 }
        )) {
            HomeFeedView(playerVM: playerVM)
                .tabItem {
                    Label(TabItem.home.rawValue, systemImage: TabItem.home.icon)
                }
                .tag(TabItem.home)

            SearchView(playerVM: playerVM)
                .tabItem {
                    Label(TabItem.search.rawValue, systemImage: TabItem.search.icon)
                }
                .tag(TabItem.search)

            LibraryView(playerVM: playerVM)
                .tabItem {
                    Label(TabItem.library.rawValue, systemImage: TabItem.library.icon)
                }
                .tag(TabItem.library)
        }
        .tint(OtoTheme.accent)
        .animation(OtoTheme.smoothSpring, value: playerVM.currentSong?.id)
    }

    private var shouldShowMiniPlayer: Bool {
        playerVM.currentSong != nil && playerVM.playbackState != .idle
    }

    @ViewBuilder
    private var miniPlayerAccessory: some View {
        if shouldShowMiniPlayer {
            MiniPlayerView(playerVM: playerVM)
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func detailView(for tab: TabItem) -> some View {
        switch tab {
        case .home:
            HomeFeedView(playerVM: playerVM)
        case .search:
            SearchView(playerVM: playerVM)
        case .library:
            LibraryView(playerVM: playerVM)
        }
    }
}
