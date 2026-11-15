// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The wall of posters the Apple TV app opens on, before it settles into the billboard. It plays once when
// CasaPlay opens, over everything, with the posters Home has loaded, then fades by itself. Select or a tap
// skips it. It is left out with Reduce Motion, without a TMDB key, or when the posters don't arrive in time.

import SwiftUI
import CasaPlayKit

struct WallPoster: Identifiable, Hashable {
    let id: String
    let path: String?
}

enum PosterWall {
    /// Fewer posters than this make a gappy wall, so it is skipped.
    static let minimum = 12
    /// How long to wait for the posters before giving up on the wall.
    static let patience: TimeInterval = 2.5
}

/// Sits over the whole app. Waits behind black for the posters, plays the wall, then goes away.
struct PosterWallHost: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wall: [WallPoster] = []

    private var available: [WallPoster] {
        let feed = app.discover
        let all = feed.trendingMovies + feed.trendingTV + feed.popularMovies + feed.popularTV + feed.topRated
        var seen = Set<String>()
        var result: [WallPoster] = []
        for title in all where title.posterPath != nil && seen.insert(title.id).inserted {
            result.append(WallPoster(id: title.id, path: title.posterPath))
        }
        return result
    }

    var body: some View {
        ZStack {
            if !app.posterWallShown {
                Color.black.ignoresSafeArea()
                if !wall.isEmpty {
                    PosterWallIntro(posters: wall) { finish() }
                        .transition(.opacity)
                }
            }
        }
        .task { await prepare() }
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.4)) { app.posterWallShown = true }
    }

    @MainActor
    private func prepare() async {
        guard !app.posterWallShown else { return }
        if reduceMotion || app.tmdbClient == nil {
            finish()
            return
        }
        let deadline = Date().addingTimeInterval(PosterWall.patience)
        while available.count < PosterWall.minimum, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !Task.isCancelled else { return }
        let posters = available
        guard posters.count >= PosterWall.minimum else {
            finish()
            return
        }
        // A short head start for the first pictures, so the wall doesn't open on empty tiles.
        let urls = posters.prefix(24).compactMap { $0.path.flatMap { TMDBClient.posterURL($0, width: 342) } }
        ImagePipeline.prefetch(urls, maxPixel: 520)
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        wall = Array(posters.prefix(70))
    }
}

/// The wall itself: posters fade in a few at a time and drift, the name comes up in the middle, and the
/// whole thing fades and grows away to show Home.
struct PosterWallIntro: View {
    let posters: [WallPoster]
    let onFinish: () -> Void

    @State private var appeared = false
    @State private var drifting = false
    @State private var showName = false
    @State private var leaving = false

    private var columns: Int { Platform.isTV ? 9 : (AppleMetrics.isPad ? 7 : 4) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let gap: CGFloat = Platform.isTV ? 18 : 8
            // A little wider than the screen, so the wall runs off both edges.
            let tileWidth = (size.width - gap * CGFloat(columns - 1)) / (CGFloat(columns) - 1.4)
            let tileHeight = tileWidth * 1.5
            let rows = Int(ceil(size.height / (tileHeight + gap))) + 2

            ZStack {
                Color.black

                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<columns, id: \.self) { column in
                        VStack(spacing: gap) {
                            ForEach(0..<rows, id: \.self) { row in
                                tile(column: column, row: row, rows: rows, width: tileWidth, height: tileHeight)
                            }
                        }
                        // Every other column sits lower, like the Apple TV wall.
                        .offset(y: column.isMultiple(of: 2) ? -tileHeight * 0.35 : tileHeight * 0.25)
                    }
                }
                .fixedSize()
                .frame(width: size.width, height: size.height, alignment: .top)
                .scaleEffect(drifting ? 1.1 : 1.0)
                .animation(.linear(duration: 3.4), value: drifting)

                shade(size)

                Text("CasaPlay")
                    .font(.system(size: Platform.isTV ? 120 : 46, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 18, y: 6)
                    .opacity(showName ? 1 : 0)
                    .scaleEffect(showName ? 1 : 0.94)
                    .animation(.easeOut(duration: 0.7), value: showName)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .opacity(leaving ? 0 : 1)
            .scaleEffect(leaving ? 1.12 : 1)
            .animation(.easeInOut(duration: 0.8), value: leaving)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        #if os(tvOS)
        .focusable()
        #endif
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func tile(column: Int, row: Int, rows: Int, width: CGFloat, height: CGFloat) -> some View {
        let poster = posters[(column * rows + row) % posters.count]
        let delay = Double((column * 5 + row * 3) % 11) * 0.06
        return PosterWallTile(poster: poster)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Platform.isTV ? 14 : 8, style: .continuous))
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.9)
            .animation(.easeOut(duration: 0.8).delay(delay), value: appeared)
    }

    /// Darker at the edges and behind the name, so the name reads and the wall feels deep.
    private func shade(_ size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.6), Color.clear, Color.black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.black.opacity(0.7), Color.clear],
                           center: .center, startRadius: 0, endRadius: min(size.width, size.height) * 0.7)
        }
        .allowsHitTesting(false)
    }

    private func play() async {
        appeared = true
        drifting = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        showName = true
        try? await Task.sleep(nanoseconds: 1_700_000_000)
        guard !Task.isCancelled else { return }
        leaving = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled else { return }
        onFinish()
    }
}

private struct PosterWallTile: View {
    let poster: WallPoster

    var body: some View {
        Color.white.opacity(0.07)
            .overlay {
                if let path = poster.path, let url = TMDBClient.posterURL(path, width: 342) {
                    CachedAsyncImage(url: url, maxPixel: 520) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.clear
                        }
                    }
                }
            }
    }
}
