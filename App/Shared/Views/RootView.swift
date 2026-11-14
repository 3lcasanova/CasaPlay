// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

/// Apple TV and iPhone use tabs. iPad uses a sidebar that can fold into tabs along the top (a plain sidebar before iPadOS 18).
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
            if #available(iOS 18.0, *) {
                AdaptiveTabs(selection: selection) { sectionView($0) }
            } else {
                sidebar
            }
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
        .appleTVSidebar()
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
        case .movies: LibraryView(mode: .movies)
        case .series: LibraryView(mode: .series)
        case .iptv: LiveTVView()
        case .extensions: ExtensionsView()
        case .servers: ServersView()
        case .profile: ProfileView()
        }
    }
}

#if !os(tvOS)

/// iPad, like the Apple TV app: a sidebar that is open to start with and can fold into tabs along the top.
/// "Edit" at the top of the sidebar lets people reorder or hide tabs, and their profile sits at the bottom.
@available(iOS 18.0, *)
private struct AdaptiveTabs<Content: View>: View {
    @Environment(AppState.self) private var app
    @Binding var selection: AppSection
    @AppStorage("CasaPlayTabCustomization") private var customization: TabViewCustomization
    let content: (AppSection) -> Content

    init(selection: Binding<AppSection>, @ViewBuilder content: @escaping (AppSection) -> Content) {
        _selection = selection
        self.content = content
    }

    var body: some View {
        TabView(selection: $selection) {
            tab(.home)
            tab(.movies)
            tab(.series)
            tab(.iptv)
            TabSection("More") {
                tab(.extensions)
                tab(.servers)
                tab(.profile)
            }
            .customizationID("casaplay.more")
        }
        .tabViewStyle(.sidebarAdaptable)
        .defaultAdaptableTabBarPlacement(.sidebar)
        .tabViewCustomization($customization)
        .tabViewSidebarBottomBar { profileRow }
    }

    private func tab(_ section: AppSection) -> some TabContent<AppSection> {
        Tab(section.title, systemImage: section.systemImage, value: section) {
            content(section)
        }
        .customizationID("casaplay." + section.rawValue)
    }

    /// "El Casanova · Switch Profile" at the bottom of the sidebar.
    private var profileRow: some View {
        Button {
            selection = .profile
        } label: {
            HStack(spacing: 12) {
                ProfileAvatar(profile: app.activeProfile, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.activeProfile.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text("Switch Profile")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile: \(app.activeProfile.name)")
    }
}

#endif
