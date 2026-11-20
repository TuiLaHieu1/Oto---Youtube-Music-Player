import Testing
import Foundation
@testable import Oto
@testable import OtoCore

/// SessionStore.shared.signOut() xóa mọi HomeViewModel đang sống; các suite dùng nó phải chạy tuần tự.
@Suite("Trạng thái phiên dùng chung", .serialized)
struct SharedSessionStateTests {}

extension SharedSessionStateTests {
@Suite("SessionStore Lifecycle & Cache Cleaning Tests", .serialized)
struct SessionStoreTests {
    @Test("registerResetHandler executes registered handlers on signOut")
    @MainActor
    func testSignOutExecutesResetHandlers() async {
        let store = SessionStore.shared
        var handlerCalled = false

        store.registerResetHandler {
            handlerCalled = true
        }

        let initialGen = store.sessionGeneration
        await store.signOut()

        #expect(handlerCalled == true)
        #expect(store.sessionGeneration == initialGen + 1)
        #expect(store.isAuthenticated == false)
    }

    @Test("HomeViewModel registers reset handler and clears memory on signOut")
    @MainActor
    func testHomeViewModelClearsStateOnSignOut() async {
        await HomeCache.shared.clear()

        let homeVM = HomeViewModel()
        await homeVM.loadCachedData()

        let song = Song(id: "h1", title: "Home Song", artist: "Artist", duration: 120)
        homeVM.quickPicks = [song]
        homeVM.listenAgain = [song]
        homeVM.recentlyPlayed = [song]

        #expect(!homeVM.quickPicks.isEmpty)

        // Thực hiện sign out
        await SessionStore.shared.signOut()

        // Memory cache của HomeViewModel đã được xóa sạch
        #expect(homeVM.quickPicks.isEmpty)
        #expect(homeVM.listenAgain.isEmpty)
        #expect(homeVM.recentlyPlayed.isEmpty)
    }
}
}
