// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The shows you follow (favourites, and anything you have watched an episode of): which have a new
// episode out, when the next one airs, and where you left off. Air dates come from TMDB.

import SwiftUI
import CasaPlayKit

struct TrackedShow: Identifiable {
    let item: MediaItem
    let tracking: ShowTracking
    let leftOff: LeftOff?

    var id: UUID { item.id }
}

@MainActor
@Observable
final class SeriesTracker {
    static let shared = SeriesTracker()

    private(set) var shows: [TrackedShow] = []

    private var cache: [Int: (loaded: Date, tracking: ShowTracking)] = [:]

    private init() {}

    func refresh(app: AppState) async {
        guard let client = app.tmdbClient else {
            shows = []
            return
        }
        let followed = app.items.filter { item in
            item.tmdbShowID != nil && (item.isFavorite || app.leftOff(in: item) != nil)
        }
        var result: [TrackedShow] = []
        for item in followed.prefix(20) {
            guard let id = item.tmdbShowID else { continue }
            var tracking: ShowTracking?
            if let cached = cache[id], Date().timeIntervalSince(cached.loaded) < 6 * 3600 {
                tracking = cached.tracking
            } else if let info = try? await client.showAirInfo(id: id) {
                tracking = info.tracking()
                cache[id] = (Date(), info.tracking())
            }
            guard let tracking else { continue }
            result.append(TrackedShow(item: item, tracking: tracking, leftOff: app.leftOff(in: item)))
        }
        shows = result.sorted { $0.tracking.sortKey < $1.tracking.sortKey }
    }
}

/// Home: your shows, with the new episode, the next air date, and where you left off.
struct YourShowsShelf: View {
    @Environment(AppState.self) private var app
    @Environment(SeriesTracker.self) private var tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !tracker.shows.isEmpty {
                shelf
            }
        }
        .task(id: followKey) { await tracker.refresh(app: app) }
    }

    /// Changes when you follow or unfollow a show, so the list refreshes.
    private var followKey: String {
        app.items.filter { $0.isFavorite && $0.tmdbShowID != nil }.map { $0.id.uuidString }.sorted().joined()
            + (app.tmdbClient == nil ? "|nokey" : "|key")
    }

    @ViewBuilder
    private var shelf: some View {
        #if os(tvOS)
        TVShelf(title: "Your Shows") { cards }
        #else
        Shelf(title: "Your Shows", destination: .series) { cards }
        #endif
    }

    private var cards: some View {
        ForEach(tracker.shows) { show in
            NavigationLink(value: show.item.id) {
                TrackedShowCard(show: show)
            }
            .posterButtonStyle()
        }
    }
}

struct TrackedShowCard: View {
    let show: TrackedShow

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            artwork
                .frame(width: Metrics.landscapeWidth, height: Metrics.landscapeWidth * 0.56)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if show.tracking.hasNewEpisode {
                        Text("NEW")
                            .font(.casa(10, weight: .heavy))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, Metrics.s(8))
                            .padding(.vertical, Metrics.s(3))
                            .background(Theme.accent, in: Capsule())
                            .padding(Metrics.s(8))
                    }
                }

            VStack(alignment: .leading, spacing: Metrics.s(3)) {
                Text(show.item.title)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let latest = show.tracking.latestText {
                    line("New: " + latest, color: Theme.accent)
                }
                if let next = show.tracking.nextText {
                    line("Next: " + next, color: Theme.textSecondary)
                }
                if let left = show.leftOff {
                    line((left.isWatched ? "Watched " : "Left off at ") + left.label, color: Theme.textSecondary)
                }
            }
            .frame(width: Metrics.landscapeWidth, alignment: .leading)
        }
    }

    private func line(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.casa(11, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    @ViewBuilder
    private var artwork: some View {
        let path = show.item.backdropPath ?? show.item.posterPath
        if let path, let url = TMDBClient.backdropURL(path) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Theme.surfaceStrong)
                }
            }
        } else {
            Rectangle().fill(Theme.surfaceStrong)
        }
    }
}
