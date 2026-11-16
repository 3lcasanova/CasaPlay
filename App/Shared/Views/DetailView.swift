// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// A title's page, laid out like the Apple TV app's. A full-bleed hero with the title, synopsis and the
// buttons; scrolling melts the picture into a blurred colour wash, with the episodes, related titles, cast,
// how to watch, About, Information, Languages and Accessibility below.

import SwiftUI
import CasaPlayKit

struct DetailView: View {
    @Environment(AppState.self) private var app
    let itemID: UUID

    var body: some View {
        if let item = app.item(id: itemID) {
            DetailContent(item: item)
        } else {
            ContentUnavailableView("Title not found", systemImage: "film")
        }
    }
}

private struct DetailContent: View {
    @Environment(AppState.self) private var app
    let item: MediaItem
    @State private var showingEpisodes = false
    @State private var showingStreams = false
    /// Titles viewers of this one also watch, and the title opened from that shelf.
    @State private var related: [DiscoverTitle] = []
    @State private var pushedID: UUID?
    /// The season shown in the episode shelf, its episodes, and the episode being opened for streams.
    @State private var selectedSeason = 1
    @State private var episodes: [EpisodeInfo] = []
    @State private var streamingEpisode: EpisodeStreamTarget?
    #if !os(tvOS)
    /// The title's trailers, best first, and whether the in-app trailer player is open.
    @State private var trailers: [Trailer] = []
    @State private var showingTrailer = false
    #endif
    #if os(tvOS)
    /// How far the page has scrolled, for the picture to melt into the colour wash.
    @State private var scrollOffset: CGFloat = 0
    #endif
    #if !os(tvOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// A film found online with no local file: playing it means picking a stream.
    private var movieRequest: ContentRequest? {
        guard item.tmdbShowID == nil, let imdb = item.imdbID, !imdb.isEmpty else { return nil }
        return .movie(id: imdb, title: item.title, year: item.year)
    }

    private var needsEpisode: Bool { item.tmdbShowID != nil && item.streamURL == nil }

    private var needsStream: Bool {
        movieRequest != nil && item.streamURL == nil && item.sourceName.isEmpty
    }

    private var isPlayableTitle: Bool { !needsStream && !needsEpisode }

    var body: some View {
        let decision = app.router.decide(for: item.file)

        content(decision)
            .screenBackground()
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if let url = item.imdbURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url)
                    }
                }
            }
            #endif
            .navigationDestination(item: $pushedID) { id in
                DetailView(itemID: id)
            }
            .task(id: item.id) {
                related = await app.relatedTitles(for: item)
            }
            #if !os(tvOS)
            .task(id: item.id) {
                trailers = []
                trailers = await app.trailers(for: item)
            }
            .fullScreenCover(isPresented: $showingTrailer) {
                TrailerScreen(title: item.title, trailers: trailers)
            }
            #endif
            .task(id: EpisodeLoadKey(id: item.id, season: selectedSeason)) {
                await loadEpisodes()
            }
            .adaptiveSheet(item: $streamingEpisode) { target in
                StreamSourcesView(request: target.request, libraryItemID: target.episodeID, resumeLastStream: true)
            }
            .adaptiveSheet(isPresented: $showingStreams) {
                if let request = movieRequest {
                    // Resume plays the last stream by itself; "More Streams" on a title that already has one still lists.
                    StreamSourcesView(request: request, libraryItemID: item.id, resumeLastStream: needsStream)
                }
            }
            .adaptiveSheet(isPresented: $showingEpisodes) {
                if item.tmdbShowID != nil {
                    EpisodesView(show: item,
                                 totalSeasons: episodeSeasonCount)
                        .environment(app)
                }
            }
            .task(id: item.id) {
                await app.refreshIMDb(for: item.id)
                app.findEnglishSubtitles(for: item.id)
            }
    }

    @ViewBuilder
    private func content(_ decision: PlaybackDecision) -> some View {
        #if os(tvOS)
        tvContent(decision)
        #else
        phoneContent(decision)
        #endif
    }

    #if os(tvOS)

    /// Apple TV: one fixed picture behind the page. It starts sharp, with the text on it, and melts into a
    /// blurred colour wash as the page scrolls up over it, with the title pinned at the top.
    private func tvContent(_ decision: PlaybackDecision) -> some View {
        ZStack(alignment: .top) {
            tvBackdrop
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tvHero(decision)
                    lowerSections(decision)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: DetailScrollKey.self,
                                               value: -proxy.frame(in: .named("detailScroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "detailScroll")
            .onPreferenceChange(DetailScrollKey.self) { value in
                // In steps, so the page isn't redrawn for every pixel it scrolls.
                let step = (value / 12).rounded() * 12
                if step != scrollOffset { scrollOffset = step }
            }

            tvPinnedTitle
        }
    }

    /// 0 while the hero is showing, 1 once the page has scrolled up over it.
    private var washProgress: Double {
        min(max(Double(scrollOffset - 160) / 420, 0), 1)
    }

    private var tvBackdrop: some View {
        ZStack {
            ZStack {
                BackdropImage(path: item.backdropPath ?? item.posterPath, hue: item.artHue,
                              fullSize: true, alignment: .top)
                LinearGradient(colors: [Color.black.opacity(0.78), Color.black.opacity(0.3), Color.clear],
                               startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))
                LinearGradient(colors: [Color.clear, Color.black.opacity(0.7)],
                               startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
            }
            .opacity(1 - washProgress)

            ZStack {
                BackdropImage(path: item.backdropPath ?? item.posterPath, hue: item.artHue)
                    .scaleEffect(1.3)
                    .blur(radius: 70)
                    .saturation(1.6)
                Color.black.opacity(0.32)
                LinearGradient(colors: [Color.clear, Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            }
            .opacity(washProgress)
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var tvPinnedTitle: some View {
        Text(item.title)
            .font(.system(size: 58, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 220)
            .padding(.top, 30)
            .opacity(washProgress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The text sits bottom left on the picture and "Starring" bottom right. The first shelf peeks in under it.
    private func tvHero(_ decision: PlaybackDecision) -> some View {
        ZStack(alignment: .bottomLeading) {
            tvHeroText(decision)
                .padding(.leading, Metrics.screenPadding)
                .padding(.bottom, 22)
            if !item.cast.isEmpty {
                Text("Starring " + item.cast.prefix(3).map(\.name).joined(separator: ", "))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 360, alignment: .trailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, Metrics.screenPadding)
                    .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 840)
    }

    private func tvHeroText(_ decision: PlaybackDecision) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title)
                .font(.system(size: 86, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 4)

            Text(tvKindLine)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)

            if !item.overview.isEmpty {
                Text(item.overview)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(3)
                    .frame(maxWidth: 820, alignment: .leading)
            }

            metaRow

            HStack(spacing: 16) { actionButtons(decision) }
                .padding(.top, 6)

            if item.canResume && isPlayableTitle {
                HStack(spacing: 16) {
                    ProgressBar(fraction: item.progressFraction)
                        .frame(width: 240)
                        .clipShape(Capsule())
                    Text(TimeFormat.timeLeft(item.remainingSeconds))
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: 1000, alignment: .leading)
    }

    private var tvKindLine: String {
        ([item.tmdbShowID != nil ? "TV Show" : "Movie"] + item.genres.prefix(3)).joined(separator: " · ")
    }

    #endif

    /// Subtitles are always here on the page: Off and each loaded track. English is found and switched on
    /// by itself when the page opens.
    private var subtitleRow: some View {
        let options = app.subtitleOptions(for: item.id)
        let active = app.activeSubtitle(for: item.id)
        let note: String? = options.isEmpty
            ? (app.openSubtitlesClient == nil
               ? "Add your OpenSubtitles key in Profile › Online services to get English subtitles automatically."
               : app.autoSubtitleNote[item.id])
            : nil

        return VStack(alignment: .leading, spacing: Metrics.s(2)) {
            HStack(spacing: Metrics.s(10)) {
                Image(systemName: active == nil ? "captions.bubble" : "captions.bubble.fill")
                    .font(.casa(16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .accessibilityHidden(true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.s(8)) {
                        ChipButton(title: "Off", isSelected: active == nil) {
                            app.selectSubtitle(nil, for: item.id)
                        }
                        ForEach(options) { option in
                            ChipButton(title: option.track.displayName, isSelected: active?.id == option.id) {
                                app.selectSubtitle(option.id, for: item.id)
                            }
                        }
                    }
                    .padding(.horizontal, Platform.isTV ? 8 : 0)
                    .padding(.vertical, Platform.isTV ? 14 : 2)
                }
            }
            if let note {
                Text(note)
                    .font(.casa(12))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.leading, Metrics.s(26))
            }
        }
    }

    #if os(tvOS)

    private var metaParts: [String] {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        if item.tmdbShowID != nil {
            if let seasons = item.numberOfSeasons {
                parts.append(seasons == 1 ? "1 season" : "\(seasons) seasons")
            }
        } else if item.runtimeSeconds > 0 {
            parts.append(TimeFormat.runtime(item.runtimeSeconds))
        }
        if let rating = item.rating, !rating.isEmpty { parts.append(rating) }
        return parts
    }

    private var metaRow: some View {
        HStack(spacing: Metrics.s(12)) {
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: "  ·  "))
                    .font(.casa(13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            if let rating = item.imdbRating {
                IMDbBadge(rating: rating, votes: item.imdbVotes)
            }
            if let tmdb = item.tmdbRating, tmdb > 0 {
                ScoreStrip(rating: tmdb)
            }
            if isPlayableTitle {
                ForEach(item.file.badges, id: \.self) { badge in
                    Pill(text: badge)
                }
            }
        }
    }

    #endif

    // MARK: iPhone and iPad

    #if !os(tvOS)

    private var isWide: Bool { sizeClass == .regular }

    /// The Apple TV app layout: the picture runs to the top edge and fades into black, and everything
    /// is centred over the fade: title, white Play button, a "+" and a menu, the synopsis, the facts.
    private func phoneContent(_ decision: PlaybackDecision) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                phoneArt

                VStack(alignment: .leading, spacing: 30) {
                    phoneHeader(decision)

                    lowerSections(decision)
                }
                .frame(maxWidth: isWide ? 720 : .infinity)
                .padding(.top, isWide ? -230 : -250)
                .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var phoneArt: some View {
        ZStack(alignment: .bottom) {
            HeroArt(posterPath: item.posterPath, backdropPath: item.backdropPath, hue: item.artHue, preferPoster: !isWide)
            LinearGradient(colors: [Color.black.opacity(0.5), Color.clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.28))
            LinearGradient(colors: [Color.clear, Theme.background.opacity(0.85), Theme.background],
                           startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: UnitPoint(x: 0.5, y: 0.97))
        }
        .frame(height: isWide ? 520 : 470)
        .clipped()
        .ignoresSafeArea(edges: .top)
    }

    private func phoneHeader(_ decision: PlaybackDecision) -> some View {
        VStack(spacing: 12) {
            Text(item.title)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 3)

            Text(kindLine)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)

            primaryAction(decision)
                .frame(maxWidth: 260)
                .padding(.top, 4)

            secondaryRow(decision)

            subtitleRow
                .frame(maxWidth: .infinity, alignment: .leading)

            if !item.overview.isEmpty {
                SynopsisText(text: item.overview)
            }

            phoneInfoRow
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    private var kindLine: String {
        ([item.tmdbShowID != nil ? "Series" : "Movie"] + item.genres.prefix(3)).joined(separator: " · ")
    }

    /// The big white button.
    @ViewBuilder
    private func primaryAction(_ decision: PlaybackDecision) -> some View {
        if needsEpisode {
            Button {
                showingEpisodes = true
            } label: {
                Text("Episodes").frame(maxWidth: .infinity)
            }
            .buttonStyle(HeroButtonStyle(kind: .primary))
        } else if needsStream {
            Button {
                showingStreams = true
            } label: {
                Text(item.canResume ? "Resume · \(TimeFormat.clock(item.progressSeconds))" : "Find Streams")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HeroButtonStyle(kind: .primary))
        } else {
            Button {
                app.play(item)
            } label: {
                Text(item.canResume ? "Resume · \(TimeFormat.clock(item.progressSeconds))" : "Play")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HeroButtonStyle(kind: .primary))
            .disabled(!decision.isPlayable)
        }
    }

    /// A text button, the "+" (favourites) and the "..." menu.
    private func secondaryRow(_ decision: PlaybackDecision) -> some View {
        HStack(spacing: 12) {
            if item.tmdbShowID != nil && !needsEpisode {
                Button {
                    showingEpisodes = true
                } label: {
                    Text("Episodes").frame(minWidth: 110)
                }
                .buttonStyle(HeroButtonStyle(kind: .secondary))
            } else if movieRequest != nil && !needsStream {
                Button {
                    showingStreams = true
                } label: {
                    Text("More Streams").frame(minWidth: 110)
                }
                .buttonStyle(HeroButtonStyle(kind: .secondary))
            }

            Button {
                app.toggleFavorite(item.id)
            } label: {
                Image(systemName: item.isFavorite ? "checkmark" : "plus")
            }
            .buttonStyle(HeroButtonStyle(kind: .icon))
            .accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites")

            if !trailers.isEmpty {
                Button {
                    showingTrailer = true
                } label: {
                    Image(systemName: "play.rectangle")
                }
                .buttonStyle(HeroButtonStyle(kind: .icon))
                .accessibilityLabel("Play trailer")
            }

            moreMenu(decision)
        }
    }

    private func moreMenu(_ decision: PlaybackDecision) -> some View {
        Menu {
            Button {
                app.toggleWatched(item.id)
            } label: {
                Label(item.isWatched ? "Mark as Unwatched" : "Mark as Watched",
                      systemImage: item.isWatched ? "eye.slash" : "checkmark.circle")
            }
            if item.canResume && isPlayableTitle {
                Button {
                    app.startOver(item.id)
                } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                }
                .disabled(!decision.isPlayable)
            }
            if let url = item.imdbURL {
                Link(destination: url) {
                    Label("Open on IMDb", systemImage: "arrow.up.right.square")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Capsule().fill(Color.white.opacity(0.2)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More options")
    }

    private var phoneMetaParts: [String] {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        if item.tmdbShowID != nil {
            if let seasons = item.numberOfSeasons {
                parts.append(seasons == 1 ? "1 season" : "\(seasons) seasons")
            }
        } else if item.runtimeSeconds > 0 {
            parts.append(TimeFormat.runtime(item.runtimeSeconds))
        }
        return parts
    }

    /// 2005 · 1h 56min, the score, the age rating and what the file offers, as small badges.
    private var phoneInfoRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !phoneMetaParts.isEmpty {
                    Text(phoneMetaParts.joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .fixedSize()
                }
                if let tmdb = item.tmdbRating, tmdb > 0, let percent = TMDBScore.percent(tmdb) {
                    HStack(spacing: 3) {
                        Image(systemName: "hand.thumbsup.fill")
                            .foregroundStyle(Color(red: 0.36, green: 0.86, blue: 0.48))
                        Text("\(percent)%")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                }
                if let imdb = item.imdbRating {
                    IMDbBadge(rating: imdb)
                }
                if let rating = item.rating, !rating.isEmpty {
                    InfoBadge(text: rating.uppercased())
                }
                if isPlayableTitle {
                    ForEach(item.file.badges, id: \.self) { badge in
                        InfoBadge(text: badge)
                    }
                }
                if app.activeSubtitle(for: item.id) != nil {
                    InfoBadge(text: "CC")
                }
            }
        }
    }

    #endif

    // MARK: Actions (Apple TV)

    #if os(tvOS)
    @ViewBuilder
    private func actionButtons(_ decision: PlaybackDecision) -> some View {
        if needsEpisode {
            Button {
                showingEpisodes = true
            } label: {
                Label("Episodes", systemImage: "list.bullet")
            }
            .buttonStyle(HeroButtonStyle(kind: .primary))
        } else if needsStream {
            Button {
                showingStreams = true
            } label: {
                Label(
                    item.canResume ? "Resume · \(TimeFormat.clock(item.progressSeconds))" : "Find Streams",
                    systemImage: "play.fill"
                )
            }
            .buttonStyle(HeroButtonStyle(kind: .primary))
        } else {
            Button {
                app.play(item)
            } label: {
                Label(
                    item.canResume ? "Resume · \(TimeFormat.clock(item.progressSeconds))" : "Play",
                    systemImage: "play.fill"
                )
            }
            .buttonStyle(HeroButtonStyle(kind: .primary))
            .disabled(!decision.isPlayable)
        }

        if item.tmdbShowID != nil && !needsEpisode {
            Button {
                showingEpisodes = true
            } label: {
                Text("All Episodes")
            }
            .buttonStyle(HeroButtonStyle(kind: .secondary))
        }

        Button {
            app.toggleFavorite(item.id)
        } label: {
            Image(systemName: item.isFavorite ? "checkmark" : "plus")
        }
        .buttonStyle(HeroButtonStyle(kind: .icon))
        .accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites")

        if movieRequest != nil && !needsStream {
            Button {
                showingStreams = true
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(HeroButtonStyle(kind: .icon))
            .accessibilityLabel("Find other streams")
        }

        if item.canResume && isPlayableTitle {
            Button {
                app.startOver(item.id)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(HeroButtonStyle(kind: .icon))
            .disabled(!decision.isPlayable)
            .accessibilityLabel("Start over")
        }

        Button {
            app.toggleWatched(item.id)
        } label: {
            Image(systemName: item.isWatched ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .buttonStyle(HeroButtonStyle(kind: .icon))
        .accessibilityLabel(item.isWatched ? "Mark as unwatched" : "Mark as watched")
    }
    #endif

    // MARK: Related

    @ViewBuilder
    private var relatedShelf: some View {
        if !related.isEmpty {
            Shelf(title: "Related") {
                ForEach(related) { title in
                    Button {
                        openRelated(title)
                    } label: {
                        ApplePosterCard(title: title.title, posterPath: title.posterPath)
                    }
                    .posterButtonStyle()
                }
            }
        }
    }

    private func openRelated(_ title: DiscoverTitle) {
        Task { @MainActor in
            let opened: UUID?
            if title.isShow {
                opened = try? await app.openShow(tmdbID: title.tmdbID)
            } else {
                opened = try? await app.openMovie(tmdbID: title.tmdbID)
            }
            if let opened { pushedID = opened }
        }
    }

    // MARK: Under the hero (every platform)

    /// Episodes, related titles, cast, how to watch, About and the details, as in the Apple TV app.
    private func lowerSections(_ decision: PlaybackDecision) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            episodesSection
            relatedShelf
            if !item.cast.isEmpty { castRow }
            if isPlayableTitle { howToWatch(decision) }
            aboutAndDetails
        }
        .padding(.top, Platform.isTV ? 12 : 0)
        .padding(.bottom, Metrics.sectionSpacing)
    }

    // MARK: Episodes

    @ViewBuilder
    private var episodesSection: some View {
        if item.tmdbShowID != nil, app.tmdbClient != nil {
            VStack(alignment: .leading, spacing: Metrics.s(6)) {
                if episodeSeasonCount > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Metrics.s(8)) {
                            ForEach(1...episodeSeasonCount, id: \.self) { number in
                                ChipButton(title: "Season \(number)", isSelected: selectedSeason == number) {
                                    selectedSeason = number
                                }
                            }
                        }
                        .padding(.horizontal, AppleMetrics.edge)
                        .padding(.vertical, Platform.isTV ? 14 : 2)
                    }
                }
                if !episodes.isEmpty {
                    Shelf(title: "Season \(selectedSeason)") {
                        ForEach(episodes) { episode in
                            Button {
                                streamEpisode(episode)
                            } label: {
                                EpisodeCard(episode: episode)
                            }
                            .buttonStyle(FlatCardButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private func loadEpisodes() async {
        guard let showID = item.tmdbShowID, let tmdb = app.tmdbClient else {
            episodes = []
            return
        }
        let season = selectedSeason
        do {
            let detail = try await tmdb.seasonDetail(showID: showID, season: season)
            guard !Task.isCancelled else { return }
            episodes = (detail.episodes ?? []).map(EpisodeInfo.init(tmdb:))
        } catch {
            guard !Task.isCancelled else { return }
            episodes = []
        }
    }

    /// Opens the streams for one episode, the same way the full episode list does.
    private func streamEpisode(_ episode: EpisodeInfo) {
        guard let seriesID = item.imdbID, !seriesID.isEmpty else {
            showingEpisodes = true
            return
        }
        let request = ContentRequest.episode(
            seriesID: seriesID,
            title: item.title,
            season: episode.season,
            episode: episode.number,
            year: item.year
        )
        let episodeID = app.registerEpisode(show: item, season: episode.season,
                                            episode: episode.number, runtimeMinutes: episode.runtimeMinutes)
        streamingEpisode = EpisodeStreamTarget(request: request, episodeID: episodeID)
    }

    private var episodeSeasonCount: Int { item.numberOfSeasons ?? 1 }

    // MARK: How to Watch

    private func howToWatch(_ decision: PlaybackDecision) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            ShelfTitle(title: "How to Watch")
            VStack(alignment: .leading, spacing: Metrics.s(6)) {
                HStack(spacing: Metrics.s(12)) {
                    Image(systemName: decision.isPlayable ? "play.rectangle.fill" : "exclamationmark.triangle.fill")
                        .font(.casa(24))
                        .foregroundStyle(decision.isPlayable ? Theme.accent : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(decision.isPlayable ? "Watch on CasaPlay" : "Can't play on this device")
                            .font(.casa(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(decision.badgeText)
                            .font(.casa(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                ForEach(decision.reasons, id: \.self) { reason in
                    Text("Apple's player can't open: \(reason)")
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(decision.notes, id: \.self) { note in
                    Text(note)
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Metrics.s(14))
            .frame(maxWidth: Platform.isTV ? 760 : .infinity, alignment: .leading)
            .modifier(FocusGlass())
            .focusableOnTV()
        }
        .padding(.horizontal, AppleMetrics.edge)
    }

    // MARK: About, Information, Languages, Accessibility

    private var aboutAndDetails: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            aboutPanel
            detailsColumns
        }
        .padding(.horizontal, AppleMetrics.edge)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.casa(17, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.casa(11))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.casa(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            sectionHeading("About")
            VStack(alignment: .leading, spacing: Metrics.s(6)) {
                Text(item.title)
                    .font(.casa(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if !item.genres.isEmpty {
                    Text(item.genres.joined(separator: ", "))
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                if !item.overview.isEmpty {
                    Text(item.overview)
                        .font(.casa(13))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(Platform.isTV ? 6 : 10)
                }
            }
            .padding(Metrics.s(14))
            .frame(maxWidth: Platform.isTV ? 760 : .infinity, alignment: .leading)
            .modifier(FocusGlass())
            .focusableOnTV()
        }
    }

    @ViewBuilder
    private var detailsColumns: some View {
        #if os(tvOS)
        HStack(alignment: .top, spacing: 48) {
            informationColumn.frame(width: 440, alignment: .leading)
            languagesColumn.frame(maxWidth: 700, alignment: .leading)
            accessibilityColumn.frame(width: 480, alignment: .leading)
        }
        #else
        VStack(alignment: .leading, spacing: 22) {
            informationColumn
            languagesColumn
            accessibilityColumn
        }
        #endif
    }

    private var informationRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let year = item.year { rows.append(("Released", String(year))) }
        if item.tmdbShowID != nil {
            if let seasons = item.numberOfSeasons { rows.append(("Seasons", String(seasons))) }
        } else if item.runtimeSeconds > 0 {
            rows.append(("Runtime", TimeFormat.runtime(item.runtimeSeconds)))
        }
        if let rating = item.rating, !rating.isEmpty { rows.append(("Rated", rating)) }
        if isPlayableTitle {
            rows.append(("Container", item.file.container.displayName))
            rows.append(("Video", "\(item.file.videoCodec.displayName) · \(item.file.width)×\(item.file.height)"))
            if let size = item.file.sizeBytes {
                rows.append(("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
            }
        }
        if !item.sourceName.isEmpty { rows.append(("Source", item.sourceName)) }
        return rows
    }

    private var informationColumn: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            sectionHeading("Information")
            VStack(alignment: .leading, spacing: Metrics.s(10)) {
                ForEach(Array(informationRows.enumerated()), id: \.offset) { _, row in
                    labelled(row.label, row.value)
                }
            }
            .padding(Metrics.s(14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(FocusGlass())
            .focusableOnTV()
        }
    }

    private var languagesColumn: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            sectionHeading("Languages")
            if isPlayableTitle {
                labelled("Audio", item.file.audioCodecs.isEmpty
                         ? "None"
                         : item.file.audioCodecs.map { $0.displayName }.joined(separator: ", "))
            }
            #if os(tvOS)
            Text("Subtitles")
                .font(.casa(11))
                .foregroundStyle(Theme.textSecondary)
            subtitleRow
            #endif
            if isPlayableTitle, !item.file.subtitleFormats.isEmpty {
                labelled("In the file",
                         item.file.subtitleFormats.map { $0.rawValue.uppercased() }.joined(separator: ", "))
            }
        }
    }

    private var accessibilityColumn: some View {
        let hasSubtitles = !app.subtitleOptions(for: item.id).isEmpty || !item.file.subtitleFormats.isEmpty
        return VStack(alignment: .leading, spacing: Metrics.s(8)) {
            sectionHeading("Accessibility")
            HStack(alignment: .top, spacing: Metrics.s(10)) {
                Text("CC")
                    .font(.casa(10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, Metrics.s(5))
                    .padding(.vertical, Metrics.s(1))
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.s(4), style: .continuous)
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                    )
                Text(hasSubtitles
                     ? "Closed captions and subtitles are available for this title."
                     : "No subtitles found for this title yet.")
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cast

    private var castRow: some View {
        Shelf(title: "Cast & Crew") {
            ForEach(Array(item.cast.enumerated()), id: \.element.id) { index, member in
                CastTile(member: member,
                         hue: (item.artHue + Double(index) * 37).truncatingRemainder(dividingBy: 360))
                    .focusableOnTV()
            }
        }
    }
}

// MARK: - Pieces

/// TMDB score as a star rating and a percentage.
private struct ScoreStrip: View {
    let rating: Double

    var body: some View {
        HStack(spacing: Metrics.s(8)) {
            HStack(spacing: Metrics.s(3)) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.20))
                Text(String(format: "%.1f", rating))
            }
            if let percent = TMDBScore.percent(rating) {
                HStack(spacing: Metrics.s(3)) {
                    Image(systemName: "hand.thumbsup.fill")
                        .foregroundStyle(Color(red: 0.36, green: 0.86, blue: 0.48))
                    Text("\(percent)%")
                }
            }
        }
        .font(.casa(13, weight: .bold))
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("TMDB score \(String(format: "%.1f", rating)) out of 10")
    }
}

/// A cast member: round portrait with the name and role. On Apple TV the focused one grows a white ring.
private struct CastTile: View {
    let member: CastMember
    let hue: Double
    @Environment(\.isFocused) private var isFocused

    private var size: CGFloat { Platform.isTV ? 150 : 84 }

    var body: some View {
        VStack(spacing: Metrics.s(8)) {
            CachedAsyncImage(url: member.profilePath.flatMap(TMDBClient.posterURL)) { phase in
                if let image = phase.image {
                    // Faces sit near the top of a portrait, so keep the top and trim the bottom.
                    image.resizable().scaledToFill().frame(width: size, height: size, alignment: .top)
                } else {
                    AvatarView(text: member.initials, hue: hue, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(isFocused ? Color.white : Color.white.opacity(0.14),
                                      lineWidth: isFocused ? 4 : 1)
            )
            .scaleEffect(isFocused ? 1.1 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 16, y: 8)
            .accessibilityHidden(true)

            Text(member.name)
                .font(.casa(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(member.role)
                .font(.casa(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Platform.isTV ? 210 : 104)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Episode shelf pieces

/// Where the page has scrolled to (Apple TV), so the picture can melt into the colour wash.
private struct DetailScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Reloads the episode shelf when the show or the season changes.
private struct EpisodeLoadKey: Equatable {
    let id: UUID
    let season: Int
}

/// The episode picked on the page, waiting for its list of streams.
private struct EpisodeStreamTarget: Identifiable {
    let id = UUID()
    let request: ContentRequest
    let episodeID: UUID
}

/// A card that draws nothing of its own: the label shows its own focus.
private struct FlatCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A frosted panel that turns lighter and lifts a little while it has focus on Apple TV.
private struct FocusGlass: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Metrics.s(14), style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.28 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.s(14), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .scaleEffect(isFocused ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// One episode: the still, "EPISODE 3", the title, a short summary and the air date. The focused one
/// sits on a light glass card.
private struct EpisodeCard: View {
    let episode: EpisodeInfo
    @Environment(\.isFocused) private var isFocused

    private var width: CGFloat { Metrics.landscapeWidth }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var airDateText: String? {
        guard let raw = episode.airDate, raw.count >= 10,
              let date = Self.parser.date(from: String(raw.prefix(10))) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            CachedAsyncImage(url: episode.imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let minutes = episode.runtimeMinutes, minutes > 0 {
                    Text("\(minutes) min")
                        .font(.casa(10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Metrics.s(6))
                        .padding(.vertical, Metrics.s(2))
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(Metrics.s(6))
                }
            }

            VStack(alignment: .leading, spacing: Metrics.s(2)) {
                Text("EPISODE \(episode.number)")
                    .font(.casa(9, weight: .bold))
                    .tracking(Platform.isTV ? 2 : 1)
                    .foregroundStyle(Theme.textSecondary)
                Text(episode.name)
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(Platform.isTV ? 3 : 2)
                }
                if let airDateText {
                    Text(airDateText)
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(width: width, height: Metrics.s(Platform.isTV ? 104 : 96), alignment: .topLeading)
        }
        .padding(Metrics.s(8))
        .background(
            RoundedRectangle(cornerRadius: Metrics.s(14), style: .continuous)
                .fill(Color.white.opacity(isFocused ? 0.26 : 0))
        )
        .scaleEffect(isFocused ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
