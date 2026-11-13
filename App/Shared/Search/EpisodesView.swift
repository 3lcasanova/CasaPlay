// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Season/episode browser for a TV show fetched from TMDB.
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
    @State private var episodes: [TMDBEpisode] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var streamingEpisode: EpisodeTarget?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    ContentUnavailableView("Load Failed", systemImage: "exclamationmark.triangle",
                                          description: Text(err))
                } else {
                    episodeList
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(show.title)
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
        .sheet(item: $streamingEpisode) { target in
            StreamSourcesView(request: target.request, title: target.title)
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
        guard let showID = show.tmdbShowID, let client = app.tmdbClient else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let season = try await client.seasonDetail(showID: showID, season: selectedSeason)
            episodes = season.episodes ?? []
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Stream

    private func streamEpisode(_ ep: TMDBEpisode) {
        guard let seriesID = show.imdbID else { return }
        let request = ContentRequest(
            kind: .episode,
            id: seriesID,
            title: show.title,
            year: show.year,
            season: ep.season_number,
            episode: ep.episode_number
        )
        streamingEpisode = EpisodeTarget(
            request: request,
            title: "\(show.title) S\(String(format: "%02d", ep.season_number))E\(String(format: "%02d", ep.episode_number))"
        )
    }
}

// MARK: - Episode row

private struct EpisodeRow: View {
    let episode: TMDBEpisode
    let show: MediaItem
    let onStream: () -> Void

    var body: some View {
        Button(action: onStream) {
            HStack(alignment: .top, spacing: Metrics.s(14)) {
                // Still image or placeholder
                episodeThumb
                    .frame(width: Metrics.s(100), height: Metrics.s(56))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: Metrics.s(4)) {
                    HStack {
                        Text("E\(episode.episode_number)")
                            .font(.casa(11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(episode.name)
                            .font(.casa(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let rt = episode.runtime {
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
        .buttonStyle(.plain)
        .focusableOnTV()
    }

    @ViewBuilder
    private var episodeThumb: some View {
        if let path = episode.still_path, let url = TMDBClient.backdropURL(path) {
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

private struct EpisodeTarget: Identifiable {
    let id = UUID()
    let request: ContentRequest
    let title: String
}
