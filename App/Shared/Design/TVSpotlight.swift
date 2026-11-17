// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// CasaPlay 3i VERSION, Apple TV only. A shelf where the title that has focus opens out from a poster into a
// wide picture with its name on it, and its details (kind, year, rating and what it is about) show under
// the row. The other titles stay posters. Only the row you are on shows details, so the next row sits
// close below it.

#if os(tvOS)

import SwiftUI
import CasaPlayKit

enum SpotlightMetrics {
    /// A poster in the row.
    static let poster: CGFloat = 250
    static let height: CGFloat = 375
    /// The focused title: the same height, as wide as a 16:9 picture.
    static let wide: CGFloat = 667
    static let gap: CGFloat = 18
    /// Room under the row for the focused title's details.
    static let details: CGFloat = 175
}

extension DiscoverTitle {
    /// "Movie · 2025 · ★ 7.8"
    /// "Show  •  Horror  •  2022  •  TV-MA  •  ★ 7.8"
    func spotlightLine(ageRating: String?) -> String {
        var parts = [isShow ? "Show" : "Movie"]
        if let genre { parts.append(genre) }
        if let year { parts.append(String(year)) }
        if let ageRating, !ageRating.isEmpty { parts.append(ageRating) }
        if let rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        return parts.joined(separator: "  •  ")
    }
}

/// One shelf of online titles in the 3i look.
struct TVSpotlightShelf: View {
    let title: String
    let titles: [DiscoverTitle]
    let ranked: Bool
    let onSelect: (DiscoverTitle) -> Void

    /// The title in this row that has focus, or nil while focus is somewhere else.
    @State private var focusedID: String?
    /// Age ratings ("PG-13", "R", "TV-MA") already looked up, by title id.
    @State private var ratings: [String: String] = SpotlightRatings.known
    @Environment(AppState.self) private var app

    private var spotlight: DiscoverTitle? {
        guard let focusedID else { return nil }
        return titles.first { $0.id == focusedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.horizontal, TVMetrics.edge)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: SpotlightMetrics.gap) {
                    ForEach(Array(titles.enumerated()), id: \.element.id) { position, item in
                        Button {
                            onSelect(item)
                        } label: {
                            TVSpotlightTile(item: item, rank: ranked ? position + 1 : nil) { hasFocus in
                                focusChanged(item.id, hasFocus)
                            }
                        }
                        .buttonStyle(PremiumCardButtonStyle(focusScale: 1))
                    }
                }
                .padding(.horizontal, TVMetrics.edge)
                .padding(.vertical, 22)
            }
            .scrollClipDisabled()

            details
        }
        .environment(\.tvShelfID, title)
        .id(title)
    }

    /// Looks up the focused title's age rating once; shared by every row.
    private func loadAgeRating() async {
        guard let item = spotlight, ratings[item.id] == nil else { return }
        if let known = SpotlightRatings.known[item.id] { ratings[item.id] = known; return }
        guard let client = app.tmdbClient else { return }
        try? await Task.sleep(for: .milliseconds(250))   // skip titles the viewer only passes over
        guard !Task.isCancelled,
              let value = try? await client.ageRating(id: item.tmdbID, isShow: item.isShow) else { return }
        SpotlightRatings.known[item.id] = value
        ratings[item.id] = value
    }

    /// The focused title's line and summary. No height at all while the row doesn't have focus.
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item = spotlight {
                Text(item.spotlightLine(ageRating: ratings[item.id]))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.white)
                if !item.overview.isEmpty {
                    Text(item.overview)
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: 1050, alignment: .leading)
        .frame(height: spotlight == nil ? 0 : SpotlightMetrics.details, alignment: .top)
        .padding(.horizontal, TVMetrics.edge)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: focusedID)
        .task(id: focusedID) { await loadAgeRating() }
        .accessibilityHidden(true)
    }

    private func focusChanged(_ id: String, _ hasFocus: Bool) {
        if hasFocus {
            focusedID = id
        } else {
            // Moving along the row, the next title takes focus a moment later. Waiting for it keeps the
            // details from closing and opening again between two titles.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if focusedID == id { focusedID = nil }
            }
        }
    }
}

/// A title in a 3i shelf: a poster, or the wide picture with its name while it has focus.
struct TVSpotlightTile: View {
    let item: DiscoverTitle
    let rank: Int?
    let onFocusChange: (Bool) -> Void

    @Environment(\.cardFocused) private var focused

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(width: SpotlightMetrics.poster, height: SpotlightMetrics.height)
                .overlay { PosterImage(path: item.posterPath, title: item.title) }
                .clipped()
                .opacity(focused ? 0 : 1)

            if focused {
                BackdropImage(path: item.backdropPath ?? item.posterPath, hue: 220)
                    .transition(.opacity)
                LinearGradient(colors: [Color.clear, Color.black.opacity(0.82)],
                               startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                    .transition(.opacity)
                Text(item.title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 22)
                    .frame(maxWidth: SpotlightMetrics.wide * 0.8, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(width: focused ? SpotlightMetrics.wide : SpotlightMetrics.poster,
               height: SpotlightMetrics.height, alignment: .bottomLeading)
        .overlay(alignment: .topLeading) { rankNumber }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(focused ? Theme.accent : Color.white.opacity(0.12), lineWidth: focused ? 5 : 1)
        }
        .shadow(color: Theme.accent.opacity(focused ? 0.7 : 0), radius: focused ? 14 : 0)
        .animation(.easeInOut(duration: 0.28), value: focused)
        .onChange(of: focused) { _, now in onFocusChange(now) }
        .reportsRowFocus()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rank.map { "Number \($0), \(item.title)" } ?? item.title)
    }

    @ViewBuilder private var rankNumber: some View {
        if let rank {
            Text("\(rank)")
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .padding(.leading, 16)
                .padding(.top, 6)
        }
    }
}

#endif

/// Age ratings found so far, kept while the app runs so each title is looked up once.
@MainActor
enum SpotlightRatings {
    static var known: [String: String] = [:]
}
