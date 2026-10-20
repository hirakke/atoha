import SwiftUI

@main
struct AtohaWatchApp: App {
    @StateObject private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(store)
                .tint(Theme.accent)
                .task { store.activate() }
        }
    }
}
