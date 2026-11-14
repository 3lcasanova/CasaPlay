// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
#if os(tvOS)
import TVServices
#endif

@main
struct CasaPlayApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(TorrentCenter.shared)
                .environment(ExtensionCenter.shared)
                .environment(ServerCenter.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    #if os(tvOS)
                    // Each time the app opens, ask tvOS to refresh the Top Shelf above the app row.
                    TVTopShelfContentProvider.topShelfContentDidChange()
                    #endif
                }
        }
    }
}
