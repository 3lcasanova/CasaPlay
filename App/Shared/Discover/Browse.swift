// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// What the category tiles on Movies and Series stand for, and the state behind the poster grid:
// one growing list per category (loaded a page at a time), TMDB search, and the episode badges.

import SwiftUI
import CasaPlayKit

/// One tile: a TMDB list that loads page by page.
struct BrowseCategory: Identifiable, Sendable {
    enum Badges: Sendable {
        /// A ribbon from the release date (films): IN 8 DAYS, NEW.
        case release
        /// An episode label and ribbon read from the show's latest and next episode.
        case episodes
    }

    let id: String
    let title: String
    let symbol: String
    let palette: TilePalette
    let badges: Badges
    let isShow: Bool
    let load: @Sendable (TMDBClient, Int) async throws -> [DiscoverTitle]

    /// Streaming catalogues and release dates are for this country.
    static let region = "CA"

    private static func movie(
        _ id: String, _ title: String, _ symbol: String, _ palette: TilePalette,
        _ load: @escaping @Sendable (TMDBClient, Int) async throws -> [TMDBMovie]
    ) -> BrowseCategory {
        BrowseCategory(id: "m-" + id, title: title, symbol: symbol, palette: palette,
                       badges: .release, isShow: false) { client, page in
            try await load(client, page).map(DiscoverTitle.init)
        }
    }

    private static func show(
        _ id: String, _ title: String, _ symbol: String, _ palette: TilePalette,
        _ load: @escaping @Sendable (TMDBClient, Int) async throws -> [TMDBShow]
    ) -> BrowseCategory {
        BrowseCategory(id: "tv-" + id, title: title, symbol: symbol, palette: palette,
                       badges: .episodes, isShow: true) { client, page in
            try await load(client, page).map(DiscoverTitle.init)
        }
    }

    /// TMDB watch-provider IDs for the services shown as "Trending on …" tiles. A service that only
    /// exists in the US (Hulu, Showtime, Starz, Peacock) is looked up in the US catalogue.
    private static let services: [(id: Int, name: String, palette: TilePalette, region: String)] = [
        (8, "Netflix", .ruby, region),
        (15, "Hulu", .lime, "US"),
        (119, "Prime Video", .sky, region),
        (1899, "HBO Max", .magenta, "US"),
        (37, "Showtime", .cyan, "US"),
        (43, "Starz", .rose, "US"),
        (337, "Disney+", .indigo, region),
        (350, "Apple TV+", .emerald, region),
        (230, "Crave", .teal, region),
        (531, "Paramount+", .violet, region),
        (386, "Peacock", .amber, "US")
    ]

    static let movies: [BrowseCategory] = {
        let from = discoverFromYear
        var list: [BrowseCategory] = [
            movie("popular", "Popular", "flame.fill", .ruby) { try await $0.discoverMovies(fromYear: from, page: $1) },
            movie("nowPlaying", "Now Playing", "ticket.fill", .amber) { try await $0.nowPlayingMovies(region: region, page: $1) },
            movie("upcoming", "Coming Soon", "calendar", .violet) { try await $0.upcomingMovies(region: region, page: $1) },
            movie("topRated", "Top Rated", "rosette", .emerald) { try await $0.discoverMovies(fromYear: from, sort: .rating, page: $1) },
            movie("trending", "Trending This Week", "chart.line.uptrend.xyaxis", .rose) { try await $0.trendingMovies(page: $1) }
        ]
        for service in services {
            let provider = service.id
            let country = service.region
            list.append(movie("on\(provider)", "Trending on \(service.name)", "play.tv.fill", service.palette) {
                try await $0.discoverMovies(fromYear: from, page: $1, provider: provider, watchRegion: country)
            })
        }
        list += [
            movie("anime", "Anime", "sparkles", .sunset) { try await $0.discoverMovies(genre: 16, language: "ja", fromYear: from, page: $1) },
            movie("action", "Action", "bolt.fill", .ruby) { try await $0.discoverMovies(genre: 28, fromYear: from, page: $1) },
            movie("comedy", "Comedy", "face.smiling.fill", .amber) { try await $0.discoverMovies(genre: 35, fromYear: from, page: $1) },
            movie("scifi", "Sci-Fi", "airplane", .indigo) { try await $0.discoverMovies(genre: 878, fromYear: from, page: $1) },
            movie("horror", "Horror", "moon.stars.fill", .graphite) { try await $0.discoverMovies(genre: 27, fromYear: from, page: $1) },
            movie("thriller", "Thriller", "eye.fill", .teal) { try await $0.discoverMovies(genre: 53, fromYear: from, page: $1) },
            movie("drama", "Drama", "theatermasks.fill", .violet) { try await $0.discoverMovies(genre: 18, fromYear: from, page: $1) },
            movie("family", "Family", "figure.2.and.child.holdinghands", .emerald) { try await $0.discoverMovies(genre: 10751, fromYear: from, page: $1) },
            movie("animation", "Animation", "paintpalette.fill", .sunset) { try await $0.discoverMovies(genre: 16, fromYear: from, page: $1) },
            movie("fantasy", "Fantasy", "wand.and.stars", .indigo) { try await $0.discoverMovies(genre: 14, fromYear: from, page: $1) },
            movie("romance", "Romance", "heart.fill", .rose) { try await $0.discoverMovies(genre: 10749, fromYear: from, page: $1) },
            movie("documentary", "Documentaries", "globe.americas.fill", .ocean) { try await $0.discoverMovies(genre: 99, fromYear: from, page: $1) }
        ]
        return list
    }()

    static let series: [BrowseCategory] = {
        let from = discoverFromYear
        var list: [BrowseCategory] = [
            show("airingToday", "New TV Tonight", "dot.radiowaves.left.and.right", .ruby) { try await $0.airingTodayTV(page: $1) },
            show("onTheAir", "On The Air This Week", "calendar.badge.clock", .amber) { try await $0.onTheAirTV(page: $1) },
            show("popular", "Popular", "flame.fill", .sunset) { try await $0.discoverTV(fromYear: from, page: $1) },
            show("topRated", "Top Rated", "rosette", .emerald) { try await $0.discoverTV(fromYear: from, sort: .rating, page: $1) },
            show("trending", "Trending This Week", "chart.line.uptrend.xyaxis", .rose) { try await $0.trendingTV(page: $1) }
        ]
        for service in services {
            let provider = service.id
            let country = service.region
            list.append(show("on\(provider)", "Trending on \(service.name)", "play.tv.fill", service.palette) {
                try await $0.discoverTV(fromYear: from, page: $1, provider: provider, watchRegion: country)
            })
        }
        list += [
            show("anime", "Anime", "sparkles", .violet) { try await $0.discoverTV(genre: 16, language: "ja", fromYear: from, page: $1) },
            show("action", "Action & Adventure", "bolt.fill", .ruby) { try await $0.discoverTV(genre: 10759, fromYear: from, page: $1) },
            show("scifi", "Sci-Fi & Fantasy", "airplane", .indigo) { try await $0.discoverTV(genre: 10765, fromYear: from, page: $1) },
            show("drama", "Drama", "theatermasks.fill", .violet) { try await $0.discoverTV(genre: 18, fromYear: from, page: $1) },
            show("comedy", "Comedy", "face.smiling.fill", .amber) { try await $0.discoverTV(genre: 35, fromYear: from, page: $1) },
            show("crime", "Crime", "magnifyingglass", .graphite) { try await $0.discoverTV(genre: 80, fromYear: from, page: $1) },
            show("mystery", "Mystery", "eye.fill", .teal) { try await $0.discoverTV(genre: 9648, fromYear: from, page: $1) },
            show("animation", "Animation", "paintpalette.fill", .sunset) { try await $0.discoverTV(genre: 16, fromYear: from, page: $1) },
            show("kids", "Kids", "teddybear.fill", .emerald) { try await $0.discoverTV(genre: 10762, fromYear: from, page: $1) },
            show("reality", "Reality", "camera.fill", .rose) { try await $0.discoverTV(genre: 10764, fromYear: from, page: $1) },
            show("documentary", "Documentaries", "globe.americas.fill", .ocean) { try await $0.discoverTV(genre: 99, fromYear: from, page: $1) }
        ]
        return list
    }()
}

/// The titles loaded so far for each category, and TMDB search results.
@Observable
final class BrowseModel {
    struct Listing {
        var titles: [DiscoverTitle] = []
        var nextPage = 1
        var ended = false
        var failure: String?
    }

    /// A category has no entry until its first page has been asked for.
    private(set) var listings: [String: Listing] = [:]
    private(set) var loading: Set<String> = []

    private(set) var searchResults: [DiscoverTitle] = []
    private(set) var isSearching = false
    private var searchToken = UUID()

    /// Pages stop after this many, which is far more than anyone scrolls.
    private static let lastPage = 25

    func listing(_ id: String) -> Listing {
        listings[id] ?? Listing()
    }

    func isLoading(_ id: String) -> Bool {
        loading.contains(id)
    }

    /// Loads a category the first time it is shown. A first page that failed is tried again.
    @MainActor
    func loadFirstPage(_ category: BrowseCategory, client: TMDBClient?) async {
        if let existing = listings[category.id], !(existing.titles.isEmpty && !existing.ended) { return }
        await loadNextPage(category, client: client, retrying: true)
    }

    /// Adds the next page of a category. Does nothing while a page is loading, once the list has ended,
    /// or after a failure (the Retry button passes `retrying`).
    @MainActor
    func loadNextPage(_ category: BrowseCategory, client: TMDBClient?, retrying: Bool = false) async {
        guard let client, !loading.contains(category.id) else { return }
        var listing = listings[category.id] ?? Listing()
        guard !listing.ended, retrying || listing.failure == nil else { return }
        loading.insert(category.id)
        defer { loading.remove(category.id) }
        do {
            let batch = try await category.load(client, listing.nextPage)
            listing.titles = DiscoverFeed.merged([listing.titles, DiscoverFeed.recent(batch)])
            listing.nextPage += 1
            listing.ended = batch.isEmpty || listing.nextPage > Self.lastPage
            listing.failure = nil
        } catch {
            // Scrolling away cancels the request; that isn't a failure, so the page is asked for again later.
            if Task.isCancelled { return }
            listing.failure = error.localizedDescription
        }
        listings[category.id] = listing
    }

    /// Searches TMDB for films or shows. Results are not limited to 2020 on: someone searching wants that title.
    @MainActor
    func search(_ query: String, isShow: Bool, client: TMDBClient?) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = UUID()
        searchToken = token
        guard text.count >= 2, let client else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        var found: [DiscoverTitle] = []
        do {
            if isShow {
                found = try await client.searchTV(query: text).map(DiscoverTitle.init)
            } else {
                found = try await client.searchMovies(query: text).map(DiscoverTitle.init)
            }
        } catch {
            found = []
        }
        guard searchToken == token, !Task.isCancelled else { return }
        searchResults = DiscoverFeed.merged([found])
        isSearching = false
    }
}

/// Episode badges for shows, fetched one show at a time as its card comes on screen.
@Observable
final class AirInfoCache {
    private(set) var badges: [Int: EpisodeBadge] = [:]
    @ObservationIgnored private var requested: Set<Int> = []

    func badge(for tmdbID: Int) -> EpisodeBadge? {
        badges[tmdbID]
    }

    @MainActor
    func load(_ tmdbID: Int, client: TMDBClient?) async {
        guard let client, requested.insert(tmdbID).inserted else { return }
        do {
            let info = try await client.showAirInfo(id: tmdbID)
            if let badge = info.badge() { badges[tmdbID] = badge }
        } catch {
            // Try again the next time the card appears.
            requested.remove(tmdbID)
        }
    }
}
