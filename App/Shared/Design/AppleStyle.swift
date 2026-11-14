// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The Apple TV app look: shelves with a chevron, ranked "Top 10" posters, wide Continue Watching
// cards, round glass buttons, the "MORE" synopsis, and on iPhone and iPad the swipeable billboard
// at the top of Home.

import SwiftUI
import CasaPlayKit
#if canImport(UIKit)
import UIKit
#endif

enum AppleMetrics {
    /// True on an iPad.
    static var isPad: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    /// A poster in a shelf. Three and a bit fit across an iPhone, seven across an iPad.
    static var poster: CGFloat { Platform.isTV ? 250 : (isPad ? 148 : 112) }
    /// A wide Continue Watching card.
    static var wide: CGFloat { Platform.isTV ? 340 : (isPad ? 260 : 270) }
    /// A Continue Watching card is 16:9, a little less wide on an iPad.
    static var wideHeightRatio: CGFloat { Platform.isTV ? 9.0 / 16.0 : (isPad ? 0.7 : 9.0 / 16.0) }
    /// The space between cards in a shelf.
    static var gap: CGFloat { Platform.isTV ? 40 : (isPad ? 20 : 14) }
    /// The left and right margin of shelves and the billboard text.
    static var edge: CGFloat { Platform.isTV ? 80 : (isPad ? 36 : 20) }

    /// Wide enough for the billboard with the words on the left: an iPad, or an iPhone on its side.
    static func isWide(_ width: CGFloat) -> Bool { width >= 640 }
}

// MARK: - Shelf title

/// A shelf heading in bold, with a small chevron when tapping it opens the full list.
struct ShelfTitle: View {
    let title: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: Metrics.s(4)) {
            Text(title)
                .font(.casa(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.casa(13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Cards

/// A poster with nothing under it, rounded, with a hairline edge. With a rank it is a "Top 10" card:
/// a big number in the top left corner.
struct ApplePosterCard: View {
    let title: String
    let posterPath: String?
    var rank: Int? = nil
    var progress: Double? = nil
    var isWatched = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        Color.clear
            .frame(width: AppleMetrics.poster, height: AppleMetrics.poster * 1.5)
            .overlay { PosterImage(path: posterPath, title: title) }
            .overlay(alignment: .top) {
                if rank != nil {
                    LinearGradient(colors: [Color.black.opacity(0.6), Color.clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Metrics.s(64))
                }
            }
            .overlay(alignment: .topLeading) { rankNumber }
            .overlay(alignment: .topTrailing) {
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.casa(16))
                        .foregroundStyle(Theme.textPrimary, Color.black.opacity(0.55))
                        .padding(Metrics.s(6))
                }
            }
            .overlay(alignment: .bottom) {
                if let progress { ProgressBar(fraction: progress) }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rank.map { "Number \($0), \(title)" } ?? title)
    }

    @ViewBuilder private var rankNumber: some View {
        if let rank {
            Text("\(rank)")
                .font(.system(size: Platform.isTV ? 60 : AppleMetrics.poster * 0.29, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .padding(.leading, Metrics.s(9))
                .padding(.top, Metrics.s(2))
        }
    }
}

/// A wide card for something you are partway through: the picture, the title, and how much is left.
struct ContinueCard: View {
    let item: MediaItem

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        Color.clear
            .frame(width: AppleMetrics.wide, height: AppleMetrics.wide * AppleMetrics.wideHeightRatio)
            .overlay { BackdropImage(path: item.backdropPath ?? item.posterPath, hue: item.artHue) }
            .overlay(alignment: .bottom) { caption }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title), \(detailText)")
    }

    /// "S1, E4 · 56m left" for an episode on an iPad, like the Apple TV app. Everywhere else just the time left.
    private var detailText: String {
        let left = TimeFormat.timeLeft(item.remainingSeconds)
        #if os(tvOS)
        return left
        #else
        guard AppleMetrics.isPad, let season = item.seasonNumber, let episode = item.episodeNumber else { return left }
        return "S\(season), E\(episode) · \(left)"
        #endif
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: Metrics.s(5)) {
            Text(item.title)
                .font(.casa(15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: Metrics.s(8)) {
                Image(systemName: "play.fill")
                    .font(.casa(10))
                    .foregroundStyle(.white)
                ProgressBar(fraction: item.progressFraction)
                    .frame(width: Metrics.s(56))
                    .clipShape(Capsule())
                Text(detailText)
                    .font(.casa(12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.s(12))
        .padding(.bottom, Metrics.s(10))
        .padding(.top, Metrics.s(40))
        .background(
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
        )
    }
}

// MARK: - Small pieces

/// A round frosted button face, for the profile, back and share buttons.
struct GlassCircleLabel: View {
    let systemName: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// The dots under the billboard: the current page is a long pill.
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { position in
                Capsule()
                    .fill(Color.white.opacity(position == index ? 0.95 : 0.35))
                    .frame(width: position == index ? 26 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

/// A small outlined badge: PG-13, 4K, HDR, CC.
struct InfoBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            )
            .fixedSize()
    }
}

/// The synopsis: two lines, then MORE opens the rest.
struct SynopsisText: View {
    let text: String
    @State private var expanded = false

    private var isLong: Bool { text.count > 120 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(expanded ? nil : 2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isLong && !expanded {
                Text("MORE")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, 32)
                    .padding(.trailing, 2)
                    .background(
                        LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                                       startPoint: .leading, endPoint: UnitPoint(x: 0.4, y: 0.5))
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isLong { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } }
        }
        .accessibilityAddTraits(isLong ? .isButton : [])
    }
}

// MARK: - Billboard art

/// The big picture behind a billboard or a title page. On a phone it is the poster: its subject sits in the
/// middle, and it is lined up with the top so faces stay in view when the bottom fades out. Where the screen
/// is wide (iPad) it is the backdrop. With no poster it falls back to the backdrop.
struct HeroArt: View {
    let posterPath: String?
    let backdropPath: String?
    let hue: Double
    var preferPoster = true

    var body: some View {
        if preferPoster, let posterPath, let url = TMDBClient.posterURL(posterPath, width: 780) {
            GeometryReader { proxy in
                CachedAsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                            .clipped()
                    } else {
                        ArtView(hue: hue, cornerRadius: 0)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            BackdropImage(path: backdropPath ?? posterPath, hue: hue, fullSize: !preferPoster, alignment: .top)
        }
    }
}

// MARK: - Home billboard

/// One page of the billboard: something you are watching, or a trending title.
struct HeroSlide: Identifiable {
    enum Source {
        case library(MediaItem)
        case online(DiscoverTitle)
    }

    let source: Source

    var id: String {
        switch source {
        case .library(let item): return "lib-" + item.id.uuidString
        case .online(let title): return title.id
        }
    }
}

#if !os(tvOS)

/// The swipeable billboard at the top of Home. The picture runs edge to edge, behind the status bar.
/// On a phone it is tall, with the words in the middle. On an iPad it is a 16:9 picture with the words on the left.
struct HomeHero: View {
    @Environment(AppState.self) private var app
    let slides: [HeroSlide]
    let topInset: CGFloat
    /// The size of the screen area Home has, which sets how big the billboard is on an iPad.
    let containerSize: CGSize
    let openOnline: (DiscoverTitle) -> Void
    @State private var index = 0

    static let artHeight: CGFloat = 540

    private var wide: Bool { AppleMetrics.isWide(containerSize.width) }

    private var height: CGFloat {
        if wide {
            return min(containerSize.width * 9 / 16, containerSize.height * 0.64)
        }
        return Self.artHeight + topInset
    }

    private var currentIndex: Int { min(index, max(slides.count - 1, 0)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $index) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { position, slide in
                    HeroSlideView(slide: slide, wide: wide, openOnline: openOnline)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if slides.count > 1 {
                PageDots(count: slides.count, index: currentIndex)
                    .padding(.bottom, 12)
            }
        }
        .frame(height: height)
        .overlay(alignment: .top) {
            if !wide { HomeHeader(topInset: topInset) }
        }
    }
}

/// "Home" in big type on the left and the profile button on the right.
struct HomeHeader: View {
    @Environment(AppState.self) private var app
    let topInset: CGFloat
    /// On a wide screen the sidebar or tab bar already says where you are, so there is no title.
    var wide = false

    var body: some View {
        if wide {
            Color.clear.frame(height: topInset + 64)
        } else {
            header
        }
    }

    private var header: some View {
        HStack {
            Text("Home")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                app.selectedSection = .profile
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, topInset + 4)
    }

    private var avatar: some View {
        return ProfileAvatar(profile: app.activeProfile, size: 40)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
    }
}

private struct HeroSlideView: View {
    @Environment(AppState.self) private var app
    let slide: HeroSlide
    let wide: Bool
    let openOnline: (DiscoverTitle) -> Void

    var body: some View {
        if wide {
            wideBody
        } else {
            phoneBody
        }
    }

    /// iPad: the wide picture with the words on the left, like the Apple TV app. The picture ends in a clean
    /// edge, and the first shelf starts right under it.
    private var wideBody: some View {
        ZStack(alignment: .bottomLeading) {
            HeroArt(posterPath: posterPath, backdropPath: backdropPath, hue: hue, preferPoster: false)
            LinearGradient(colors: [Color.black.opacity(0.72), Color.black.opacity(0.35), Color.clear],
                           startPoint: .leading, endPoint: UnitPoint(x: 0.72, y: 0.5))
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.5)],
                           startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                Text(badge)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                TitleLogo(title: title, tmdbID: logoID, isShow: logoIsShow)

                HStack(spacing: 8) {
                    Text(wideMetaText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                    if let chip = ratingChip {
                        InfoBadge(text: chip)
                    }
                }

                if !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(3)
                        .frame(maxWidth: 540, alignment: .leading)
                }

                HStack(spacing: 12) {
                    primaryButton
                    addButton
                }
                .padding(.top, 6)

                if let timeLeft {
                    Text(timeLeft)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppleMetrics.edge)
            .padding(.bottom, 44)
        }
        .clipped()
    }

    /// iPhone: the poster, with the words in the middle.
    private var phoneBody: some View {
        ZStack(alignment: .bottom) {
            HeroArt(posterPath: posterPath, backdropPath: backdropPath, hue: hue, preferPoster: true)
            LinearGradient(colors: [Color.black.opacity(0.55), Color.clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3))
            LinearGradient(colors: [Color.clear, Theme.background.opacity(0.85), Theme.background],
                           startPoint: UnitPoint(x: 0.5, y: 0.42), endPoint: UnitPoint(x: 0.5, y: 0.9))

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 3)

                if !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    primaryButton
                    infoButton
                }
                .padding(.top, 4)

                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 38)
        }
        .clipped()
    }

    // MARK: What the page shows

    private var title: String {
        switch slide.source {
        case .library(let item): return item.title
        case .online(let title): return title.title
        }
    }

    private var overview: String {
        switch slide.source {
        case .library(let item): return item.overview
        case .online(let title): return title.overview
        }
    }

    private var posterPath: String? {
        switch slide.source {
        case .library(let item): return item.posterPath
        case .online(let title): return title.posterPath
        }
    }

    private var backdropPath: String? {
        switch slide.source {
        case .library(let item): return item.backdropPath
        case .online(let title): return title.backdropPath
        }
    }

    private var hue: Double {
        switch slide.source {
        case .library(let item): return item.artHue
        case .online: return 220
        }
    }

    private var footnote: String {
        switch slide.source {
        case .library(let item):
            return item.canResume
                ? "Continue watching · " + TimeFormat.timeLeft(item.remainingSeconds)
                : item.metaLine
        case .online(let title):
            return ["Trending", title.isShow ? "TV Series" : "Movie", title.year.map(String.init)]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    /// The small label over the title.
    private var badge: String {
        switch slide.source {
        case .library(let item): return item.canResume ? "Continue Watching" : "From Your Library"
        case .online(let title): return title.isShow ? "Trending TV Show" : "Trending Movie"
        }
    }

    /// "TV Show · 2025 · ★ 7.8"
    private var metaLine: String {
        switch slide.source {
        case .library(let item):
            return item.metaLine
        case .online(let title):
            var parts = [title.isShow ? "TV Show" : "Movie"]
            if let year = title.year { parts.append(String(year)) }
            if let rating = title.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
            return parts.joined(separator: " · ")
        }
    }

    /// The line under the title on an iPad: "2025 · 1h 52m", with the age rating drawn as a chip beside it.
    private var wideMetaText: String {
        guard case .library(let item) = slide.source, item.rating?.isEmpty == false else { return metaLine }
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        parts.append(TimeFormat.runtime(item.runtimeSeconds))
        return parts.joined(separator: " · ")
    }

    private var ratingChip: String? {
        if case .library(let item) = slide.source, let rating = item.rating, !rating.isEmpty { return rating }
        return nil
    }

    /// "2h 52m left", for something you are partway through.
    private var timeLeft: String? {
        if case .library(let item) = slide.source, item.canResume {
            return TimeFormat.timeLeft(item.remainingSeconds)
        }
        return nil
    }

    /// The TMDB ID the title logo is looked up by.
    private var logoID: Int? {
        switch slide.source {
        case .library(let item): return item.tmdbShowID ?? item.tmdbMovieID
        case .online(let title): return title.tmdbID
        }
    }

    private var logoIsShow: Bool {
        switch slide.source {
        case .library(let item): return item.tmdbShowID != nil
        case .online(let title): return title.isShow
        }
    }

    // MARK: Buttons

    @ViewBuilder private var primaryButton: some View {
        switch slide.source {
        case .library(let item):
            if item.streamURL == nil && item.sourceName.isEmpty {
                // An online title with no saved stream: its page is where a stream is picked.
                NavigationLink(value: item.id) {
                    Text(item.canResume ? "Resume" : "Watch").frame(minWidth: 130)
                }
                .buttonStyle(HeroButtonStyle(kind: .primary))
            } else {
                Button {
                    app.play(item)
                } label: {
                    Text(item.canResume ? "Resume" : "Play").frame(minWidth: 130)
                }
                .buttonStyle(HeroButtonStyle(kind: .primary))
            }
        case .online(let title):
            Button {
                openOnline(title)
            } label: {
                Text("Watch").frame(minWidth: 130)
            }
            .buttonStyle(HeroButtonStyle(kind: .primary))
        }
    }

    /// The round "+" button of the wide billboard. For something in your library it adds it to Favorites, or takes it
    /// out again. For an online title it opens the page, where it can be added.
    @ViewBuilder private var addButton: some View {
        switch slide.source {
        case .library(let item):
            Button {
                app.toggleFavorite(item.id)
            } label: {
                Image(systemName: item.isFavorite ? "checkmark" : "plus")
            }
            .buttonStyle(HeroButtonStyle(kind: .icon))
            .accessibilityLabel(item.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        case .online(let title):
            Button {
                openOnline(title)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(HeroButtonStyle(kind: .icon))
            .accessibilityLabel("Open")
        }
    }

    @ViewBuilder private var infoButton: some View {
        switch slide.source {
        case .library(let item):
            NavigationLink(value: item.id) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(HeroButtonStyle(kind: .icon))
            .accessibilityLabel("Details")
        case .online(let title):
            Button {
                openOnline(title)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(HeroButtonStyle(kind: .icon))
            .accessibilityLabel("Details")
        }
    }
}

#endif

// MARK: - Title logo

/// Logos already looked up, so a title is asked for only once.
@MainActor
enum TitleLogoCache {
    static var found: [String: String] = [:]
    static var missing: Set<String> = []
}

/// The title drawn as its logo, like the Apple TV app. Until TMDB answers, and when it has no logo, the name
/// is drawn in plain type.
struct TitleLogo: View {
    @Environment(AppState.self) private var app
    let title: String
    let tmdbID: Int?
    let isShow: Bool

    @State private var logoPath: String?
    @State private var resolved = false

    private var key: String { (isShow ? "tv-" : "movie-") + String(tmdbID ?? 0) }

    var body: some View {
        Group {
            if let logoPath, let url = TMDBClient.logoURL(logoPath) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        plainTitle
                    default:
                        Color.clear
                    }
                }
                .frame(maxWidth: 340, maxHeight: 92, alignment: .leading)
            } else if resolved {
                plainTitle
            } else {
                Color.clear.frame(height: 92)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: key) { await load() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    private var plainTitle: some View {
        Text(title)
            .font(.system(size: 58, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 3)
    }

    @MainActor
    private func load() async {
        logoPath = nil
        resolved = false
        guard let tmdbID else {
            resolved = true
            return
        }
        if let known = TitleLogoCache.found[key] {
            logoPath = known
            resolved = true
            return
        }
        if TitleLogoCache.missing.contains(key) {
            resolved = true
            return
        }
        guard let client = app.tmdbClient else {
            resolved = true
            return
        }

        let path: String?
        do {
            if isShow {
                path = try await client.titleLogoPath(showID: tmdbID)
            } else {
                path = try await client.titleLogoPath(movieID: tmdbID)
            }
        } catch {
            // Not saved as "missing", so the next visit tries again.
            resolved = true
            return
        }
        if let path {
            TitleLogoCache.found[key] = path
            logoPath = path
        } else {
            TitleLogoCache.missing.insert(key)
        }
        resolved = true
    }
}

// MARK: - Apple TV

extension View {
    /// Buttons around shelf cards: plain on iPhone and iPad. On Apple TV the card lifts a little when it has
    /// focus, and tells the card so it can show its caption.
    @ViewBuilder
    func appleTileStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(PremiumCardButtonStyle(focusScale: 1.07))
        #else
        self.buttonStyle(.plain)
        #endif
    }

    /// Apple TV: the sidebar of the Apple TV app, which folds into a small pill. Everything else is unchanged.
    @ViewBuilder
    func appleTVSidebar() -> some View {
        #if os(tvOS)
        if #available(tvOS 18.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
