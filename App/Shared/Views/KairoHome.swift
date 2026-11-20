// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Apple TV only. Home in the Kairo style: a big "ON NOW" area at the top that follows whatever you
// look at, with the shelves under it. Move onto a channel and the top changes to what is on that channel;
// move onto a film and it shows that film. Watch starts it.

#if os(tvOS)

import SwiftUI
import CasaPlayKit

/// What the top area is showing.
struct KairoHero: Equatable {
    enum Source: Equatable {
        case channel(FavoriteChannel)
        case title(DiscoverTitle)
        case library(UUID)
        case none
    }

    var source: Source
    var label: String
    var title: String
    var subtitle: String?
    var progress: Double?
    var overview: String
    var imageURL: URL?
    /// A channel logo is drawn whole on a dark card; a film's picture fills the card.
    var imageIsLogo: Bool
}

struct KairoHome: View {
    @Environment(AppState.self) private var app
    @Environment(RecentChannels.self) private var recent
    @Binding var path: [UUID]
    let opener: DiscoverOpener
    let isOpening: Bool
    let message: String?

    @State private var focusedHero: KairoHero?

    var body: some View {
        let hero = focusedHero ?? defaultHero

        VStack(alignment: .leading, spacing: 0) {
            heroArea(hero)
                .frame(height: 470)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    if app.tmdbClient == nil {
                        TMDBKeyNotice()
                    }
                    if let message {
                        Text(message)
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 70)
                    }
                    shelves
                }
                .padding(.bottom, 160)
            }
        }
        .overlay {
            if isOpening {
                ProgressView().tint(.white)
            }
        }
        .task { await recent.refreshGuide() }
    }

    // MARK: Hero

    private var defaultHero: KairoHero {
        if let channel = recent.channels.first { return channelHero(channel) }
        let feed = app.discover
        if let title = feed.trendingMovies.first(where: { $0.backdropPath != nil }) ?? feed.trendingMovies.first {
            return titleHero(title)
        }
        return KairoHero(source: .none, label: "WELCOME", title: "CasaPlay",
                         subtitle: nil, progress: nil,
                         overview: "Your movies, shows, live channels, sports and news in one place.",
                         imageURL: nil, imageIsLogo: false)
    }

    private func channelHero(_ channel: FavoriteChannel) -> KairoHero {
        let now = recent.guide[channel.id]?.now
        var subtitle = channel.name
        if let now {
            subtitle += "   " + now.start.formatted(date: .omitted, time: .shortened)
                + " – " + now.end.formatted(date: .omitted, time: .shortened)
        }
        return KairoHero(source: .channel(channel), label: "ON NOW",
                         title: now?.title ?? channel.name, subtitle: subtitle,
                         progress: now?.progress(at: Date()), overview: now?.detail ?? "",
                         imageURL: channel.logo.flatMap { URL(string: $0) }, imageIsLogo: true)
    }

    private func titleHero(_ title: DiscoverTitle) -> KairoHero {
        var parts: [String] = [title.isShow ? "TV Show" : "Movie"]
        if let year = title.year { parts.append(String(year)) }
        if let rating = title.rating, rating > 0 { parts.append(String(format: "%.1f", rating)) }
        let picture = (title.backdropPath ?? title.posterPath).flatMap { TMDBClient.backdropURL($0) }
        return KairoHero(source: .title(title), label: "TRENDING", title: title.title,
                         subtitle: parts.joined(separator: "  ·  "), progress: nil,
                         overview: title.overview, imageURL: picture, imageIsLogo: false)
    }

    private func libraryHero(_ item: MediaItem) -> KairoHero {
        let picture = (item.backdropPath ?? item.posterPath).flatMap { TMDBClient.backdropURL($0) }
        return KairoHero(source: .library(item.id), label: "CONTINUE WATCHING", title: item.title,
                         subtitle: item.metaLine, progress: item.canResume ? item.progressFraction : nil,
                         overview: item.overview, imageURL: picture, imageIsLogo: false)
    }

    private func heroArea(_ hero: KairoHero) -> some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 14) {
                Text(hero.label)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Kairo.label)
                Text(hero.title)
                    .font(.system(size: 58, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let subtitle = hero.subtitle {
                    Text(subtitle)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if let progress = hero.progress {
                    KairoProgress(value: progress)
                        .frame(width: 520, height: 5)
                }
                if !hero.overview.isEmpty {
                    Text(hero.overview)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                        .frame(maxWidth: 860, alignment: .leading)
                }
                if hero.source != .none {
                    HStack(spacing: 18) {
                        Button { watch(hero) } label: {
                            Label("Watch", systemImage: "play.fill")
                        }
                        .buttonStyle(KairoActionStyle(primary: true))
                        Button { more(hero) } label: {
                            Text(moreTitle(hero))
                        }
                        .buttonStyle(KairoActionStyle(primary: false))
                    }
                    .padding(.top, 6)
                    .focusSection()
                }
            }
            Spacer(minLength: 0)
            previewCard(hero)
                .frame(width: 760, height: 430)
        }
        .padding(.horizontal, 70)
        .padding(.top, 6)
    }

    private func previewCard(_ hero: KairoHero) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Kairo.card.opacity(0.6))
            if let url = hero.imageURL {
                CachedAsyncImage(url: url) { phase in
                    if let image = phase.image {
                        if hero.imageIsLogo {
                            image.resizable().scaledToFit().padding(60)
                        } else {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hero.imageIsLogo {
                Text("LIVE")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.88, green: 0.11, blue: 0.16), in: Capsule())
                    .padding(16)
            }
        }
    }

    private func moreTitle(_ hero: KairoHero) -> String {
        if case .channel = hero.source { return "Open guide" }
        return "Details"
    }

    private func watch(_ hero: KairoHero) {
        switch hero.source {
        case .channel(let channel):
            if !recent.play(channel, app: app) { app.selectedSection = .iptv }
        case .title(let title):
            opener.open(title)
        case .library(let id):
            path.append(id)
        case .none:
            break
        }
    }

    private func more(_ hero: KairoHero) {
        if case .channel = hero.source {
            app.selectedSection = .iptv
        } else {
            watch(hero)
        }
    }

    // MARK: Shelves

    @ViewBuilder
    private var shelves: some View {
        let feed = app.discover

        if !app.continueWatching.isEmpty {
            shelf("Continue watching") {
                ForEach(app.continueWatching) { item in
                    Button { path.append(item.id) } label: {
                        KairoPoster(title: item.title,
                                    url: item.posterPath.flatMap { TMDBClient.posterURL($0) },
                                    rating: item.imdbRating ?? item.tmdbRating)
                    }
                    .buttonStyle(KairoCardStyle(onFocus: { focusedHero = libraryHero(item) }))
                }
            }
        }

        if !recent.channels.isEmpty {
            shelf("Recently watched") {
                ForEach(recent.channels) { channel in
                    Button { recent.play(channel, app: app) } label: {
                        KairoChannelCard(channel: channel, nowNext: recent.guide[channel.id])
                    }
                    .buttonStyle(KairoCardStyle(onFocus: { focusedHero = channelHero(channel) }))
                }
            }
        }

        TodayShelves()

        titleShelf("Recommended movies", DiscoverFeed.merged([feed.trendingMovies, feed.popularMovies]))
        titleShelf("Recommended shows", DiscoverFeed.merged([feed.trendingTV, feed.popularTV]))
        titleShelf("Top rated movies", feed.topRated)
        titleShelf("Top rated shows", feed.topRatedTV)
        titleShelf("On TV tonight", feed.titles("tv-airingToday"))
        titleShelf("Now playing", feed.titles("m-nowPlaying"))
        titleShelf("Coming soon", feed.titles("m-upcoming"))
        titleShelf("Anime series", feed.titles("tv-anime"))
    }

    @ViewBuilder
    private func titleShelf(_ title: String, _ titles: [DiscoverTitle]) -> some View {
        if !titles.isEmpty {
            shelf(title) {
                ForEach(titles) { item in
                    Button { opener.open(item) } label: {
                        KairoPoster(title: item.title,
                                    url: item.posterPath.flatMap { TMDBClient.posterURL($0) },
                                    rating: item.rating)
                    }
                    .buttonStyle(KairoCardStyle(onFocus: { focusedHero = titleHero(item) }))
                }
            }
        }
    }

    private func shelf<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 70)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 28) {
                    content()
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 24)
            }
            .focusSection()
        }
    }
}

// MARK: - Cards

/// A poster with its rating in a gold badge, and the title underneath.
struct KairoPoster: View {
    let title: String
    let url: URL?
    let rating: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Kairo.card)
                CachedAsyncImage(url: url, maxPixel: 600) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Text(String(title.prefix(2)).uppercased())
                            .font(.system(size: 40, weight: .heavy))
                            .foregroundStyle(Kairo.secondary)
                    }
                }
                if let rating, rating > 0 {
                    KairoBadge(text: String(format: "%.1f", rating))
                        .padding(10)
                }
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)
        }
    }
}

/// A channel: its logo, its name, what is on now, and how far through it is.
struct KairoChannelCard: View {
    let channel: FavoriteChannel
    let nowNext: NowNext?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let url = channel.logo.flatMap({ URL(string: $0) }) {
                    CachedAsyncImage(url: url, maxPixel: 500) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit().padding(14)
                        } else {
                            Image(systemName: "tv").font(.system(size: 40)).foregroundStyle(Kairo.secondary)
                        }
                    }
                } else {
                    Image(systemName: "tv").font(.system(size: 40)).foregroundStyle(Kairo.secondary)
                }
            }
            .frame(height: 96)

            Text(channel.name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(nowNext?.now?.title ?? " ")
                .font(.system(size: 20))
                .foregroundStyle(Kairo.secondary)
                .lineLimit(1)
            KairoProgress(value: nowNext?.now?.progress(at: Date()) ?? 0)
                .frame(height: 4)
                .opacity(nowNext?.now == nil ? 0 : 1)
        }
        .padding(18)
        .frame(width: 290, height: 214)
        .background(Kairo.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#endif
