// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// A title's page. A full-bleed hero with the title, scores, synopsis and the action buttons right on the
// image, then frosted panels for how it plays, subtitles and the cast.

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

    private var heroHeight: CGFloat {
        #if os(tvOS)
        return 800
        #else
        return sizeClass == .regular ? 460 : 300
        #endif
    }

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
            .navigationDestination(item: $pushedID) { id in
                DetailView(itemID: id)
            }
            .task(id: item.id) {
                related = await app.relatedTitles(for: item)
            }
            #endif
            .adaptiveSheet(isPresented: $showingStreams) {
                if let request = movieRequest {
                    StreamSourcesView(request: request, libraryItemID: item.id)
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

    /// Apple TV: the text sits on the picture, left aligned, with the focusable buttons under it.
    private func tvContent(_ decision: PlaybackDecision) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                hero(decision)

                if isPlayableTitle {
                    playbackCard(decision)
                }
                if !item.cast.isEmpty {
                    castRow
                }
            }
            .padding(.bottom, Metrics.sectionSpacing)
        }
    }

    // MARK: Hero

    /// On Apple TV the text sits on the image. On iPhone and iPad it starts at the bottom edge of the
    /// image and runs below it, where there is more room.
    private func hero(_ decision: PlaybackDecision) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                BackdropImage(path: item.backdropPath ?? item.posterPath, hue: item.artHue)
                // Dark from the left for the text, and into the page colour at the bottom.
                LinearGradient(colors: [Theme.background.opacity(0.9), Theme.background.opacity(0.45), Color.clear],
                               startPoint: .leading, endPoint: .trailing)
                    .opacity(Platform.isTV ? 1 : 0)
                LinearGradient(colors: [Color.clear, Theme.background.opacity(0.7), Theme.background],
                               startPoint: UnitPoint(x: 0.5, y: Platform.isTV ? 0.4 : 0.5), endPoint: .bottom)
                if Platform.isTV {
                    heroText(decision)
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.bottom, Metrics.s(14))
                }
            }
            .frame(height: heroHeight)
            .clipped()

            if !Platform.isTV {
                heroText(decision)
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.top, -Metrics.s(46))
            }
        }
    }

    private func heroText(_ decision: PlaybackDecision) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s(10)) {
            Text(item.tmdbShowID != nil ? "SERIES" : "MOVIE")
                .font(.casa(11, weight: .heavy))
                .tracking(Platform.isTV ? 5 : 2.5)
                .foregroundStyle(Theme.accent)

            Text(item.title)
                .font(.system(size: Platform.isTV ? 76 : 32, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 4)

            metaRow

            if !item.genres.isEmpty {
                Text(item.genres.joined(separator: "  ·  "))
                    .font(.casa(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            if !item.overview.isEmpty {
                Text(item.overview)
                    .font(.casa(14))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineLimit(Platform.isTV ? 3 : 4)
                    .frame(maxWidth: Platform.isTV ? 860 : .infinity, alignment: .leading)
                    .padding(.top, Metrics.s(2))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.s(10)) { actionButtons(decision) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.s(10)) { actionButtons(decision) }
                        .padding(.vertical, 4)
                }
            }
            .padding(.top, Metrics.s(8))

            subtitleRow

            if item.canResume && isPlayableTitle {
                HStack(spacing: Metrics.s(10)) {
                    ProgressBar(fraction: item.progressFraction)
                        .frame(width: Metrics.s(150))
                        .clipShape(Capsule())
                    Text(TimeFormat.timeLeft(item.remainingSeconds))
                        .font(.casa(12))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: Platform.isTV ? 1000 : .infinity, alignment: .leading)
    }

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

                    relatedShelf

                    if isPlayableTitle {
                        playbackCard(decision)
                    }
                    if !item.cast.isEmpty {
                        castRow
                    }
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

    #endif

    // MARK: Actions

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

            if movieRequest != nil {
                Button {
                    showingStreams = true
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(HeroButtonStyle(kind: .icon))
                .accessibilityLabel("Find other streams")
            }
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
            app.toggleFavorite(item.id)
        } label: {
            Image(systemName: item.isFavorite ? "heart.fill" : "heart")
        }
        .buttonStyle(HeroButtonStyle(kind: .icon))
        .accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites")

        Button {
            app.toggleWatched(item.id)
        } label: {
            Image(systemName: item.isWatched ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .buttonStyle(HeroButtonStyle(kind: .icon))
        .accessibilityLabel(item.isWatched ? "Mark as unwatched" : "Mark as watched")

        if item.tmdbShowID != nil && !needsEpisode {
            Button {
                showingEpisodes = true
            } label: {
                Label("Episodes", systemImage: "list.bullet")
            }
            .buttonStyle(HeroButtonStyle(kind: .secondary))
        }

        #if !os(tvOS)
        if let url = item.imdbURL {
            Link(destination: url) {
                Text("IMDb")
                    .font(.casa(13, weight: .heavy))
            }
            .buttonStyle(HeroButtonStyle(kind: .secondary))
            .accessibilityLabel("Open on IMDb")
        }
        #endif
    }

    private var episodeSeasonCount: Int { item.numberOfSeasons ?? 1 }

    // MARK: How it plays

    private func playbackCard(_ decision: PlaybackDecision) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s(14)) {
            DetailSectionTitle(title: "How it plays")

            HStack(spacing: Metrics.s(8)) {
                Image(systemName: decision.isPlayable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(decision.isPlayable ? Color(red: 0.36, green: 0.86, blue: 0.48) : Color.orange)
                Text(decision.badgeText)
                    .font(.casa(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: Platform.isTV ? 300 : 150), spacing: Metrics.s(10), alignment: .top)],
                      alignment: .leading, spacing: Metrics.s(10)) {
                SpecTile(symbol: "shippingbox.fill", label: "Container", value: item.file.container.displayName)
                SpecTile(symbol: "film.fill", label: "Video",
                         value: "\(item.file.videoCodec.displayName) · \(item.file.width)×\(item.file.height)")
                SpecTile(symbol: "waveform", label: "Audio",
                         value: item.file.audioCodecs.isEmpty
                            ? "None"
                            : item.file.audioCodecs.map { $0.displayName }.joined(separator: ", "))
                SpecTile(symbol: "captions.bubble.fill", label: "Subtitles",
                         value: item.file.subtitleFormats.isEmpty
                            ? "None"
                            : item.file.subtitleFormats.map { $0.rawValue.uppercased() }.joined(separator: ", "))
                if let size = item.file.sizeBytes {
                    SpecTile(symbol: "internaldrive.fill", label: "Size",
                             value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                }
                if !item.sourceName.isEmpty {
                    SpecTile(symbol: "antenna.radiowaves.left.and.right", label: "Source", value: item.sourceName)
                }
            }
        }
        .padding(Metrics.s(18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.horizontal, Metrics.screenPadding)
        .focusableOnTV()
    }

    // MARK: Cast

    private var castRow: some View {
        Shelf(title: "Cast") {
            ForEach(Array(item.cast.enumerated()), id: \.element.id) { index, member in
                CastTile(member: member,
                         hue: (item.artHue + Double(index) * 37).truncatingRemainder(dividingBy: 360))
                    .focusableOnTV()
            }
        }
    }
}

// MARK: - Pieces

/// A section heading with a short amber bar in front of it.
private struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        HStack(spacing: Metrics.s(10)) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: Metrics.s(4), height: Metrics.s(20))
            Text(title)
                .font(.casa(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

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

/// One fact about the file: an icon, what it is and its value.
private struct SpecTile: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Metrics.s(12)) {
            Image(systemName: symbol)
                .font(.casa(16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: Metrics.s(38), height: Metrics.s(38))
                .background(Theme.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.casa(10, weight: .bold))
                    .tracking(Platform.isTV ? 2 : 1)
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.s(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Metrics.s(12), style: .continuous))
    }
}

/// A cast member: round portrait with the name and role. On Apple TV the focused one grows a white ring.
private struct CastTile: View {
    let member: CastMember
    let hue: Double
    @Environment(\.isFocused) private var isFocused

    private var size: CGFloat { Platform.isTV ? 132 : 84 }

    var body: some View {
        VStack(spacing: Metrics.s(8)) {
            AsyncImage(url: member.profilePath.flatMap(TMDBClient.posterURL)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
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
        .frame(width: Platform.isTV ? 190 : 104)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
