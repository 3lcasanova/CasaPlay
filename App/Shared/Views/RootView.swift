// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

/// Apple TV and iPhone use tabs. iPad uses a sidebar.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(TorrentCenter.self) private var torrents
    @Environment(\.scenePhase) private var scenePhase
    #if !os(tvOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        @Bindable var state = app

        navigation
            .fullScreenCover(item: $state.playing) { item in
                PlayerScreen(item: item)
            }
            .task { torrents.start() }
            .onChange(of: scenePhase) { _, phase in
                // Apps can't keep peer connections open after suspension; save and close instead.
                switch phase {
                case .active: torrents.start()
                case .background: torrents.suspend()
                default: break
                }
            }
            .onOpenURL { url in
                Task { await openTorrentLink(url) }
            }
    }

    private var selection: Binding<AppSection> {
        Binding(
            get: { app.selectedSection },
            set: { app.selectedSection = $0 }
        )
    }

    @ViewBuilder
    private var navigation: some View {
        #if os(tvOS)
        tabs
        #else
        if sizeClass == .regular {
            sidebar
        } else {
            tabs
        }
        #endif
    }

    private var tabs: some View {
        TabView(selection: selection) {
            ForEach(AppSection.allCases) { section in
                sectionView(section)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(section)
            }
        }
    }

    #if !os(tvOS)
    private var sidebar: some View {
        let optionalSelection = Binding<AppSection?>(
            get: { app.selectedSection },
            set: { newValue in
                if let newValue { app.selectedSection = newValue }
            }
        )
        return NavigationSplitView {
            List(AppSection.allCases, selection: optionalSelection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .scrollingScreenTitle("CasaPlay")
        } detail: {
            sectionView(app.selectedSection)
        }
    }
    #endif

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .home: HomeView()
        case .search: SearchView()
        case .movies: LibraryView(mode: .all)
        case .favorites: LibraryView(mode: .favorites)
        case .torrents: TorrentsView()
        case .extensions: ExtensionsView()
        case .servers: ServersView()
        case .profile: ProfileView()
        }
    }

    /// magnet: links and .torrent files opened from other apps (iPhone and iPad).
    private func openTorrentLink(_ url: URL) async {
        if url.scheme?.lowercased() == "magnet" {
            _ = await torrents.add(magnet: url.absoluteString)
        } else if url.isFileURL, url.pathExtension.lowercased() == "torrent" {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 * 1024 * 1024,
                  let data = try? Data(contentsOf: url) else { return }
            _ = await torrents.add(torrentFile: data)
        } else {
            return
        }
        app.selectedSection = .torrents
    }
}
