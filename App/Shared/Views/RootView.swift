// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

/// Apple TV and iPhone use tabs. iPad uses a sidebar.
struct RootView: View {
    @Environment(AppState.self) private var app
    #if !os(tvOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        @Bindable var state = app

        navigation
            .fullScreenCover(item: $state.playing) { item in
                PlayerScreen(item: item)
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
            .navigationTitle("CasaPlay")
        } detail: {
            sectionView(app.selectedSection)
        }
    }
    #endif

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .home: HomeView()
        case .movies: LibraryView(mode: .all)
        case .favorites: LibraryView(mode: .favorites)
        case .sources: SourcesView()
        case .profile: ProfileView()
        }
    }
}
