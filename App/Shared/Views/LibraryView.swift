// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct LibraryView: View {
    enum Mode {
        case all, favorites
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case fourK = "4K"
        case hdr = "HDR"
        case unwatched = "Unwatched"

        var id: String { rawValue }

        func matches(_ item: MediaItem) -> Bool {
            switch self {
            case .all: return true
            case .fourK: return item.file.is4K
            case .hdr: return item.file.hdr.isHDR
            case .unwatched: return !item.isWatched
            }
        }
    }

    @Environment(AppState.self) private var app
    let mode: Mode
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var path: [UUID] = []
    @State private var isOpening = false
    @State private var openError: String?

    private var opener: DiscoverOpener {
        DiscoverOpener(app: app,
                       push: { path.append($0) },
                       setBusy: { isOpening = $0 },
                       setError: { openError = $0 })
    }

    /// Popular films not already in the library, shown below it on the Movies tab.
    private var popular: [DiscoverTitle] {
        guard mode == .all else { return [] }
        let owned = Set(app.items.map { $0.title.lowercased() })
        return app.discover.popularMovies
            .filter { !owned.contains($0.title.lowercased()) }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var visibleItems: [MediaItem] {
        let base = (mode == .all) ? app.library : app.favorites
        return base
            .filter { filter.matches($0) }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.shelfSpacing, alignment: .top)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(14)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Metrics.s(8)) {
                            ForEach(Filter.allCases) { option in
                                ChipButton(title: option.rawValue, isSelected: option == filter) {
                                    filter = option
                                }
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.vertical, Platform.isTV ? 14 : 0)
                    }

                    if mode == .all && app.tmdbClient == nil && app.items.isEmpty {
                        TMDBKeyNotice()
                    }

                    if let openError {
                        Text(openError)
                            .font(.casa(13))
                            .foregroundStyle(.red)
                            .padding(.horizontal, Metrics.screenPadding)
                    }

                    if visibleItems.isEmpty {
                        if mode == .favorites || !query.isEmpty || filter != .all {
                            ContentUnavailableView(
                                mode == .favorites && query.isEmpty ? "No favorites yet" : "Nothing found",
                                systemImage: mode == .favorites ? "heart" : "film",
                                description: Text(mode == .favorites && query.isEmpty
                                    ? "Tap the heart on a title to keep it here."
                                    : "Try a different search or filter.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, Metrics.sectionSpacing)
                        }
                    } else {
                        if mode == .all {
                            sectionTitle("Your Library")
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.sectionSpacing / 2) {
                            ForEach(visibleItems) { item in
                                NavigationLink(value: item.id) {
                                    PosterCard(item: item)
                                }
                                .posterButtonStyle()
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                    }

                    if !popular.isEmpty && filter == .all {
                        sectionTitle("Popular Movies")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.sectionSpacing / 2) {
                            ForEach(popular) { title in
                                Button { opener.open(title) } label: {
                                    SearchPosterCard(
                                        title: title.title,
                                        year: title.year,
                                        posterPath: title.posterPath,
                                        rating: title.rating.map { String(format: "★ %.1f", $0) }
                                    )
                                }
                                .posterButtonStyle()
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                    }
                }
                .padding(.bottom, Metrics.sectionSpacing)
            }
            .background(Theme.background.ignoresSafeArea())
            .overlay {
                if isOpening {
                    ProgressView().tint(Theme.accent)
                }
            }
            .task(id: app.tmdbClient == nil) {
                await app.discover.loadIfNeeded(app.tmdbClient)
            }
            .navigationTitle(mode == .all ? "Movies" : "Favorites")
            .searchable(text: $query)
            .navigationDestination(for: UUID.self) { id in
                DetailView(itemID: id)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.casa(19, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Metrics.screenPadding)
    }
}
