// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var path: [UUID] = []
    @State private var isOpening = false
    @State private var openError: String?

    private var opener: DiscoverOpener {
        DiscoverOpener(app: app,
                       push: { path.append($0) },
                       setBusy: { isOpening = $0 },
                       setError: { openError = $0 })
    }

    var body: some View {
        let feed = app.discover

        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    if let item = app.continueWatching.first {
                        HeroView(item: item)
                    } else if let top = feed.trendingMovies.first {
                        DiscoverHero(title: top) { opener.open(top) }
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
                                    LandscapeCard(item: item)
                                }
                                .posterButtonStyle()
                            }
                        }
                    }

                    DiscoverShelf(title: "Trending Movies", titles: feed.trendingMovies) { opener.open($0) }
                    DiscoverShelf(title: "Trending TV Shows", titles: feed.trendingTV) { opener.open($0) }

                    if !app.favorites.isEmpty {
                        Shelf(title: "Favorites") {
                            ForEach(app.favorites) { item in
                                NavigationLink(value: item.id) {
                                    PosterCard(item: item)
                                }
                                .posterButtonStyle()
                            }
                        }
                    }

                    DiscoverShelf(title: "Popular Movies", titles: feed.popularMovies) { opener.open($0) }
                    DiscoverShelf(title: "Top Rated", titles: feed.topRated) { opener.open($0) }

                    if !app.recentlyAdded.isEmpty {
                        Shelf(title: "Your Library") {
                            ForEach(app.recentlyAdded) { item in
                                NavigationLink(value: item.id) {
                                    PosterCard(item: item)
                                }
                                .posterButtonStyle()
                            }
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
                await feed.loadIfNeeded(app.tmdbClient)
            }
            .navigationDestination(for: UUID.self) { id in
                DetailView(itemID: id)
            }
        }
    }
}

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
