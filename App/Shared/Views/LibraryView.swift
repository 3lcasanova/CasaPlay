// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Movies and Series. Big colourful category tiles across the top pick a list; the poster grid below
// shows it, a page at a time. The first tiles are your own library and favorites (when you have any),
// then TMDB lists, streaming services and genres. A show is a library card with a TMDB show ID,
// so the two tabs split the library by that.

import SwiftUI
import CasaPlayKit

struct LibraryView: View {
    enum Mode {
        case movies, series
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
    @State private var selection: String?
    @State private var model = BrowseModel()
    @State private var airInfo = AirInfoCache()

    private static let libraryID = "library"
    private static let favoritesID = "favorites"

    private var opener: DiscoverOpener {
        DiscoverOpener(app: app,
                       push: { path.append($0) },
                       setBusy: { isOpening = $0 },
                       setError: { openError = $0 })
    }

    // MARK: What is shown

    private var isShow: Bool { mode == .series }
    private var screenTitle: String { isShow ? "Series" : "Movies" }
    private var categories: [BrowseCategory] { isShow ? BrowseCategory.series : BrowseCategory.movies }

    private func belongs(_ item: MediaItem) -> Bool {
        (item.tmdbShowID != nil) == isShow
    }

    private var ownItems: [MediaItem] { app.library.filter(belongs) }
    private var favoriteItems: [MediaItem] { app.favorites.filter(belongs) }

    /// Resolution and HDR come from the video file, which a show card doesn't have.
    private var filters: [Filter] {
        isShow ? [.all, .unwatched] : Filter.allCases
    }

    /// The tile that is on. With nothing chosen yet it is your library if you have one, else the first list.
    private var activeID: String {
        if let selection {
            if selection == Self.libraryID && !ownItems.isEmpty { return selection }
            if selection == Self.favoritesID && !favoriteItems.isEmpty { return selection }
            if categories.contains(where: { $0.id == selection }) { return selection }
        }
        return ownItems.isEmpty ? categories[0].id : Self.libraryID
    }

    private var activeCategory: BrowseCategory? {
        categories.first { $0.id == activeID }
    }

    private var searchText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Changes when the tile or the TMDB key changes, which is when the first page needs loading.
    private var loadKey: String {
        "\(activeID)|\(app.tmdbClient == nil)"
    }

    private func visible(_ items: [MediaItem]) -> [MediaItem] {
        items
            .filter { filter.matches($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Screen

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(14)) {
                    rail

                    if app.tmdbClient == nil && ownItems.isEmpty {
                        TMDBKeyNotice()
                    }

                    if let openError {
                        Text(openError)
                            .font(.casa(13))
                            .foregroundStyle(.red)
                            .padding(.horizontal, PremiumGrid.edge)
                            .focusableOnTV()
                    }

                    results
                }
                .padding(.bottom, Metrics.sectionSpacing)
            }
            .tvFullWidth()
            .screenBackground()
            .overlay {
                if isOpening {
                    ProgressView().tint(Theme.accent)
                }
            }
            .task(id: loadKey) {
                if let category = activeCategory {
                    await model.loadFirstPage(category, client: app.tmdbClient)
                }
            }
            .task(id: query) {
                if !searchText.isEmpty {
                    do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
                }
                await model.search(query, isShow: isShow, client: app.tmdbClient)
            }
            .scrollingScreenTitle(screenTitle)
            .searchable(text: $query)
            .navigationDestination(for: UUID.self) { id in
                DetailView(itemID: id)
            }
        }
    }

    // MARK: Category tiles

    private var rail: some View {
        CategoryRail {
            if !ownItems.isEmpty {
                tile(id: Self.libraryID, title: isShow ? "My Shows" : "My Library",
                     symbol: "square.stack.fill", palette: .amber)
            }
            if !favoriteItems.isEmpty {
                tile(id: Self.favoritesID, title: "Favorites", symbol: "heart.fill", palette: .rose)
            }
            ForEach(categories) { category in
                tile(id: category.id, title: category.title, symbol: category.symbol, palette: category.palette)
            }
        }
    }

    private func tile(id: String, title: String, symbol: String, palette: TilePalette) -> some View {
        Button {
            query = ""
            selection = id
        } label: {
            CategoryTile(title: title, symbol: symbol, palette: palette,
                         isSelected: searchText.isEmpty && activeID == id)
        }
        .premiumCardStyle(focusScale: 1.06)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if !searchText.isEmpty {
            searchSection
        } else if activeID == Self.libraryID {
            libraryGrid(title: isShow ? "My Shows" : "My Library", items: ownItems, filterable: true)
        } else if activeID == Self.favoritesID {
            libraryGrid(title: "Favorites", items: favoriteItems, filterable: false)
        } else if let category = activeCategory {
            categoryGrid(category)
        }
    }

    @ViewBuilder
    private func libraryGrid(title: String, items: [MediaItem], filterable: Bool) -> some View {
        PremiumSectionHeader(title: title, detail: "\(items.count)")
        if filterable {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.s(8)) {
                    ForEach(filters) { option in
                        ChipButton(title: option.rawValue, isSelected: option == filter) {
                            filter = option
                        }
                    }
                }
                .padding(.horizontal, PremiumGrid.edge)
                .padding(.vertical, Platform.isTV ? 14 : 0)
            }
        }
        let shown = filterable ? visible(items) : items
        if shown.isEmpty {
            ContentUnavailableView("Nothing found", systemImage: isShow ? "tv" : "film",
                                   description: Text("Try a different filter."))
                .frame(maxWidth: .infinity)
                .padding(.top, Metrics.sectionSpacing)
        } else {
            LazyVGrid(columns: PremiumGrid.columns, alignment: .leading, spacing: PremiumGrid.rowSpacing) {
                ForEach(shown) { item in
                    NavigationLink(value: item.id) {
                        PremiumPosterCard(item: item)
                    }
                    .premiumCardStyle()
                }
            }
            .padding(.horizontal, PremiumGrid.edge)
        }
    }

    @ViewBuilder
    private func categoryGrid(_ category: BrowseCategory) -> some View {
        let listing = model.listing(category.id)
        PremiumSectionHeader(title: category.title)
        if app.tmdbClient != nil {
            if listing.titles.isEmpty {
                if let failure = listing.failure {
                    failureView(failure) {
                        Task { await model.loadNextPage(category, client: app.tmdbClient, retrying: true) }
                    }
                } else if listing.ended {
                    ContentUnavailableView("Nothing here yet", systemImage: isShow ? "tv" : "film",
                                           description: Text("TMDB has no titles in this list right now."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, Metrics.sectionSpacing)
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Metrics.sectionSpacing)
                }
            } else {
                titleGrid(listing.titles, category: category)
                if let failure = listing.failure {
                    failureView(failure) {
                        Task { await model.loadNextPage(category, client: app.tmdbClient, retrying: true) }
                    }
                } else if !listing.ended {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        let text = searchText
        let mine = ownItems.filter { $0.title.localizedCaseInsensitiveContains(text) }
        if !mine.isEmpty {
            PremiumSectionHeader(title: "In your library", detail: "\(mine.count)")
            LazyVGrid(columns: PremiumGrid.columns, alignment: .leading, spacing: PremiumGrid.rowSpacing) {
                ForEach(mine) { item in
                    NavigationLink(value: item.id) {
                        PremiumPosterCard(item: item)
                    }
                    .premiumCardStyle()
                }
            }
            .padding(.horizontal, PremiumGrid.edge)
        }

        if app.tmdbClient != nil && text.count >= 2 {
            PremiumSectionHeader(title: "Results for “\(text)”")
            if model.searchResults.isEmpty {
                if model.isSearching {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Metrics.sectionSpacing)
                } else if mine.isEmpty {
                    ContentUnavailableView.search(text: text)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Metrics.sectionSpacing)
                }
            } else {
                titleGrid(model.searchResults, category: nil)
            }
        } else if mine.isEmpty {
            ContentUnavailableView.search(text: text)
                .frame(maxWidth: .infinity)
                .padding(.top, Metrics.sectionSpacing)
        }
    }

    private func failureView(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: Metrics.s(10)) {
            Text("Couldn't load this list. \(message)")
                .font(.casa(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            ChipButton(title: "Try again", isSelected: false, action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PremiumGrid.edge)
        .padding(.top, Metrics.s(10))
    }

    /// The poster grid. Scrolling near the end of a category asks for its next page.
    private func titleGrid(_ titles: [DiscoverTitle], category: BrowseCategory?) -> some View {
        let trailing = Set(titles.suffix(PremiumGrid.prefetch).map(\.id))
        return LazyVGrid(columns: PremiumGrid.columns, alignment: .leading, spacing: PremiumGrid.rowSpacing) {
            ForEach(titles) { title in
                Button { opener.open(title) } label: {
                    card(for: title)
                }
                .premiumCardStyle()
                .task(id: title.id) {
                    if title.isShow { await airInfo.load(title.tmdbID, client: app.tmdbClient) }
                }
                .onAppear {
                    if let category, trailing.contains(title.id) {
                        Task { await model.loadNextPage(category, client: app.tmdbClient) }
                    }
                }
            }
        }
        .padding(.horizontal, PremiumGrid.edge)
    }

    /// A film shows its year in the blue badge and, when it is new or coming soon, a ribbon with the date.
    /// A show shows its latest or next episode and a ribbon (TODAY, WEEKLY, IN 8 DAYS) once that is known.
    private func card(for title: DiscoverTitle) -> PremiumPosterCard {
        let year = title.year.map(String.init)
        if title.isShow {
            let badge = airInfo.badge(for: title.tmdbID)
            let label = badge?.label
            return PremiumPosterCard(title: title.title, subtitle: label == nil ? nil : year,
                                     posterPath: title.posterPath, rating: title.rating,
                                     badge: label ?? year, ribbon: badge?.ribbon)
        }
        return PremiumPosterCard(title: title.title, subtitle: nil,
                                 posterPath: title.posterPath, rating: title.rating,
                                 badge: year, ribbon: ReleaseDates.movieRibbon(releaseDate: title.releaseDate))
    }
}
