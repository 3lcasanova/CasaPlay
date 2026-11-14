// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State var path: [UUID] = []
    @State var isOpening = false
    @State var openError: String?

    var opener: DiscoverOpener {
        DiscoverOpener(app: app,
                       push: { path.append($0) },
                       setBusy: { isOpening = $0 },
                       setError: { openError = $0 })
    }

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        phoneBody
        #endif
    }

    // MARK: Apple TV

    @ViewBuilder
    private var tvBody: some View {
        #if os(tvOS)
        let feed = app.discover

        NavigationStack(path: $path) {
            TVHome(path: $path, opener: opener, isOpening: isOpening, message: openError ?? feed.error)
                .task(id: app.tmdbClient == nil) {
                    await feed.loadIfNeeded(app.tmdbClient)
                }
                .navigationDestination(for: UUID.self) { id in
                    DetailView(itemID: id)
                }
        }
        #else
        EmptyView()
        #endif
    }
}

#if !os(tvOS)

// MARK: - iPhone and iPad

extension HomeView {
    /// Up to two titles you are watching, then trending films and shows, alternating.
    private var heroSlides: [HeroSlide] {
        let feed = app.discover
        var slides = app.continueWatching.prefix(2).map { HeroSlide(source: .library($0)) }

        var online: [DiscoverTitle] = []
        let films = feed.trendingMovies.filter { $0.backdropPath != nil }
        let shows = feed.trendingTV.filter { $0.backdropPath != nil }
        for position in 0..<max(films.count, shows.count) {
            if position < films.count { online.append(films[position]) }
            if position < shows.count { online.append(shows[position]) }
        }
        slides += online.prefix(max(6 - slides.count, 0)).map { HeroSlide(source: .online($0)) }
        return slides
    }

    @ViewBuilder
    var phoneBody: some View {
        let feed = app.discover

        NavigationStack(path: $path) {
            GeometryReader { proxy in
                let topInset = max(proxy.safeAreaInsets.top, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        let slides = heroSlides
                        if slides.isEmpty {
                            HomeHeader(topInset: topInset)
                        } else {
                            HomeHero(slides: slides, topInset: topInset) { opener.open($0) }
                        }

                        if app.tmdbClient == nil {
                            TMDBKeyNotice()
                        }

                        if let message = openError ?? feed.error {
                            Text(message)
                                .font(.casa(13))
                                .foregroundStyle(.red)
                                .padding(.horizontal, Metrics.screenPadding)
                        }

                        if !app.continueWatching.isEmpty {
                            Shelf(title: "Continue Watching") {
                                ForEach(app.continueWatching) { item in
                                    NavigationLink(value: item.id) {
                                        ContinueCard(item: item)
                                    }
                                    .posterButtonStyle()
                                }
                            }
                        }

                        DiscoverShelf(title: "Top 10 Movies This Week",
                                      titles: Array(feed.trendingMovies.prefix(10)),
                                      ranked: true, destination: .movies) { opener.open($0) }
                        DiscoverShelf(title: "Top 10 TV Shows This Week",
                                      titles: Array(feed.trendingTV.prefix(10)),
                                      ranked: true, destination: .series) { opener.open($0) }

                        if !app.favorites.isEmpty {
                            Shelf(title: "Favorites") {
                                ForEach(app.favorites) { item in
                                    NavigationLink(value: item.id) {
                                        libraryPoster(item)
                                    }
                                    .posterButtonStyle()
                                }
                            }
                        }

                        DiscoverShelf(title: "Popular Movies", titles: feed.popularMovies, destination: .movies) { opener.open($0) }
                        DiscoverShelf(title: "Now Playing", titles: feed.titles("m-nowPlaying"), destination: .movies) { opener.open($0) }
                        DiscoverShelf(title: "Popular Shows", titles: feed.popularTV, destination: .series) { opener.open($0) }
                        DiscoverShelf(title: "Top Rated", titles: feed.topRated, destination: .movies) { opener.open($0) }
                        DiscoverShelf(title: "Top Rated Shows", titles: feed.topRatedTV, destination: .series) { opener.open($0) }
                        DiscoverShelf(title: "Anime Series", titles: feed.titles("tv-anime"), destination: .series) { opener.open($0) }
                        DiscoverShelf(title: "Anime Movies", titles: feed.titles("m-anime"), destination: .movies) { opener.open($0) }
                        DiscoverShelf(title: "Coming Soon", titles: feed.titles("m-upcoming"), destination: .movies) { opener.open($0) }

                        if !app.recentlyAdded.isEmpty {
                            Shelf(title: "Your Library") {
                                ForEach(app.recentlyAdded) { item in
                                    NavigationLink(value: item.id) {
                                        libraryPoster(item)
                                    }
                                    .posterButtonStyle()
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea(edges: .top)
                .screenBackground()
                .overlay {
                    if isOpening {
                        ProgressView().tint(.white)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: app.tmdbClient == nil) {
                await feed.loadIfNeeded(app.tmdbClient)
            }
            .navigationDestination(for: UUID.self) { id in
                DetailView(itemID: id)
            }
        }
    }

    private func libraryPoster(_ item: MediaItem) -> some View {
        ApplePosterCard(title: item.title,
                        posterPath: item.posterPath,
                        progress: item.canResume ? item.progressFraction : nil,
                        isWatched: item.isWatched)
    }
}

#endif

struct HeroView: View {
    @Environment(AppState.self) private var app
    let item: MediaItem

    /// Online titles have no saved stream, so resuming means picking one on the detail page.
    private var needsStream: Bool { item.streamURL == nil && item.sourceName.isEmpty }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackdropImage(path: item.backdropPath ?? item.posterPath, hue: item.artHue)
            LinearGradient(
                colors: [Color.clear, Theme.background],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: Metrics.s(8)) {
                Text(item.canResume ? "CONTINUE WATCHING" : "FEATURED")
                    .font(.casa(11, weight: .bold))
                    .tracking(Platform.isTV ? 3 : 1.5)
                    .foregroundStyle(Theme.accent)

                Text(item.title)
                    .font(.casa(34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Metrics.s(12)) {
                    Text(item.metaLine)
                        .font(.casa(13))
                        .foregroundStyle(Theme.textSecondary)
                    if let rating = item.imdbRating {
                        IMDbBadge(rating: rating)
                    }
                }

                if !needsStream {
                    HStack(spacing: Metrics.s(6)) {
                        ForEach(item.file.badges, id: \.self) { badge in
                            Pill(text: badge)
                        }
                    }
                }

                HStack(spacing: Metrics.s(10)) {
                    if needsStream {
                        NavigationLink(value: item.id) {
                            Label(item.canResume ? "Resume" : "Watch", systemImage: "play.fill")
                                .foregroundStyle(Theme.onAccent)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            app.play(item)
                        } label: {
                            Label(item.canResume ? "Resume" : "Play", systemImage: "play.fill")
                                .foregroundStyle(Theme.onAccent)
                        }
                        .buttonStyle(.borderedProminent)

                        NavigationLink(value: item.id) {
                            Label("Details", systemImage: "info.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, Metrics.s(4))
            }
            .padding(Metrics.screenPadding)
        }
        .frame(height: Metrics.heroHeight)
        .clipped()
    }
}
