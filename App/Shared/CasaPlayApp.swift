// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI

@main
struct CasaPlayApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(TorrentCenter.shared)
                .environment(ExtensionCenter.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
