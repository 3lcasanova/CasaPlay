// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

/// Placeholder artwork: a gradient tinted by the item's hue.
/// Swap for real posters (TMDB) in Phase 2.
struct ArtView: View {
    let hue: Double
    var title: String? = nil
    var cornerRadius: CGFloat = Metrics.cornerRadius

    private var base: Double { hue / 360 }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(hue: base, saturation: 0.55, brightness: 0.34),
                    Color(hue: base, saturation: 0.45, brightness: 0.08)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RadialGradient(
                colors: [
                    Color(hue: base, saturation: 0.5, brightness: 0.95).opacity(0.5),
                    Color.clear
                ],
                center: UnitPoint(x: 0.72, y: 0.2),
                startRadius: 0,
                endRadius: 320
            )
            if let title {
                Text(title.uppercased())
                    .font(.casa(11, weight: .bold))
                    .tracking(Platform.isTV ? 3 : 1.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.6), radius: 4)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.28))
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: Platform.isTV ? 8 : 4)
    }
}

struct Pill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.casa(11, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Metrics.s(7))
            .padding(.vertical, Metrics.s(2))
            .background(Theme.surfaceStrong, in: Capsule())
    }
}

struct AvatarView: View {
    let text: String
    let hue: Double
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [
                        Color(hue: hue / 360, saturation: 0.55, brightness: 0.78),
                        Color(hue: hue / 360, saturation: 0.6, brightness: 0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(text)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Theme.onLight)
        }
        .frame(width: size, height: size)
    }
}

/// A selectable pill used for filters and settings.
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.casa(13, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
                .padding(.horizontal, Metrics.s(12))
                .padding(.vertical, Metrics.s(6))
                .background(isSelected ? Theme.accent : Theme.surfaceStrong, in: Capsule())
        }
        .posterButtonStyle()
    }
}

/// A titled row of chips that edits one value.
struct OptionRow<Value: Hashable>: View {
    let title: String
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            Text(title)
                .font(.casa(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.s(8)) {
                    ForEach(options, id: \.self) { option in
                        ChipButton(title: label(option), isSelected: option == selection) {
                            selection = option
                        }
                    }
                }
                .padding(.vertical, Platform.isTV ? 14 : 0)
            }
        }
    }
}

struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            posterArt
                .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * 1.5)
                .overlay(alignment: .topTrailing) {
                    if item.isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.casa(16))
                            .foregroundStyle(Theme.textPrimary, Color.black.opacity(0.55))
                            .padding(Metrics.s(6))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if item.file.is4K {
                        Pill(text: "4K").padding(Metrics.s(6))
                    }
                }
                .overlay(alignment: .bottom) {
                    if item.canResume {
                        ProgressBar(fraction: item.progressFraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text([item.yearText, item.rating ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: Metrics.posterWidth, alignment: .leading)
        }
    }

    @ViewBuilder private var posterArt: some View {
        if let path = item.posterPath, let url = TMDBClient.posterURL(path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: ArtView(hue: item.artHue, title: item.title)
                }
            }
        } else {
            ArtView(hue: item.artHue, title: item.title)
        }
    }
}

struct LandscapeCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            landscapeArt
                .frame(width: Metrics.landscapeWidth, height: Metrics.landscapeWidth * 9 / 16)
                .overlay(alignment: .bottom) {
                    if item.canResume {
                        ProgressBar(fraction: item.progressFraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(item.canResume ? TimeFormat.timeLeft(item.remainingSeconds) : item.metaLine)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: Metrics.landscapeWidth, alignment: .leading)
        }
    }

    @ViewBuilder private var landscapeArt: some View {
        if let path = item.backdropPath ?? item.posterPath, let url = TMDBClient.backdropURL(path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: ArtView(hue: item.artHue, title: item.title)
                }
            }
        } else {
            ArtView(hue: item.artHue, title: item.title)
        }
    }
}

/// A titled, horizontally scrolling row.
struct Shelf<Content: View>: View {
    let title: String
    private let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            Text(title)
                .font(.casa(19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Metrics.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Metrics.shelfSpacing) {
                    content()
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, Platform.isTV ? 28 : 0)
            }
        }
    }
}

/// IMDb's yellow mark with the rating, e.g. [IMDb] 7.6 · 128K.
struct IMDbBadge: View {
    let rating: Double
    var votes: Int? = nil

    var body: some View {
        HStack(spacing: Metrics.s(6)) {
            Text("IMDb")
                .font(.casa(11, weight: .heavy))
                .foregroundStyle(Color.black)
                .padding(.horizontal, Metrics.s(5))
                .padding(.vertical, Metrics.s(1.5))
                .background(Color(red: 0.961, green: 0.773, blue: 0.094), in: RoundedRectangle(cornerRadius: Metrics.s(3)))
            Text(IMDb.ratingText(rating))
                .font(.casa(13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if let votes {
                Text(IMDb.votesText(votes))
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("IMDb rating \(IMDb.ratingText(rating)) out of 10")
    }
}
