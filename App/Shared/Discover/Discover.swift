// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Real titles from TMDB for Home, Movies and Series: trending, popular and top-rated lists.

import SwiftUI
import CasaPlayKit

struct DiscoverTitle: Identifiable, Hashable {
    let tmdbID: Int
    let isShow: Bool
    let title: String
    let year: Int?
    let posterPath: String?
    let backdropPath: String?
    let overview: String
    let rating: Double?
    /// Release date for a film, first air date for a show ("yyyy-MM-dd"), when TMDB has one.
    let releaseDate: String?

    var id: String { (isShow ? "tv-" : "movie-") + String(tmdbID) }

    init(_ m: TMDBMovie) {
        tmdbID = m.id; isShow = false; title = m.title; year = m.releaseYear
        posterPath = m.poster_path; backdropPath = m.backdrop_path
        overview = m.overview ?? ""; rating = m.vote_average
        releaseDate = m.release_date
    }

    init(_ s: TMDBShow) {
        tmdbID = s.id; isShow = true; title = s.name; year = s.firstAirYear
        posterPath = s.poster_path; backdropPath = s.backdrop_path
        overview = s.overview ?? ""; rating = s.vote_average
        releaseDate = s.first_air_date
    }
}

/// A shelf of TMDB titles beyond the core lists: new releases, genres and anime.
struct DiscoverRowSpec: Sendable {
    let id: String
    let title: String
    let isShow: Bool
    let fetch: @Sendable (TMDBClient) async throws -> [DiscoverTitle]

    static func movies(_ id: String, _ title: String,
                       _ load: @escaping @Sendable (TMDBClient) async throws -> [TMDBMovie]) -> DiscoverRowSpec {
        DiscoverRowSpec(id: "m-" + id, title: title, isShow: false) { try await load($0).map(DiscoverTitle.init) }
    }

    static func shows(_ id: String, _ title: String,
                      _ load: @escaping @Sendable (TMDBClient) async throws -> [TMDBShow]) -> DiscoverRowSpec {
        DiscoverRowSpec(id: "tv-" + id, title: title, isShow: true) { try await load($0).map(DiscoverTitle.init) }
    }
}

@Observable
final class DiscoverFeed {
    var trendingMovies: [DiscoverTitle] = []
    var trendingTV: [DiscoverTitle] = []
    var popularMovies: [DiscoverTitle] = []
    var topRated: [DiscoverTitle] = []
    var popularTV: [DiscoverTitle] = []
    var topRatedTV: [DiscoverTitle] = []
    var error: String?
    private(set) var isLoaded = false

    /// Extra shelves by row ID. A row has no entry until it has loaded.
    private(set) var extra: [String: [DiscoverTitle]] = [:]
    private var moreTask: Task<Void, Never>?

    /// Movie shelves, then show shelves, each in the order they appear on screen.
    /// Genre IDs are TMDB's. Anime is animation made in Japan. Everything is from 2020 on.
    static let rowSpecs: [DiscoverRowSpec] = [
        .movies("nowPlaying", "Now Playing") { try await $0.nowPlayingMovies(region: "CA") },
        .movies("upcoming", "Coming Soon") { try await $0.upcomingMovies(region: "CA") },
        .movies("anime", "Anime Movies") { try await $0.discoverMovies(genre: 16, language: "ja", fromYear: discoverFromYear) },
        .movies("action", "Action") { try await $0.discoverMovies(genre: 28, fromYear: discoverFromYear) },
        .movies("comedy", "Comedy") { try await $0.discoverMovies(genre: 35, fromYear: discoverFromYear) },
        .movies("animation", "Animation") { try await $0.discoverMovies(genre: 16, fromYear: discoverFromYear) },
        .movies("scifi", "Sci-Fi") { try await $0.discoverMovies(genre: 878, fromYear: discoverFromYear) },
        .movies("horror", "Horror") { try await $0.discoverMovies(genre: 27, fromYear: discoverFromYear) },
        .movies("thriller", "Thriller") { try await $0.discoverMovies(genre: 53, fromYear: discoverFromYear) },
        .movies("drama", "Drama") { try await $0.discoverMovies(genre: 18, fromYear: discoverFromYear) },
        .movies("family", "Family") { try await $0.discoverMovies(genre: 10751, fromYear: discoverFromYear) },
        .movies("fantasy", "Fantasy") { try await $0.discoverMovies(genre: 14, fromYear: discoverFromYear) },
        .movies("romance", "Romance") { try await $0.discoverMovies(genre: 10749, fromYear: discoverFromYear) },
        .movies("documentary", "Documentaries") { try await $0.discoverMovies(genre: 99, fromYear: discoverFromYear) },

        .shows("airingToday", "Airing Today") { try await $0.airingTodayTV() },
        .shows("onTheAir", "On The Air") { try await $0.onTheAirTV() },
        .shows("anime", "Anime Series") { try await $0.discoverTV(genre: 16, language: "ja", fromYear: discoverFromYear) },
        .shows("action", "Action & Adventure") { try await $0.discoverTV(genre: 10759, fromYear: discoverFromYear) },
        .shows("scifi", "Sci-Fi & Fantasy") { try await $0.discoverTV(genre: 10765, fromYear: discoverFromYear) },
        .shows("drama", "Drama") { try await $0.discoverTV(genre: 18, fromYear: discoverFromYear) },
        .shows("comedy", "Comedy") { try await $0.discoverTV(genre: 35, fromYear: discoverFromYear) },
        .shows("crime", "Crime") { try await $0.discoverTV(genre: 80, fromYear: discoverFromYear) },
        .shows("mystery", "Mystery") { try await $0.discoverTV(genre: 9648, fromYear: discoverFromYear) },
        .shows("animation", "Animation") { try await $0.discoverTV(genre: 16, fromYear: discoverFromYear) },
        .shows("kids", "Kids") { try await $0.discoverTV(genre: 10762, fromYear: discoverFromYear) },
        .shows("reality", "Reality") { try await $0.discoverTV(genre: 10764, fromYear: discoverFromYear) },
        .shows("documentary", "Documentaries") { try await $0.discoverTV(genre: 99, fromYear: discoverFromYear) }
    ]

    /// Only titles from `discoverFromYear` on are shown. A title with no date is kept.
    static func recent(_ titles: [DiscoverTitle]) -> [DiscoverTitle] {
        titles.filter { ($0.year ?? discoverFromYear) >= discoverFromYear }
    }

    /// Lists joined in order, without repeats.
    static func merged(_ lists: [[DiscoverTitle]]) -> [DiscoverTitle] {
        var seen = Set<String>()
        return lists.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    /// The titles of one extra shelf, or none until it has loaded.
    func titles(_ id: String) -> [DiscoverTitle] {
        extra[id] ?? []
    }

    /// The loaded extra shelves for movies or for shows, in screen order. Empty ones are left out.
    func rows(shows: Bool) -> [(title: String, titles: [DiscoverTitle])] {
        Self.rowSpecs.filter { $0.isShow == shows }.compactMap { spec in
            guard let list = extra[spec.id], !list.isEmpty else { return nil }
            return (spec.title, list)
        }
    }

    /// Loads the extra shelves that haven't loaded yet. They fill in one by one, and a failed one is
    /// tried again the next time a screen asks. Not tied to a screen, so switching tabs doesn't stop it.
    @MainActor
    func loadMoreIfNeeded(_ client: TMDBClient) {
        guard moreTask == nil else { return }
        let missing = Self.rowSpecs.filter { extra[$0.id] == nil }
        guard !missing.isEmpty else { return }
        moreTask = Task { @MainActor in
            await withTaskGroup(of: (String, [DiscoverTitle]?).self) { group in
                for spec in missing {
                    group.addTask { (spec.id, try? await spec.fetch(client)) }
                }
                for await (id, list) in group {
                    if let list { self.extra[id] = Self.recent(list) }
                }
            }
            self.moreTask = nil
        }
    }

    @MainActor
    func loadIfNeeded(_ client: TMDBClient?) async {
        guard let client else { return }
        if isLoaded {
            loadMoreIfNeeded(client)
            return
        }
        do {
            let since = discoverFromYear
            async let trending = client.trendingMovies()
            async let tv = client.trendingTV()
            // Popular and top rated come from discover so they can be limited to 2020 on.
            // Popular films are three pages deep, so Movies has plenty to browse.
            async let popular = client.discoverMovies(fromYear: since)
            async let popular2 = try? client.discoverMovies(fromYear: since, page: 2)
            async let popular3 = try? client.discoverMovies(fromYear: since, page: 3)
            async let top = client.discoverMovies(fromYear: since, sort: .rating)
            // The show lists only feed Home and Series, so a failure here doesn't hide the films.
            async let popularShows = try? client.discoverTV(fromYear: since)
            async let popularShows2 = try? client.discoverTV(fromYear: since, page: 2)
            async let popularShows3 = try? client.discoverTV(fromYear: since, page: 3)
            async let topShows = try? client.discoverTV(fromYear: since, sort: .rating)

            trendingMovies = Self.recent(try await trending.map(DiscoverTitle.init))
            trendingTV = Self.recent(try await tv.map(DiscoverTitle.init))
            let firstPage = try await popular.map(DiscoverTitle.init)
            let films2 = (await popular2 ?? []).map(DiscoverTitle.init)
            let films3 = (await popular3 ?? []).map(DiscoverTitle.init)
            popularMovies = Self.merged([firstPage, films2, films3])
            topRated = try await top.map(DiscoverTitle.init)
            let shows1 = (await popularShows ?? []).map(DiscoverTitle.init)
            let shows2 = (await popularShows2 ?? []).map(DiscoverTitle.init)
            let shows3 = (await popularShows3 ?? []).map(DiscoverTitle.init)
            popularTV = Self.merged([shows1, shows2, shows3])
            topRatedTV = (await topShows ?? []).map(DiscoverTitle.init)
            error = nil
            isLoaded = true
            loadMoreIfNeeded(client)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// CasaPlay's Home, Movies and Series screens show titles from this year on.
let discoverFromYear = 2020

/// Opens a TMDB title as a library item and pushes its detail page.
struct DiscoverOpener {
    let app: AppState
    let push: (UUID) -> Void
    let setBusy: (Bool) -> Void
    let setError: (String?) -> Void

    @MainActor
    func open(_ title: DiscoverTitle) {
        Task { @MainActor in
            setBusy(true)
            defer { setBusy(false) }
            do {
                let id = title.isShow
                    ? try await app.openShow(tmdbID: title.tmdbID)
                    : try await app.openMovie(tmdbID: title.tmdbID)
                if let id { setError(nil); push(id) }
            } catch {
                setError(error.localizedDescription)
            }
        }
    }
}

struct DiscoverShelf: View {
    let title: String
    let titles: [DiscoverTitle]
    let ranked: Bool
    let destination: AppSection?
    let onSelect: (DiscoverTitle) -> Void

    init(title: String, titles: [DiscoverTitle], ranked: Bool = false, destination: AppSection? = nil,
         onSelect: @escaping (DiscoverTitle) -> Void) {
        self.title = title
        self.titles = titles
        self.ranked = ranked
        self.destination = destination
        self.onSelect = onSelect
    }

    var body: some View {
        if !titles.isEmpty {
            #if os(tvOS)
            TVShelf(title: title) { tiles }
                .task(id: titles.count) { prefetchPosters() }
            #else
            Shelf(title: title, destination: destination) { tiles }
                .task(id: titles.count) { prefetchPosters() }
            #endif
        }
    }

    /// Loads the posters of the whole shelf now, so they are ready when they scroll in.
    private func prefetchPosters() {
        let urls = titles.compactMap { title in title.posterPath.flatMap { TMDBClient.posterURL($0) } }
        ImagePipeline.prefetch(urls, maxPixel: 600)
    }

    @ViewBuilder
    private var tiles: some View {
        ForEach(Array(titles.enumerated()), id: \.element.id) { position, item in
            Button { onSelect(item) } label: {
                card(item, rank: position + 1)
            }
            .appleTileStyle()
        }
    }

    @ViewBuilder
    private func card(_ item: DiscoverTitle, rank: Int) -> some View {
        #if os(tvOS)
        TVPosterTile(title: item.title, posterPath: item.posterPath, rank: ranked ? rank : nil, caption: item.tvCaption)
        #else
        ApplePosterCard(title: item.title, posterPath: item.posterPath, rank: ranked ? rank : nil)
        #endif
    }
}

struct DiscoverHero: View {
    let title: DiscoverTitle
    let onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackdropImage(path: title.backdropPath ?? title.posterPath, hue: 220, alignment: .top)
            LinearGradient(colors: [Color.clear, Theme.background], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: Metrics.s(8)) {
                Text("TRENDING THIS WEEK")
                    .font(.casa(11, weight: .bold))
                    .tracking(Platform.isTV ? 3 : 1.5)
                    .foregroundStyle(Theme.accent)
                Text(title.title)
                    .font(.casa(34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if !title.overview.isEmpty {
                    Text(title.overview)
                        .font(.casa(14))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: Metrics.s(560), alignment: .leading)
                }
                Button(action: onOpen) {
                    Label("Watch", systemImage: "play.fill")
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, Metrics.s(4))
            }
            .padding(Metrics.screenPadding)
        }
        .frame(height: Metrics.heroHeight)
        .clipped()
    }
}

/// TMDB backdrop, or the coloured placeholder while loading or when there is none.
struct BackdropImage: View {
    let path: String?
    let hue: Double
    /// The full-size picture, for something that fills an Apple TV screen.
    var fullSize = false
    /// Where the picture sits when it is cropped to fit. A big banner uses `.top`, so heads aren't cut off.
    var alignment: Alignment = .center

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Group {
                if let path, let url = fullSize ? TMDBClient.originalBackdropURL(path) : TMDBClient.backdropURL(path) {
                    CachedAsyncImage(url: url, maxPixel: fullSize ? 3200 : 1600) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: size.width, height: size.height, alignment: alignment)
                        } else {
                            ArtView(hue: hue, cornerRadius: 0)
                        }
                    }
                } else {
                    ArtView(hue: hue, cornerRadius: 0)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }
}

struct TMDBKeyNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            Label("Connect TMDB to see real movies", systemImage: "key")
                .font(.casa(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Add your TMDB read access token or API key in Profile › Online services. Trending films, shows and posters appear here once it's set.")
                .font(.casa(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Metrics.s(16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .padding(.horizontal, Metrics.screenPadding)
        .focusableOnTV()
    }
}
