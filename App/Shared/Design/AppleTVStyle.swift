// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Apple TV only. Home the way the Apple TV app draws it: a full-screen billboard that changes by itself,
// Continue Watching, "Top 10" shelves with big numbers, a caption under the poster that has focus, and a
// soft glow behind it all that takes its colour from the billboard.

#if os(tvOS)

import SwiftUI
import CasaPlayKit

enum TVMetrics {
    /// Left and right margin of the content.
    static let edge: CGFloat = 80
    static let spacing: CGFloat = 30
    /// The billboard fills the top of the screen. The first shelf shows under it.
    static let billboard: CGFloat = 800
}

// MARK: - Telling Home which shelf has focus

private struct TVShelfIDKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct TVShelfFocusKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
    /// The ID of the shelf this view is in.
    var tvShelfID: String {
        get { self[TVShelfIDKey.self] }
        set { self[TVShelfIDKey.self] = newValue }
    }

    /// Called with a shelf's ID when something in it gets focus. Home uses it to bring that shelf to the top.
    var tvShelfFocus: (String) -> Void {
        get { self[TVShelfFocusKey.self] }
        set { self[TVShelfFocusKey.self] = newValue }
    }
}

private struct RowFocusReporter: ViewModifier {
    @Environment(\.cardFocused) private var focused
    @Environment(\.tvShelfID) private var shelfID
    @Environment(\.tvShelfFocus) private var report

    func body(content: Content) -> some View {
        content.onChange(of: focused) { _, now in
            if now { report(shelfID) }
        }
    }
}

extension View {
    /// Put on the face of a tile in a button: tells Home when the tile gets focus.
    func reportsRowFocus() -> some View {
        modifier(RowFocusReporter())
    }
}

// MARK: - Shelf and tiles

/// A shelf: a small title, then a row that scrolls sideways. Six posters show and the seventh peeks in.
struct TVShelf<Content: View>: View {
    let rowID: String
    let title: String
    private let content: () -> Content

    init(id: String? = nil, title: String, @ViewBuilder content: @escaping () -> Content) {
        self.rowID = id ?? title
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.horizontal, TVMetrics.edge)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: TVMetrics.spacing) {
                    content()
                }
                .padding(.horizontal, TVMetrics.edge)
                .padding(.vertical, 32)
            }
            .scrollClipDisabled()
        }
        .environment(\.tvShelfID, rowID)
        .id(rowID)
    }
}

/// A poster with its caption under it. The caption shows while the poster has focus.
struct TVPosterTile: View {
    let title: String
    let posterPath: String?
    var rank: Int? = nil
    var caption: String
    var progress: Double? = nil
    var isWatched = false

    @Environment(\.cardFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ApplePosterCard(title: title, posterPath: posterPath, rank: rank, progress: progress, isWatched: isWatched)
            Text(caption)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
                .frame(width: AppleMetrics.poster, alignment: .leading)
                .opacity(focused ? 1 : 0)
        }
        .reportsRowFocus()
    }
}

/// A wide Continue Watching card.
struct TVContinueTile: View {
    let item: MediaItem

    var body: some View {
        ContinueCard(item: item)
            .reportsRowFocus()
    }
}

extension DiscoverTitle {
    /// "TV Show · 2025" or "Movie · 2025".
    var tvCaption: String {
        let kind = isShow ? "TV Show" : "Movie"
        guard let year else { return kind }
        return "\(kind) · \(year)"
    }
}

// MARK: - Billboard

extension HeroSlide {
    var tvTitle: String {
        switch source {
        case .library(let item): return item.title
        case .online(let title): return title.title
        }
    }

    var tvOverview: String {
        switch source {
        case .library(let item): return item.overview
        case .online(let title): return title.overview
        }
    }

    var tvBackdrop: String? {
        switch source {
        case .library(let item): return item.backdropPath ?? item.posterPath
        case .online(let title): return title.backdropPath ?? title.posterPath
        }
    }

    var tvHue: Double {
        switch source {
        case .library(let item): return item.artHue
        case .online: return 220
        }
    }

    /// The small label over the title.
    var tvLabel: String {
        switch source {
        case .library(let item): return item.canResume ? "Continue Watching" : "From Your Library"
        case .online(let title): return title.isShow ? "Trending TV Show" : "Trending Movie"
        }
    }

    /// The small line under the buttons.
    var tvCaption: String {
        switch source {
        case .library(let item): return item.metaLine
        case .online(let title): return title.tvCaption
        }
    }

    var tvActionTitle: String {
        switch source {
        case .library(let item): return item.canResume ? "Resume" : "Play"
        case .online: return "Watch Now"
        }
    }
}

/// The big picture at the top of Home. It fills the screen, changes by itself, and has a button for the
/// title, one for its page, and one for the next title.
struct TVBillboard: View {
    let slides: [HeroSlide]
    @Binding var index: Int
    let primary: (HeroSlide) -> Void
    let info: (HeroSlide) -> Void

    @Environment(\.tvShelfFocus) private var rowFocus
    @FocusState private var field: Field?
    @State private var lastTouch = Date.distantPast

    private enum Field: Hashable {
        case primary, info, next
    }

    private var safeIndex: Int { min(index, max(slides.count - 1, 0)) }
    private var slide: HeroSlide { slides[safeIndex] }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                BackdropImage(path: slide.tvBackdrop, hue: slide.tvHue, fullSize: true)
                    .id(slide.id)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.8), value: slide.id)

            shading
            details
        }
        .frame(maxWidth: .infinity)
        .frame(height: TVMetrics.billboard)
        .overlay(alignment: .bottom) { dots.padding(.bottom, 20) }
        .clipped()
        .task(id: slides.count) { await rotate() }
        .onChange(of: field) { _, now in
            if now != nil { rowFocus("billboard") }
        }
    }

    // MARK: Look

    private var shading: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.65), Color.clear],
                           startPoint: .leading, endPoint: UnitPoint(x: 0.62, y: 0.5))
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.55), Color.black],
                           startPoint: UnitPoint(x: 0.5, y: 0.42), endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            // A ZStack, so the old words fade out on top of the new ones instead of stacking above them.
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(slide.tvLabel.uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(Color.white.opacity(0.7))

                    Text(slide.tvTitle)
                        .font(.system(size: 76, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

                    if !slide.tvOverview.isEmpty {
                        Text(slide.tvOverview)
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .lineLimit(2)
                            .frame(maxWidth: 780, alignment: .leading)
                    }
                }
                .id(slide.id)
                .transition(.opacity)
            }

            HStack(spacing: 22) {
                Button {
                    lastTouch = Date()
                    primary(slide)
                } label: {
                    Label(slide.tvActionTitle, systemImage: "play.fill")
                }
                .buttonStyle(HeroButtonStyle(kind: .primary))
                .focused($field, equals: .primary)

                Button {
                    lastTouch = Date()
                    info(slide)
                } label: {
                    Image(systemName: "info")
                }
                .buttonStyle(HeroButtonStyle(kind: .icon))
                .focused($field, equals: .info)
                .accessibilityLabel("Details")

                if slides.count > 1 {
                    Button {
                        lastTouch = Date()
                        advance()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(HeroButtonStyle(kind: .icon))
                    .focused($field, equals: .next)
                    .accessibilityLabel("Next title")
                }
            }

            ZStack(alignment: .leading) {
                Text(slide.tvCaption)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .id("caption-" + slide.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: slide.id)
        .padding(.leading, TVMetrics.edge)
        .padding(.bottom, 84)
    }

    private var dots: some View {
        HStack(spacing: 12) {
            ForEach(0..<slides.count, id: \.self) { position in
                Capsule()
                    .fill(Color.white.opacity(position == safeIndex ? 0.95 : 0.35))
                    .frame(width: position == safeIndex ? 36 : 10, height: 10)
            }
        }
        .animation(.easeOut(duration: 0.25), value: safeIndex)
        .accessibilityHidden(true)
    }

    // MARK: Changing titles

    private func advance() {
        guard slides.count > 1 else { return }
        index = (safeIndex + 1) % slides.count
    }

    /// Moves on every few seconds, unless a button was just pressed.
    private func rotate() async {
        guard slides.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            if Task.isCancelled { break }
            if Date().timeIntervalSince(lastTouch) > 12 { advance() }
        }
    }
}

// MARK: - Home

/// Home on Apple TV.
struct TVHome: View {
    @Environment(AppState.self) private var app
    @Binding var path: [UUID]
    let opener: DiscoverOpener
    let isOpening: Bool
    let message: String?

    @State private var slideIndex = 0
    @State private var scrolledRow = "billboard"

    /// Up to two titles you are watching, then trending films and shows, alternating.
    private var billboardSlides: [HeroSlide] {
        let feed = app.discover
        var result = app.continueWatching.prefix(2).map { HeroSlide(source: .library($0)) }

        var online: [DiscoverTitle] = []
        let films = feed.trendingMovies.filter { $0.backdropPath != nil }
        let shows = feed.trendingTV.filter { $0.backdropPath != nil }
        for position in 0..<max(films.count, shows.count) {
            if position < films.count { online.append(films[position]) }
            if position < shows.count { online.append(shows[position]) }
        }
        result += online.prefix(max(7 - result.count, 0)).map { HeroSlide(source: .online($0)) }
        return result
    }

    var body: some View {
        let slides = billboardSlides

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if slides.isEmpty {
                        Text("Home")
                            .font(.system(size: 64, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, TVMetrics.edge)
                            .padding(.top, 120)
                            .padding(.bottom, 30)
                            .id("billboard")
                    } else {
                        TVBillboard(slides: slides, index: $slideIndex,
                                    primary: { play($0) }, info: { open($0) })
                            .id("billboard")
                    }

                    if app.tmdbClient == nil {
                        TMDBKeyNotice()
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                            .padding(.horizontal, TVMetrics.edge)
                    }

                    shelves
                }
                .padding(.bottom, 200)
            }
            .environment(\.tvShelfFocus, { id in bringToTop(id, proxy) })
        }
        .ignoresSafeArea()
        .background { glow(slides) }
        .overlay {
            if isOpening {
                ProgressView().tint(.white)
            }
        }
    }

    // MARK: Shelves

    @ViewBuilder
    private var shelves: some View {
        let feed = app.discover

        if !app.continueWatching.isEmpty {
            TVShelf(title: "Continue Watching") {
                ForEach(app.continueWatching) { item in
                    NavigationLink(value: item.id) {
                        TVContinueTile(item: item)
                    }
                    .appleTileStyle()
                }
            }
        }

        DiscoverShelf(title: "Top 10 Movies This Week", titles: Array(feed.trendingMovies.prefix(10)), ranked: true) { opener.open($0) }
        DiscoverShelf(title: "Top 10 TV Shows This Week", titles: Array(feed.trendingTV.prefix(10)), ranked: true) { opener.open($0) }

        if !app.favorites.isEmpty {
            TVShelf(title: "Favorites") {
                ForEach(app.favorites) { item in
                    libraryTile(item)
                }
            }
        }

        DiscoverShelf(title: "Popular Movies", titles: feed.popularMovies) { opener.open($0) }
        DiscoverShelf(title: "Now Playing", titles: feed.titles("m-nowPlaying")) { opener.open($0) }
        DiscoverShelf(title: "Popular Shows", titles: feed.popularTV) { opener.open($0) }
        DiscoverShelf(title: "Top Rated", titles: feed.topRated) { opener.open($0) }
        DiscoverShelf(title: "Top Rated Shows", titles: feed.topRatedTV) { opener.open($0) }
        DiscoverShelf(title: "Anime Series", titles: feed.titles("tv-anime")) { opener.open($0) }
        DiscoverShelf(title: "Anime Movies", titles: feed.titles("m-anime")) { opener.open($0) }
        DiscoverShelf(title: "Coming Soon", titles: feed.titles("m-upcoming")) { opener.open($0) }

        if !app.recentlyAdded.isEmpty {
            TVShelf(title: "Your Library") {
                ForEach(app.recentlyAdded) { item in
                    libraryTile(item)
                }
            }
        }
    }

    private func libraryTile(_ item: MediaItem) -> some View {
        NavigationLink(value: item.id) {
            TVPosterTile(title: item.title,
                         posterPath: item.posterPath,
                         caption: item.title,
                         progress: item.canResume ? item.progressFraction : nil,
                         isWatched: item.isWatched)
        }
        .appleTileStyle()
    }

    // MARK: Actions

    /// The main button: play what you are watching, or open the page of a title that needs a stream picked.
    private func play(_ slide: HeroSlide) {
        switch slide.source {
        case .library(let item):
            if item.streamURL == nil && item.sourceName.isEmpty {
                path.append(item.id)
            } else {
                app.play(item)
            }
        case .online(let title):
            opener.open(title)
        }
    }

    private func open(_ slide: HeroSlide) {
        switch slide.source {
        case .library(let item): path.append(item.id)
        case .online(let title): opener.open(title)
        }
    }

    /// Like the Apple TV app, the shelf you are on moves up to the top of the screen.
    private func bringToTop(_ id: String, _ proxy: ScrollViewProxy) {
        guard id != scrolledRow else { return }
        scrolledRow = id
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    // MARK: Glow

    /// Black, with the billboard picture blurred far out so its colours glow behind the shelves.
    @ViewBuilder
    private func glow(_ slides: [HeroSlide]) -> some View {
        ZStack {
            Color.black
            if slides.isEmpty {
                RadialGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.5).opacity(0.5), Color.clear],
                               center: .topLeading, startRadius: 40, endRadius: 1100)
            } else {
                let current = slides[min(slideIndex, slides.count - 1)]
                BackdropImage(path: current.tvBackdrop, hue: current.tvHue)
                    .blur(radius: 90)
                    .opacity(0.42)
                    .id(current.id)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 1.0), value: current.id)
                Color.black.opacity(0.3)
            }
        }
        .ignoresSafeArea()
    }
}

#endif
