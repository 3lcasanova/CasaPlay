// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

enum AppSection: String, CaseIterable, Identifiable {
    case home, movies, favorites, torrents, extensions, servers, sources, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .favorites: return "Favorites"
        case .torrents: return "Torrents"
        case .extensions: return "Extensions"
        case .servers: return "Servers"
        case .sources: return "Sources"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .movies: return "film"
        case .favorites: return "heart"
        case .torrents: return "arrow.down.circle"
        case .extensions: return "puzzlepiece.extension"
        case .servers: return "server.rack"
        case .sources: return "externaldrive"
        case .profile: return "person.crop.circle"
        }
    }
}

/// A subtitle track whose cues are in memory and can be drawn by the overlay.
struct LoadedSubtitle: Identifiable, Hashable {
    let track: SubtitleTrack
    let cues: [SubtitleCue]
    var id: String { track.id }
}

/// Keys for the online services, saved on this device.
enum ServiceKeys {
    static let omdb = "omdbAPIKey"
    static let openSubtitles = "openSubtitlesAPIKey"
    static let openSubtitlesToken = "openSubtitlesToken"
    static let openSubtitlesUser = "openSubtitlesUsername"

    /// The key entered in Online services, or else the one built in from Config/Secrets.xcconfig.
    static func value(_ key: String) -> String {
        let entered = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return entered.isEmpty ? builtIn(key) : entered
    }

    /// Keys copied into Info.plist at build time. Empty when Secrets.xcconfig is missing.
    static func builtIn(_ key: String) -> String {
        let plistKey: String
        switch key {
        case omdb: plistKey = "OMDbAPIKey"
        case openSubtitles: plistKey = "OpenSubtitlesAPIKey"
        default: return ""
        }
        let value = (Bundle.main.object(forInfoDictionaryKey: plistKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting can arrive as the literal "$(NAME)".
        return value.hasPrefix("$(") ? "" : value
    }
}

/// One shared, in-memory store for the whole app.
/// Phase 2 replaces `items` with a SwiftData library fed by real sources.
/// Watch progress is shared between profiles until Phase 5 splits it per profile.
@Observable
final class AppState {
    var items: [MediaItem] = SampleData.movies
    var profiles: [Profile] = SampleData.profiles
    var sources: [MediaSource] = SampleData.sources
    var activeProfileID: UUID = SampleData.profiles[0].id
    var subtitleStyle = SubtitleStyle.default
    var selectedSection: AppSection = .home
    var playing: MediaItem?
    var router = PlaybackRouter()
    /// Set when the user picks a torrent stream; clears after the sheet is dismissed.
    var pendingTorrentHash: InfoHash?

    /// Subtitle files loaded for each title (downloaded, or found next to the video).
    var subtitleLibrary: [MediaItem.ID: [LoadedSubtitle]] = [:]
    /// The viewer's choice per title: a track ID, or `Self.subtitlesOff`. No entry means automatic.
    var subtitleChoice: [MediaItem.ID: String] = [:]
    static let subtitlesOff = "off"

    var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    /// What the active profile is allowed to see. The Kids profile only shows G and PG.
    var library: [MediaItem] {
        guard activeProfile.isKids else { return items }
        return items.filter { ["G", "PG"].contains($0.rating ?? "") }
    }

    var continueWatching: [MediaItem] {
        library
            .filter { $0.canResume }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    var recentlyAdded: [MediaItem] {
        library.sorted { $0.addedAt > $1.addedAt }
    }

    var favorites: [MediaItem] {
        library.filter { $0.isFavorite }
    }

    var featured: MediaItem? {
        continueWatching.first ?? library.first
    }

    func item(id: MediaItem.ID) -> MediaItem? {
        items.first { $0.id == id }
    }

    func play(_ item: MediaItem) {
        playing = items.first { $0.id == item.id } ?? item
    }

    func startOver(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progressSeconds = 0
        items[index].isWatched = false
        playing = items[index]
    }

    func toggleFavorite(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
    }

    func toggleWatched(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isWatched.toggle()
        if items[index].isWatched {
            items[index].progressSeconds = 0
        }
    }

    func updateProgress(id: MediaItem.ID, seconds: TimeInterval) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progressSeconds = seconds
        items[index].lastPlayedAt = Date()
        if items[index].progressFraction >= 0.95 {
            items[index].isWatched = true
        }
    }

    // MARK: Subtitles

    func subtitleOptions(for id: MediaItem.ID) -> [LoadedSubtitle] {
        var options = subtitleLibrary[id] ?? []
        #if DEBUG
        // Lets the overlay be tried on the test stream before real sources exist.
        if options.isEmpty {
            let demo = SubtitleTrack(
                id: "demo-en",
                languageCode: "en",
                displayName: "English (demo)",
                origin: .sidecar,
                format: .srt
            )
            options.append(LoadedSubtitle(track: demo, cues: SRTParser.parse(SampleData.demoSubtitleSRT)))
        }
        #endif
        return options
    }

    /// The track to draw, following the viewer's choice or the profile's languages.
    func activeSubtitle(for id: MediaItem.ID) -> LoadedSubtitle? {
        let options = subtitleOptions(for: id)
        if let choice = subtitleChoice[id] {
            return options.first { $0.id == choice }
        }
        let automatic = SubtitleSelector.defaultTrack(
            from: options.map(\.track),
            preferredLanguages: activeProfile.preferredSubtitleLanguages,
            audioLanguage: nil
        )
        return options.first { $0.id == automatic?.id }
    }

    func selectSubtitle(_ trackID: String?, for id: MediaItem.ID) {
        subtitleChoice[id] = trackID ?? Self.subtitlesOff
    }

    func addSubtitle(_ subtitle: LoadedSubtitle, for id: MediaItem.ID) {
        var list = subtitleLibrary[id] ?? []
        list.removeAll { $0.id == subtitle.id }
        list.append(subtitle)
        subtitleLibrary[id] = list
        subtitleChoice[id] = subtitle.id
    }

    // MARK: Online services

    var openSubtitlesClient: OpenSubtitlesClient? {
        let key = ServiceKeys.value(ServiceKeys.openSubtitles)
        guard !key.isEmpty else { return nil }
        let token = ServiceKeys.value(ServiceKeys.openSubtitlesToken)
        return OpenSubtitlesClient(apiKey: key, token: token.isEmpty ? nil : token)
    }

    var omdbClient: OMDbClient? {
        let key = ServiceKeys.value(ServiceKeys.omdb)
        return key.isEmpty ? nil : OMDbClient(apiKey: key)
    }

    /// Fetches the current IMDb rating for a title that has an IMDb ID.
    /// Quietly does nothing without an OMDb key or an IMDb ID.
    @MainActor
    func refreshIMDb(for id: MediaItem.ID) async {
        guard let client = omdbClient,
              let imdbID = item(id: id)?.imdbID else { return }
        guard let result = try? await client.rating(imdbID: imdbID),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].imdbRating = result.rating ?? items[index].imdbRating
        items[index].imdbVotes = result.votes ?? items[index].imdbVotes
    }
}
