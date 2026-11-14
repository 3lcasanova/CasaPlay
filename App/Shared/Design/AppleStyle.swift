// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The Apple TV app look: shelves with a chevron, ranked "Top 10" posters, wide Continue Watching
// cards, round glass buttons, the "MORE" synopsis, and on iPhone and iPad the swipeable billboard
// at the top of Home.

import SwiftUI
import CasaPlayKit

enum AppleMetrics {
    /// A poster in a shelf. Three and a bit fit across an iPhone.
    static var poster: CGFloat { Platform.isTV ? 250 : 112 }
    /// A wide Continue Watching card.
    static var wide: CGFloat { Platform.isTV ? 340 : 270 }
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
                .font(.system(size: Platform.isTV ? 60 : 32, weight: .heavy, design: .rounded))
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
            .frame(width: AppleMetrics.wide, height: AppleMetrics.wide * 9 / 16)
            .overlay { BackdropImage(path: item.backdropPath ?? item.posterPath, hue: item.artHue) }
            .overlay(alignment: .bottom) { caption }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title), \(TimeFormat.timeLeft(item.remainingSeconds))")
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
                Text(TimeFormat.timeLeft(item.remainingSeconds))
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
                AsyncImage(url: url) { phase in
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
            BackdropImage(path: backdropPath ?? posterPath, hue: hue)
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
struct HomeHero: View {
    @Environment(AppState.self) private var app
    let slides: [HeroSlide]
    let topInset: CGFloat
    let openOnline: (DiscoverTitle) -> Void
    @State private var index = 0

    static let artHeight: CGFloat = 540

    private var currentIndex: Int { min(index, max(slides.count - 1, 0)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $index) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { position, slide in
                    HeroSlideView(slide: slide, openOnline: openOnline)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if slides.count > 1 {
                PageDots(count: slides.count, index: currentIndex)
                    .padding(.bottom, 12)
            }
        }
        .frame(height: Self.artHeight + topInset)
        .overlay(alignment: .top) { HomeHeader(topInset: topInset) }
    }
}

/// "Home" in big type on the left and the profile button on the right.
struct HomeHeader: View {
    @Environment(AppState.self) private var app
    let topInset: CGFloat

    var body: some View {
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    let slide: HeroSlide
    let openOnline: (DiscoverTitle) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            HeroArt(posterPath: posterPath, backdropPath: backdropPath, hue: hue, preferPoster: sizeClass != .regular)
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
