// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Season/episode browser for a TV show. TMDB supplies the episode list; TheTVDB backs it up
// when TMDB has none and fills in missing titles, summaries and pictures.
// Presented as a sheet from DetailView when item.tmdbShowID is set.
// Tapping an episode opens StreamSourcesView for that S/E pair.

import SwiftUI
import CasaPlayKit

struct EpisodesView: View {
    let show: MediaItem           // parent show item
    let totalSeasons: Int

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSeason = 1
    @State private var episodes: [EpisodeInfo] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var tvdbSeriesID: Int?
    @State private var streamingEpisode: EpisodeTarget?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    ContentUnavailableView("Can't show episodes", systemImage: "exclamationmark.triangle",
                                          description: Text(err))
                } else {
                    episodeList
                }
            }
            .screenBackground()
            .scrollingScreenTitle(show.title)
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
            .safeAreaInset(edge: .top) { seasonPicker }
        }
        .adaptiveSheet(item: $streamingEpisode) { target in
            StreamSourcesView(request: target.request, libraryItemID: target.episodeID)
        }
        .task(id: selectedSeason) { await loadSeason() }
    }

    // MARK: - Season picker

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.s(8)) {
                ForEach(1...totalSeasons, id: \.self) { n in
                    Button("Season \(n)") { selectedSeason = n }
                        .font(.casa(13, weight: selectedSeason == n ? .semibold : .regular))
                        .foregroundStyle(selectedSeason == n ? Theme.accent : Theme.textSecondary)
                        .padding(.horizontal, Metrics.s(12))
                        .padding(.vertical, Metrics.s(6))
                        .background(selectedSeason == n ? Theme.accent.opacity(0.15) : Color.clear,
                                    in: Capsule())
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, Metrics.s(10))
        }
        .background(Theme.background)
    }

    // MARK: - Episode list

    private var episodeList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(episodes) { ep in
                    EpisodeRow(episode: ep, show: show) {
                        streamEpisode(ep)
                    }
                    Divider().background(Theme.surface).padding(.leading, Metrics.screenPadding)
                }
            }
            .padding(.bottom, Metrics.sectionSpacing)
        }
    }

    // MARK: - Load

    private func loadSeason() async {
        let season = selectedSeason
        let tmdb = app.tmdbClient
        let tvdb = app.tvdbClient
        guard tmdb != nil || tvdb != nil else {
            loadError = "Add a TMDB or TheTVDB key in Profile › Online services to see episodes."
            return
        }
        isLoading = true
        loadError = nil
        defer { if !Task.isCancelled { isLoading = false } }

        var result: [EpisodeInfo] = []
        var failure: String?
        if let tmdb, let showID = show.tmdbShowID {
            do {
                let detail = try await tmdb.seasonDetail(showID: showID, season: season)
                result = (detail.episodes ?? []).map(EpisodeInfo.init(tmdb:))
            } catch {
                failure = error.localizedDescription
            }
        }

        // TheTVDB steps in when TMDB has nothing, and fills gaps (titles, summaries, pictures).
        let needsHelp = result.isEmpty || result.contains {
            Self.isGenericTitle($0.name) || ($0.overview ?? "").isEmpty || $0.imageURL == nil
        }
        if needsHelp, let tvdb, let extra = await tvdbEpisodes(tvdb, season: season) {
            result = Self.merged(result, with: extra)
        }

        guard !Task.isCancelled else { return }
        episodes = result
        if result.isEmpty {
            loadError = failure ?? "No episodes were found for season \(season)."
        }
    }

    private func tvdbEpisodes(_ client: TVDBClient, season: Int) async -> [TVDBEpisode]? {
        guard let imdb = show.imdbID, !imdb.isEmpty else { return nil }
        do {
            let seriesID: Int
            if let known = tvdbSeriesID {
                seriesID = known
            } else if let found = try await client.seriesID(imdbID: imdb) {
                seriesID = found
                tvdbSeriesID = found
            } else {
                return nil
            }
            return try await client.episodes(seriesID: seriesID, season: season)
        } catch {
            return nil
        }
    }

    /// "Episode 4" or an empty name means the source had no real title.
    static func isGenericTitle(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed.range(of: #"^Episode\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// TMDB's list stays the base. TheTVDB only fills what's missing, and supplies the whole list when TMDB has none.
    static func merged(_ base: [EpisodeInfo], with extra: [TVDBEpisode]) -> [EpisodeInfo] {
        guard !extra.isEmpty else { return base }
        if base.isEmpty { return extra.map(EpisodeInfo.init(tvdb:)) }
        let byNumber = Dictionary(extra.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        return base.map { episode in
            guard let other = byNumber[episode.number] else { return episode }
            var episode = episode
            if isGenericTitle(episode.name), !isGenericTitle(other.name) { episode.name = other.name }
            if (episode.overview ?? "").isEmpty, let overview = other.overview, !overview.isEmpty {
                episode.overview = overview
            }
            if episode.imageURL == nil { episode.imageURL = other.imageURL }
            if episode.runtimeMinutes == nil { episode.runtimeMinutes = other.runtimeMinutes }
            return episode
        }
    }

    // MARK: - Stream

    private func streamEpisode(_ ep: EpisodeInfo) {
        guard let seriesID = show.imdbID else { return }
        let request = ContentRequest.episode(
            seriesID: seriesID,
            title: show.title,
            season: ep.season,
            episode: ep.number,
            year: show.year
        )
        let episodeID = app.registerEpisode(show: show, season: ep.season,
                                            episode: ep.number, runtimeMinutes: ep.runtimeMinutes)
        streamingEpisode = EpisodeTarget(
            request: request,
            episodeID: episodeID,
            title: "\(show.title) S\(String(format: "%02d", ep.season))E\(String(format: "%02d", ep.number))"
        )
    }
}

// MARK: - Episode row

private struct EpisodeRow: View {
    @Environment(AppState.self) private var app
    let episode: EpisodeInfo
    let show: MediaItem
    let onStream: () -> Void

    private var record: WatchRecord? {
        let key = AppState.episodeItem(show: show, season: episode.season,
                                       episode: episode.number, runtimeMinutes: episode.runtimeMinutes).historyKey
        // Episodes played this session are tracked live; earlier ones come from saved history.
        if let live = app.episodes.first(where: { $0.historyKey == key }) {
            return WatchRecord(key: key, progressSeconds: live.progressSeconds, isWatched: live.isWatched,
                               isFavorite: live.isFavorite, lastPlayedAt: live.lastPlayedAt)
        }
        return app.watchRecord(forKey: key)
    }

    private var progressFraction: Double {
        guard let record, let runtime = episode.runtimeMinutes, runtime > 0 else { return 0 }
        return min(record.progressSeconds / Double(runtime * 60), 1)
    }

    var body: some View {
        Button(action: onStream) {
            HStack(alignment: .top, spacing: Metrics.s(14)) {
                // Still image or placeholder
                episodeThumb
                    .frame(width: Metrics.s(100), height: Metrics.s(56))
                    .overlay(alignment: .bottom) {
                        if progressFraction > 0 && record?.isWatched != true {
                            GeometryReader { geo in
                                Rectangle().fill(Theme.accent)
                                    .frame(width: geo.size.width * progressFraction, height: 3)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if record?.isWatched == true {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent)
                                .padding(4)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: Metrics.s(4)) {
                    HStack {
                        Text("E\(episode.number)")
                            .font(.casa(11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(episode.name)
                            .font(.casa(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let rt = episode.runtimeMinutes {
                            Text(TimeFormat.runtime(TimeInterval(rt * 60)))
                                .font(.casa(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.casa(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, Metrics.s(12))
        }
        .cardRowButtonStyle()
    }

    @ViewBuilder
    private var episodeThumb: some View {
        if let url = episode.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: placeholderThumb
                }
            }
        } else {
            placeholderThumb
        }
    }

    private var placeholderThumb: some View {
        ZStack {
            Rectangle().fill(Theme.surface)
            Image(systemName: "play.fill")
                .foregroundStyle(Theme.textSecondary)
                .font(.casa(16))
        }
    }
}

// MARK: - Helpers

/// One episode row, whichever service it came from.
struct EpisodeInfo: Identifiable {
    var id: String { "S\(season)E\(number)" }
    var season: Int
    var number: Int
    var name: String
    var overview: String?
    var runtimeMinutes: Int?
    var imageURL: URL?

    init(tmdb episode: TMDBEpisode) {
        season = episode.season_number
        number = episode.episode_number
        name = episode.name
        overview = episode.overview
        runtimeMinutes = episode.runtime
        imageURL = episode.still_path.flatMap { TMDBClient.backdropURL($0) }
    }

    init(tvdb episode: TVDBEpisode) {
        season = episode.season
        number = episode.number
        name = episode.name
        overview = episode.overview
        runtimeMinutes = episode.runtimeMinutes
        imageURL = episode.imageURL
    }
}

private struct EpisodeTarget: Identifiable {
    let id = UUID()
    let request: ContentRequest
    let episodeID: UUID
    let title: String
}
