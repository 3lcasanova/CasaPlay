// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The premium look shared by Movies, Series and IPTV: big colourful category tiles across the top,
// and poster cards with an episode badge, a corner ribbon, a rating strip and a focus glow.

import SwiftUI
import CasaPlayKit

// MARK: - Focus

private struct CardFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the button around this view has focus on Apple TV. Always false on iPhone and iPad.
    var cardFocused: Bool {
        get { self[CardFocusKey.self] }
        set { self[CardFocusKey.self] = newValue }
    }
}

/// Button style for tiles and poster cards. It draws no system platter: it lifts the card on focus
/// (Apple TV) or dips it when pressed (iPhone and iPad), and tells the card whether it has focus
/// so the card can draw its own white ring and show its title.
struct PremiumCardButtonStyle: ButtonStyle {
    var focusScale: CGFloat = 1.08

    func makeBody(configuration: Configuration) -> some View {
        FocusBody(configuration: configuration, focusScale: focusScale)
    }

    private struct FocusBody: View {
        let configuration: ButtonStyleConfiguration
        let focusScale: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .environment(\.cardFocused, isFocused)
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? focusScale : 1))
                .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 24, y: 14)
                .zIndex(isFocused ? 1 : 0)
                .animation(.easeOut(duration: 0.16), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

extension View {
    func premiumCardStyle(focusScale: CGFloat = 1.08) -> some View {
        buttonStyle(PremiumCardButtonStyle(focusScale: focusScale))
    }
}

// MARK: - Category tiles

/// The gradients behind the category tiles.
enum TilePalette: CaseIterable, Sendable {
    case ruby, amber, ocean, violet, emerald, rose, teal, indigo, sunset, graphite, lime, magenta, cyan, sky

    var colors: [Color] {
        switch self {
        case .ruby: return [Color(red: 0.96, green: 0.25, blue: 0.27), Color(red: 0.52, green: 0.04, blue: 0.17)]
        case .amber: return [Color(red: 0.99, green: 0.74, blue: 0.20), Color(red: 0.80, green: 0.36, blue: 0.05)]
        case .ocean: return [Color(red: 0.16, green: 0.62, blue: 0.98), Color(red: 0.05, green: 0.20, blue: 0.62)]
        case .violet: return [Color(red: 0.70, green: 0.36, blue: 0.98), Color(red: 0.27, green: 0.10, blue: 0.62)]
        case .emerald: return [Color(red: 0.20, green: 0.84, blue: 0.52), Color(red: 0.03, green: 0.38, blue: 0.30)]
        case .rose: return [Color(red: 1.00, green: 0.38, blue: 0.62), Color(red: 0.62, green: 0.07, blue: 0.36)]
        case .teal: return [Color(red: 0.14, green: 0.82, blue: 0.84), Color(red: 0.03, green: 0.34, blue: 0.48)]
        case .indigo: return [Color(red: 0.42, green: 0.45, blue: 0.99), Color(red: 0.12, green: 0.10, blue: 0.52)]
        case .sunset: return [Color(red: 1.00, green: 0.55, blue: 0.25), Color(red: 0.78, green: 0.12, blue: 0.40)]
        case .graphite: return [Color(red: 0.46, green: 0.49, blue: 0.56), Color(red: 0.12, green: 0.13, blue: 0.18)]
        case .lime: return [Color(red: 0.56, green: 0.88, blue: 0.20), Color(red: 0.16, green: 0.52, blue: 0.10)]
        case .magenta: return [Color(red: 0.92, green: 0.32, blue: 0.95), Color(red: 0.46, green: 0.08, blue: 0.62)]
        case .cyan: return [Color(red: 0.36, green: 0.90, blue: 0.96), Color(red: 0.08, green: 0.46, blue: 0.62)]
        case .sky: return [Color(red: 0.42, green: 0.78, blue: 1.00), Color(red: 0.10, green: 0.38, blue: 0.82)]
        }
    }
}

/// A big colourful tile that picks what the grid below shows.
struct CategoryTile: View {
    let title: String
    let symbol: String
    let palette: TilePalette
    let isSelected: Bool
    @Environment(\.cardFocused) private var focused

    init(title: String, symbol: String, palette: TilePalette, isSelected: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.palette = palette
        self.isSelected = isSelected
    }

    /// Six fit across an Apple TV screen with room to spare, so the last one is never cut off.
    static var size: CGSize {
        Platform.isTV ? CGSize(width: 276, height: 104) : CGSize(width: 158, height: 66)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Platform.isTV ? 24 : 15, style: .continuous)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: palette.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [Color.white.opacity(0.22), Color.clear], startPoint: .top, endPoint: .center)
            Color.black.opacity(isSelected || focused ? 0 : 0.2)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: symbol)
                .font(.system(size: Platform.isTV ? 26 : 15, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.top, Metrics.s(9))
                .padding(.trailing, Metrics.s(10))
        }
        .overlay(alignment: .leading) {
            Text(title)
                .font(.casa(17, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: Self.size.width * 0.82, alignment: .leading)
                .padding(.leading, Metrics.s(11))
                .padding(.top, Metrics.s(4))
        }
        .overlay(alignment: .bottomLeading) {
            if isSelected {
                Capsule()
                    .fill(Color.white)
                    .frame(width: Metrics.s(24), height: Metrics.s(4))
                    .padding(.leading, Metrics.s(11))
                    .padding(.bottom, Metrics.s(8))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(focused ? Color.white : Color.white.opacity(0.16),
                               lineWidth: focused ? 5 : (isSelected && !Platform.isTV ? 2.5 : 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A horizontally scrolling row of `CategoryTile`s.
struct CategoryRail<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Platform.isTV ? 20 : 10) {
                content()
            }
            .padding(.horizontal, PremiumGrid.edge)
            .padding(.vertical, Platform.isTV ? 26 : 4)
        }
    }
}

// MARK: - Poster card

/// Poster art from TMDB, or a quiet placeholder with the title while it loads or when there is none.
struct PosterImage: View {
    let path: String?
    let title: String

    var body: some View {
        if let path, let url = TMDBClient.posterURL(path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                           startPoint: .top, endPoint: .bottom)
            Text(title)
                .font(.casa(12, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(Metrics.s(8))
        }
    }
}

/// The red diagonal band across a poster's top right corner: TODAY, WEEKLY, IN 8 DAYS.
struct CornerRibbon: View {
    let text: String
    var tint = Color(red: 0.88, green: 0.11, blue: 0.16)

    private var side: CGFloat { Metrics.s(76) }

    var body: some View {
        ZStack {
            Text(text)
                .font(.casa(10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: side * 0.8)
                .padding(.vertical, Metrics.s(3))
                .frame(width: side * 1.5)
                .background(tint)
                .rotationEffect(.degrees(45))
                .position(x: side * 0.66, y: side * 0.34)
        }
        .frame(width: side, height: side)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// A poster with an optional episode badge (top left), release ribbon (top right) and a strip along
/// the bottom with the star rating on the left and the score as a percentage on the right.
/// On Apple TV the focused card gets a white ring and shows its title underneath.
struct PremiumPosterCard: View {
    let title: String
    let subtitle: String?
    let posterPath: String?
    let rating: Double?
    let badge: String?
    let ribbon: String?
    let progress: Double?
    let isWatched: Bool
    @Environment(\.cardFocused) private var focused

    init(title: String, subtitle: String? = nil, posterPath: String? = nil, rating: Double? = nil,
         badge: String? = nil, ribbon: String? = nil, progress: Double? = nil, isWatched: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.posterPath = posterPath
        self.rating = rating
        self.badge = badge
        self.ribbon = ribbon
        self.progress = progress
        self.isWatched = isWatched
    }

    /// A card for something in the user's own library.
    init(item: MediaItem) {
        self.init(title: item.title,
                  subtitle: item.yearText.isEmpty ? nil : item.yearText,
                  posterPath: item.posterPath,
                  rating: item.tmdbRating,
                  badge: item.file.is4K ? "4K" : nil,
                  progress: item.canResume ? item.progressFraction : nil,
                  isWatched: item.isWatched)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { PosterImage(path: posterPath, title: title) }
                .overlay(alignment: .bottom) { bottomStrip }
                .overlay(alignment: .topLeading) { badgePill }
                .overlay(alignment: .topTrailing) { topRight }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(Color.white, lineWidth: focused ? Metrics.s(2.6) : 0)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.casa(12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Apple TV shows the title only for the focused card, as in the reference; the space is kept.
            .opacity(Platform.isTV && !focused ? 0 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder private var badgePill: some View {
        if let badge {
            Text(badge)
                .font(.casa(12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, Metrics.s(8))
                .padding(.vertical, Metrics.s(3.5))
                .background(Color(red: 0.17, green: 0.42, blue: 0.98),
                            in: RoundedRectangle(cornerRadius: Metrics.s(8), style: .continuous))
                .padding(Metrics.s(7))
        }
    }

    @ViewBuilder private var topRight: some View {
        if let ribbon {
            CornerRibbon(text: ribbon)
        } else if isWatched {
            Image(systemName: "checkmark.circle.fill")
                .font(.casa(16))
                .foregroundStyle(Theme.textPrimary, Color.black.opacity(0.55))
                .padding(Metrics.s(6))
        }
    }

    private var percent: Int? { TMDBScore.percent(rating) }

    @ViewBuilder private var bottomStrip: some View {
        VStack(spacing: 0) {
            if let rating, rating > 0 {
                HStack(spacing: Metrics.s(4)) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.20))
                    Text(String(format: "%.1f", rating))
                    Spacer(minLength: 0)
                    if let percent {
                        Image(systemName: "hand.thumbsup.fill")
                            .foregroundStyle(Color(red: 0.36, green: 0.86, blue: 0.48))
                        Text("\(percent)%")
                    }
                }
                .font(.casa(13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Metrics.s(9))
                .padding(.bottom, Metrics.s(7))
                .padding(.top, Metrics.s(28))
                .background(
                    LinearGradient(colors: [Color.clear, Color.black.opacity(0.88)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            if let progress {
                ProgressBar(fraction: progress)
            }
        }
    }
}

// MARK: - Grid

enum PremiumGrid {
    /// Space at the left and right of rails and grids. Apple TV uses less, so the posters can be bigger.
    static var edge: CGFloat { Platform.isTV ? 56 : Metrics.screenPadding }

    /// Six across on Apple TV, filling the width; as many as fit on iPhone and iPad.
    static var columns: [GridItem] {
        if Platform.isTV {
            return Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: 6)
        }
        return [GridItem(.adaptive(minimum: 104, maximum: 200), spacing: 12, alignment: .top)]
    }

    static var rowSpacing: CGFloat { Platform.isTV ? 34 : 16 }

    /// How many cards from the end the next page starts loading.
    static var prefetch: Int { Platform.isTV ? 12 : 9 }
}

extension View {
    /// Apple TV: let the content run closer to the screen edges, so the posters have the room.
    @ViewBuilder
    func tvFullWidth() -> some View {
        #if os(tvOS)
        self.ignoresSafeArea(.container, edges: .horizontal)
        #else
        self
        #endif
    }
}

/// Heading above a grid.
struct PremiumSectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s(8)) {
            Text(title)
                .font(.casa(21, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if let detail {
                Text(detail)
                    .font(.casa(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, PremiumGrid.edge)
    }
}

// MARK: - Hero buttons and glass cards

/// Buttons over a title's hero image. On Apple TV a button is frosted glass until it has focus, then it
/// turns solid white and lifts, as in Apple's own apps. On iPhone and iPad the main button is solid white
/// and the others stay frosted.
struct HeroButtonStyle: ButtonStyle {
    enum Kind {
        /// The main action: Play, Resume, Episodes.
        case primary
        /// A text button next to it.
        case secondary
        /// A round icon button.
        case icon
    }

    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        HeroBody(configuration: configuration, kind: kind)
    }

    private struct HeroBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        private var solid: Bool { Platform.isTV ? isFocused : kind == .primary }

        var body: some View {
            configuration.label
                .font(.casa(15, weight: .semibold))
                .foregroundStyle(solid ? Theme.onLight : Color.white)
                .padding(.horizontal, kind == .icon ? Metrics.s(13) : Metrics.s(22))
                .padding(.vertical, Metrics.s(11))
                .frame(minWidth: kind == .icon ? Metrics.s(50) : nil, minHeight: Metrics.s(50))
                .background(Capsule().fill(solid ? Color.white : Color.white.opacity(0.2)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(solid ? 0 : 0.2), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1))
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 18, y: 10)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

extension View {
    /// A frosted panel: a faint light gradient with a hairline edge, on the dark background.
    func glassCard(cornerRadius: CGFloat = Platform.isTV ? 28 : 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
