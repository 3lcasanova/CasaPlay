// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// TMDB-powered search for movies and TV shows.
//
// Flow: user types → debounced TMDB search → grid of poster cards →
//       tap a card → fetch full TMDB detail → build MediaItem →
//       add to app.items → push DetailView
//
// When no TMDB key is configured, shows a friendly prompt to add one in
// Settings → Online Services.

import SwiftUI
import CasaPlayKit

struct SearchView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var kind = SearchKind.movies
    @State private var movieResults: [TMDBMovie] = []
    @State private var showResults: [TMDBShow] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var navPath: [UUID] = []
    @State private var isFetchingDetail = false

    enum SearchKind: String, CaseIterable {
        case movies = "Movies"
        case tv = "TV Shows"
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if app.tmdbClient == nil {
                    noKeyView
                } else {
                    searchContent
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Search")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .navigationDestination(for: UUID.self) { id in
                DetailView(itemID: id)
            }
        }
    }

    // MARK: - Search content

    private var searchContent: some View {
        VStack(spacing: 0) {
            // Search bar + kind picker
            VStack(spacing: Metrics.s(10)) {
                #if !os(tvOS)
                HStack(spacing: Metrics.s(10)) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Movies, TV shows…", text: $query)
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.accent)
                        .submitLabel(.search)
                        .onSubmit { triggerSearch() }
                    if !query.isEmpty {
                        Button { query = ""; clearResults() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(Metrics.s(12))
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
                .padding(.horizontal, Metrics.screenPadding)
                #endif

                Picker("Kind", selection: $kind) {
                    ForEach(SearchKind.allCases, id: \.self) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Metrics.screenPadding)
                .onChange(of: kind) { _, _ in triggerSearch() }
            }
            .padding(.top, Metrics.s(14))
            .padding(.bottom, Metrics.s(10))

            if let err = searchError {
                Text(err)
                    .font(.casa(13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, Metrics.s(8))
            }

            if isSearching || isFetchingDetail {
                ProgressView()
                    .tint(Theme.accent)
                    .padding(.top, Metrics.s(40))
                Spacer()
            } else if resultsEmpty && !query.isEmpty {
                ContentUnavailableView("No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No matches found for \"\(query)\""))
            } else if query.isEmpty {
                emptyPrompt
            } else {
                resultsGrid
            }
        }
        .onChange(of: query) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await runSearch()
            }
        }
    }

    private var resultsEmpty: Bool {
        kind == .movies ? movieResults.isEmpty : showResults.isEmpty
    }

    // MARK: - Results grid

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth),
                                        spacing: Metrics.shelfSpacing, alignment: .top)],
                      spacing: Metrics.shelfSpacing) {
                if kind == .movies {
                    ForEach(movieResults) { movie in
                        Button { Task { await selectMovie(movie) } } label: {
                            SearchPosterCard(title: movie.title,
                                             year: movie.releaseYear,
                                             posterPath: movie.poster_path,
                                             rating: nil)
                        }
                        .posterButtonStyle()
                    }
                } else {
                    ForEach(showResults) { show in
                        Button { Task { await selectShow(show) } } label: {
                            SearchPosterCard(title: show.name,
                                             year: show.firstAirYear,
                                             posterPath: show.poster_path,
                                             rating: nil)
                        }
                        .posterButtonStyle()
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, Metrics.s(14))
        }
    }

    // MARK: - Placeholder views

    private var emptyPrompt: some View {
        VStack(spacing: Metrics.s(16)) {
            Image(systemName: "magnifyingglass")
                .font(.casa(48))
                .foregroundStyle(Theme.textSecondary)
            Text("Search for a movie or TV show")
                .font(.casa(16))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noKeyView: some View {
        VStack(spacing: Metrics.s(16)) {
            Image(systemName: "key.slash")
                .font(.casa(48))
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: Metrics.s(6)) {
                Text("TMDB Key Required")
                    .font(.casa(18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Add your TMDB read access token in\nSettings → Online Services to enable search.")
                    .font(.casa(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.screenPadding)
    }

    // MARK: - Search

    private func triggerSearch() {
        searchTask?.cancel()
        searchTask = Task { await runSearch() }
    }

    @MainActor
    private func runSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let client = app.tmdbClient else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            if kind == .movies {
                movieResults = try await client.searchMovies(query: query)
            } else {
                showResults = try await client.searchTV(query: query)
            }
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func clearResults() {
        movieResults = []
        showResults = []
        searchError = nil
    }

    // MARK: - Selection

    @MainActor
    private func selectMovie(_ movie: TMDBMovie) async {
        guard let client = app.tmdbClient else { return }
        isFetchingDetail = true
        defer { isFetchingDetail = false }
        do {
            let detail = try await client.movieDetail(id: movie.id)
            let item = client.toMediaItem(detail)
            addAndNavigate(item)
        } catch {
            searchError = error.localizedDescription
        }
    }

    @MainActor
    private func selectShow(_ show: TMDBShow) async {
        guard let client = app.tmdbClient else { return }
        isFetchingDetail = true
        defer { isFetchingDetail = false }
        do {
            let detail = try await client.showDetail(id: show.id)
            let item = client.toMediaItem(detail)
            addAndNavigate(item)
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func addAndNavigate(_ item: MediaItem) {
        // Reuse an existing item by imdbID if already in the library.
        if let imdb = item.imdbID,
           let existing = app.items.first(where: { $0.imdbID == imdb }) {
            navPath.append(existing.id)
            return
        }
        app.addToLibrary(item)
        navPath.append(item.id)
    }
}

// MARK: - SearchPosterCard

private struct SearchPosterCard: View {
    let title: String
    let year: Int?
    let posterPath: String?
    let rating: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            posterImage
                .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitleLine)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: Metrics.posterWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let path = posterPath, let url = TMDBClient.posterURL(path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    fallbackArt
                @unknown default:
                    fallbackArt
                }
            }
        } else {
            fallbackArt
        }
    }

    private var fallbackArt: some View {
        ZStack {
            Rectangle().fill(Theme.surface)
            Text(title.prefix(2).uppercased())
                .font(.casa(28, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var subtitleLine: String {
        [year.map(String.init), rating].compactMap { $0 }.joined(separator: " · ")
    }
}
