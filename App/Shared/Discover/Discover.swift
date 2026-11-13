// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Real titles from TMDB for Home and Movies: trending, popular and top-rated lists.

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

    var id: String { (isShow ? "tv-" : "movie-") + String(tmdbID) }

    init(_ m: TMDBMovie) {
        tmdbID = m.id; isShow = false; title = m.title; year = m.releaseYear
        posterPath = m.poster_path; backdropPath = m.backdrop_path
        overview = m.overview ?? ""; rating = m.vote_average
    }

    init(_ s: TMDBShow) {
        tmdbID = s.id; isShow = true; title = s.name; year = s.firstAirYear
        posterPath = s.poster_path; backdropPath = s.backdrop_path
        overview = s.overview ?? ""; rating = s.vote_average
    }
}

@Observable
final class DiscoverFeed {
    var trendingMovies: [DiscoverTitle] = []
    var trendingTV: [DiscoverTitle] = []
    var popularMovies: [DiscoverTitle] = []
    var topRated: [DiscoverTitle] = []
    var error: String?
    private(set) var isLoaded = false

    @MainActor
    func loadIfNeeded(_ client: TMDBClient?) async {
        guard !isLoaded, let client else { return }
        do {
            async let trending = client.trendingMovies()
            async let tv = client.trendingTV()
            async let popular = client.popularMovies()
            async let top = client.topRatedMovies()
            trendingMovies = try await trending.map(DiscoverTitle.init)
            trendingTV = try await tv.map(DiscoverTitle.init)
            popularMovies = try await popular.map(DiscoverTitle.init)
            topRated = try await top.map(DiscoverTitle.init)
            error = nil
            isLoaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

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
    let onSelect: (DiscoverTitle) -> Void

    var body: some View {
        if !titles.isEmpty {
            Shelf(title: title) {
                ForEach(titles) { item in
                    Button { onSelect(item) } label: {
                        SearchPosterCard(
                            title: item.title,
                            year: item.year,
                            posterPath: item.posterPath,
                            rating: item.rating.map { String(format: "★ %.1f", $0) }
                        )
                    }
                    .posterButtonStyle()
                }
            }
        }
    }
}

struct DiscoverHero: View {
    let title: DiscoverTitle
    let onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackdropImage(path: title.backdropPath ?? title.posterPath, hue: 220)
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

    var body: some View {
        if let path, let url = TMDBClient.backdropURL(path) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ArtView(hue: hue, cornerRadius: 0)
                }
            }
        } else {
            ArtView(hue: hue, cornerRadius: 0)
        }
    }
}

struct TMDBKeyNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            Label("Connect TMDB to see real movies", systemImage: "key")
                .font(.casa(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Add your TMDB read access token in Profile › Online services. Trending films, shows and posters appear here once it's set.")
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
