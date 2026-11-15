// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The Apple TV screen saver. After a few minutes without a press on the remote, a slideshow of the newest
// movies and series that are streaming fills the screen: big picture, the title's logo, a line about it.
// Any press brings the app back.

#if os(tvOS)
import SwiftUI
import UIKit
import ObjectiveC
import CasaPlayKit

// MARK: - Settings

/// How long the remote must be left alone before the screen saver starts. 0 turns it off.
enum ScreensaverSettings {
    static let key = "screensaverMinutes"
    static let defaultMinutes = 3
    /// The longest it runs. After that the Apple TV's own screen saver and sleep take over.
    static let longestRun: TimeInterval = 60 * 60
}

enum ScreensaverDelay: Int, CaseIterable, Hashable {
    case off = 0, one = 1, two = 2, three = 3, five = 5, ten = 10

    var label: String { self == .off ? "Off" : (self == .one ? "1 minute" : "\(rawValue) minutes") }
}

// MARK: - Remote activity

/// When the remote was last used. UIKit hands every press and touch from the Siri Remote to
/// `UIApplication.sendEvent`, so the time is noted there.
enum IdleActivity {
    static var lastActivity = Date()
    private static var installed = false

    static func touch() { lastActivity = Date() }

    /// Starts noting remote activity. Safe to call more than once.
    static func install() {
        guard !installed else { return }
        installed = true
        let original = #selector(UIApplication.sendEvent(_:))
        let replacement = #selector(UIApplication.casaNoteActivity(_:))
        guard let first = class_getInstanceMethod(UIApplication.self, original),
              let second = class_getInstanceMethod(UIApplication.self, replacement) else { return }
        method_exchangeImplementations(first, second)
    }
}

extension UIApplication {
    @objc fileprivate func casaNoteActivity(_ event: UIEvent) {
        IdleActivity.touch()
        // The two methods are swapped, so this calls UIKit's own sendEvent.
        casaNoteActivity(event)
    }
}

// MARK: - The titles

/// The newest films and shows that stream, newest first, a film and a show in turn.
@Observable
@MainActor
final class ScreensaverFeed {
    private(set) var titles: [DiscoverTitle] = []
    private var loadedAt = Date.distantPast
    private var isLoading = false

    func loadIfNeeded(_ client: TMDBClient?) async {
        guard let client, !isLoading else { return }
        // Fresh again every six hours.
        if !titles.isEmpty, Date().timeIntervalSince(loadedAt) < 6 * 3600 { return }
        isLoading = true
        defer { isLoading = false }

        var mixed: [DiscoverTitle] = []
        // The last six months; a whole year if that gives too few.
        for days in [180, 365] {
            mixed = await Self.fetch(client, days: days)
            if mixed.count >= 8 { break }
        }
        guard !mixed.isEmpty else { return }
        titles = mixed
        loadedAt = Date()

        // The first pictures are ready before the screen saver needs them.
        let first = mixed.prefix(3).compactMap { $0.backdropPath }.compactMap { TMDBClient.originalBackdropURL($0) }
        ImagePipeline.prefetch(first, maxPixel: 3200)
    }

    private static func fetch(_ client: TMDBClient, days: Int) async -> [DiscoverTitle] {
        let since = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        async let films1 = try? client.newestStreamingMovies(since: since)
        async let films2 = try? client.newestStreamingMovies(since: since, page: 2)
        async let shows1 = try? client.newestStreamingTV(since: since)
        async let shows2 = try? client.newestStreamingTV(since: since, page: 2)
        let movieList = (await films1 ?? []) + (await films2 ?? [])
        let showList = (await shows1 ?? []) + (await shows2 ?? [])
        let films = usable(movieList.map(DiscoverTitle.init))
        let shows = usable(showList.map(DiscoverTitle.init))
        return alternating(Array(films.prefix(14)), Array(shows.prefix(14)))
    }

    /// Only titles with a wide picture and a few words about them make a good slide.
    static func usable(_ titles: [DiscoverTitle]) -> [DiscoverTitle] {
        titles.filter { $0.backdropPath != nil && !$0.overview.isEmpty }
    }

    static func alternating(_ first: [DiscoverTitle], _ second: [DiscoverTitle]) -> [DiscoverTitle] {
        var out: [DiscoverTitle] = []
        for index in 0..<max(first.count, second.count) {
            if index < first.count { out.append(first[index]) }
            if index < second.count { out.append(second[index]) }
        }
        return out
    }
}

// MARK: - When to show it

@Observable
@MainActor
final class ScreensaverModel {
    var isShowing = false
    var startedAt = Date.distantPast
    /// Set when the longest run ended: from then on the Apple TV's own screen saver and sleep may start.
    var sleepAllowedSince: Date?

    func start() {
        startedAt = Date()
        sleepAllowedSince = nil
        isShowing = true
    }

    /// Someone pressed a button: back to the app, and the waiting starts over.
    func dismiss() {
        isShowing = false
        sleepAllowedSince = nil
        IdleActivity.touch()
    }

    /// The longest run ended with nobody there: let the Apple TV sleep as it normally would.
    func endRun() {
        isShowing = false
        sleepAllowedSince = Date()
    }
}

/// Sits over the whole app. Counts the quiet time, shows the screen saver, and takes it away on a press.
struct ScreensaverHost: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ScreensaverSettings.key) private var minutes = ScreensaverSettings.defaultMinutes
    @State private var model = ScreensaverModel()
    @State private var feed = ScreensaverFeed()

    var body: some View {
        ZStack {
            if model.isShowing {
                ScreensaverView(titles: feed.titles) { model.dismiss() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: model.isShowing)
        .task {
            IdleActivity.install()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                tick()
            }
        }
        .task(id: app.tmdbClient == nil) { await feed.loadIfNeeded(app.tmdbClient) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { IdleActivity.touch() }
        }
        // "Preview now" in Settings.
        .onChange(of: app.screensaverRequested) { _, wanted in
            guard wanted else { return }
            app.screensaverRequested = false
            if !feed.titles.isEmpty { model.start() }
        }
    }

    private func tick() {
        let now = Date()

        if model.isShowing {
            UIApplication.shared.isIdleTimerDisabled = true
            if IdleActivity.lastActivity > model.startedAt.addingTimeInterval(1) {
                // A press the screen saver itself didn't catch.
                model.dismiss()
            } else if now.timeIntervalSince(model.startedAt) > ScreensaverSettings.longestRun {
                model.endRun()
            }
            return
        }

        // A press after the longest run starts the whole cycle again.
        if let since = model.sleepAllowedSince, IdleActivity.lastActivity > since {
            model.sleepAllowedSince = nil
        }

        // While a film plays the player looks after the screen.
        guard app.playing == nil else { return }

        let enabled = minutes > 0 && !feed.titles.isEmpty
        // Keep the Apple TV from starting its own screen saver before this one has had its turn.
        UIApplication.shared.isIdleTimerDisabled = enabled && model.sleepAllowedSince == nil

        guard enabled, scenePhase == .active, model.sleepAllowedSince == nil, app.posterWallShown else { return }
        if now.timeIntervalSince(IdleActivity.lastActivity) >= Double(minutes) * 60 {
            model.start()
        }
    }
}

// MARK: - The slideshow

struct ScreensaverView: View {
    let titles: [DiscoverTitle]
    let onDismiss: () -> Void

    @State private var index = 0
    @State private var appearedAt = Date()
    @FocusState private var focused: Bool

    /// How long each title stays.
    private let seconds: Double = 10

    private var current: DiscoverTitle? {
        titles.isEmpty ? nil : titles[index % titles.count]
    }

    var body: some View {
        ZStack {
            Color.black
            if let title = current {
                ScreensaverSlide(title: title, seconds: seconds)
                    .id(title.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1.4), value: index)
        .ignoresSafeArea()
        .focusable()
        .focused($focused)
        .onAppear {
            appearedAt = Date()
            Task { focused = true }
        }
        .onTapGesture { dismiss() }
        .onMoveCommand { _ in dismiss() }
        .onExitCommand { dismiss() }
        .onPlayPauseCommand { dismiss() }
        .task { await advance() }
    }

    /// The press that started a preview must not end it at once.
    private func dismiss() {
        guard Date().timeIntervalSince(appearedAt) > 0.8 else { return }
        onDismiss()
    }

    private func advance() async {
        guard titles.count > 1 else { return }
        while !Task.isCancelled {
            prefetchNext()
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            index = (index + 1) % titles.count
        }
    }

    private func prefetchNext() {
        let upcoming = (1...2).compactMap { offset -> URL? in
            guard let path = titles[(index + offset) % titles.count].backdropPath else { return nil }
            return TMDBClient.originalBackdropURL(path)
        }
        ImagePipeline.prefetch(upcoming, maxPixel: 3200)
    }
}

/// One title: the picture drifting slowly closer, with the logo and a few words at the bottom left.
private struct ScreensaverSlide: View {
    let title: DiscoverTitle
    let seconds: Double
    @State private var zoomed = false

    private var meta: String {
        var parts: [String] = []
        if let year = title.year { parts.append(String(year)) }
        if let rating = title.rating, rating > 0 { parts.append("★ " + String(format: "%.1f", rating)) }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackdropImage(path: title.backdropPath ?? title.posterPath, hue: 215, fullSize: true, alignment: .top)
                .scaleEffect(zoomed ? 1.1 : 1)
                .animation(.linear(duration: seconds + 2), value: zoomed)

            LinearGradient(colors: [Color.black.opacity(0.72), Color.black.opacity(0.2), Color.clear],
                           startPoint: .leading, endPoint: UnitPoint(x: 0.75, y: 0.5))
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.75)],
                           startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: .bottom)

            details
        }
        .overlay(alignment: .topTrailing) {
            ScreensaverClock().padding(.top, 70).padding(.trailing, 100)
        }
        .ignoresSafeArea()
        .onAppear { zoomed = true }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(title.isShow ? "NEW SERIES" : "NEW MOVIE")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(3)
                Text("•")
                Text("STREAMING NOW")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(3)
            }
            .foregroundStyle(Color.white.opacity(0.85))

            TitleLogo(title: title.title, tmdbID: title.tmdbID, isShow: title.isShow,
                      logoWidth: 620, logoHeight: 210, alignment: .leading, plainSize: 88)

            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            Text(title.overview)
                .font(.system(size: 26))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(3)
                .frame(maxWidth: 900, alignment: .leading)
        }
        .padding(.leading, 100)
        .padding(.bottom, 110)
    }
}

/// The time, small, at the top right, like Apple's own screen saver.
private struct ScreensaverClock: View {
    var body: some View {
        Text(Date.now, style: .time)
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.85))
            .shadow(color: .black.opacity(0.5), radius: 8)
    }
}
#endif
