// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

/// Movies, Series and Favorites. Movies and Series share this screen: a show is a library card
/// with a TMDB show ID, so the two tabs just split the library by that.
struct LibraryView: View {
    enum Mode {
        case movies, series, favorites
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case fourK = "4K"
        case hdr = "HDR"
        case unwatched = "Unwatched"

        var id: String { rawValue }

        func matches(_ item: MediaItem) -> Bool {
            switch self {
            case .all: return true
            case .fourK: return item.file.is4K
            case .hdr: return item.file.hdr.isHDR
            case .unwatched: return !item.isWatched
            }
        }
    }

    @Environment(AppState.self) private var app
    let mode: Mode
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var path: [UUID] = []
    @State private var isOpening = false
    @State private var openError: String?

    private var opener: DiscoverOpener {
        DiscoverOpener(app: app,
                       push: { path.append($0) },
                       setBusy: { isOpening = $0 },
                       setError: { openError = $0 })
    }

    private var screenTitle: String {
        switch mode {
        case .movies: return "Movies"
        case .series: return "Series"
        case .favorites: return "Favorites"
        }
    }

    /// Resolution and HDR come from the video file, which a show card doesn't have.
    private var filters: [Filter] {
        mode == .series ? [.all, .unwatched] : Filter.allCases
    }

    /// TMDB titles that aren't already in the library, narrowed by the filter box.
    private func fresh(_ titles: [DiscoverTitle]) -> [DiscoverTitle] {
        let owned = Set(app.items.map { $0.title.lowercased() })
        return titles
            .filter { !owned.contains($0.title.lowercased()) }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// Popular films, shown below the library on the Movies tab.
    private var popular: [DiscoverTitle] {
        guard mode == .movies else { return [] }
        return fresh(app.discover.popularMovies)
    }

    /// Shelves of shows on the Series tab. A show only appears in the first shelf that has it.
    private var seriesShelves: [(title: String, titles: [DiscoverTitle])] {
        guard mode == .series else { return [] }
        var seen = Set<String>()
        func unique(_ list: [DiscoverTitle]) -> [DiscoverTitle] {
            fresh(list).filter { seen.insert($0.id).inserted }
        }
        return [
            ("Trending Shows", unique(app.discover.trendingTV)),
            ("Popular Shows", unique(app.discover.popularTV)),
            ("Top Rated Shows", unique(app.discover.topRatedTV))
        ]
    }

    private var visibleItems: [MediaItem] {
        let base: [MediaItem]
        switch mode {
        case .movies: base = app.library.filter { $0.tmdbShowID == nil }
        case .series: base = app.library.filter { $0.tmdbShowID != nil }
        case .favorites: base = app.favorites
        }
        return base
            .filter { filter.matches($0) }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.shelfSpacing, alignment: .top)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(14)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Metrics.s(8)) {
                            ForEach(filters) { option in
                                ChipButton(title: option.rawValue, isSelected: option == filter) {
                                    filter = option
                                }
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.vertical, Platform.isTV ? 14 : 0)
                    }

                    if mode != .favorites && app.tmdbClient == nil && app.items.isEmpty {
                        TMDBKeyNotice()
                    }

                    if let openError {
                        Text(openError)
                            .font(.casa(13))
                            .foregroundStyle(.red)
                            .padding(.horizontal, Metrics.screenPadding)
                    }

                    if visibleItems.isEmpty {
                        if mode == .favorites || !query.isEmpty || filter != .all {
                            ContentUnavailableView(
                                mode == .favorites && query.isEmpty ? "No favorites yet" : "Nothing found",
                                systemImage: mode == .favorites ? "heart" : (mode == .series ? "tv" : "film"),
                                description: Text(mode == .favorites && query.isEmpty
                                    ? "Tap the heart on a title to keep it here."
                                    : "Try a different search or filter.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, Metrics.sectionSpacing)
                        }
                    } else {
                        if mode != .favorites {
                            sectionTitle(mode == .series ? "Your Shows" : "Your Library")
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.sectionSpacing / 2) {
                            ForEach(visibleItems) { item in
                                NavigationLink(value: item.id) {
                                    PosterCard(item: item)
                                }
                                .posterButtonStyle()
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                    }

                    if !popular.isEmpty && filter == .all {
                        sectionTitle("Popular Movies")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.sectionSpacing / 2) {
                            ForEach(popular) { title in
                                Button { opener.open(title) } label: {
                                    TitlePosterCard(
                                        title: title.title,
                                        year: title.year,
                                        posterPath: title.posterPath,
                                        rating: title.rating.map { String(format: "★ %.1f", $0) }
                                    )
                                }
                                .posterButtonStyle()
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                    }

                    if filter == .all {
                        ForEach(seriesShelves, id: \.title) { shelf in
                            DiscoverShelf(title: shelf.title, titles: shelf.titles) { opener.open($0) }
                        }
                    }
                }
                .padding(.bottom, Metrics.sectionSpacing)
            }
            .screenBackground()
            .overlay {
                if isOpening {
                    ProgressView().tint(Theme.accent)
                }
            }
            .task(id: app.tmdbClient == nil) {
                await app.discover.loadIfNeeded(app.tmdbClient)
            }
            .scrollingScreenTitle(screenTitle)
            .searchable(text: $query)
            .navigationDestination(for: UUID.self) { id in
                DetailView(itemID: id)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.casa(19, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Metrics.screenPadding)
    }
}
