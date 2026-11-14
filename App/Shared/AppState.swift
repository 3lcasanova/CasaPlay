// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

enum AppSection: String, CaseIterable, Identifiable {
    case home, movies, series, iptv, extensions, servers, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .series: return "Series"
        case .iptv: return "IPTV"
        case .extensions: return "Extensions"
        case .servers: return "Servers"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .movies: return "film"
        case .series: return "tv"
        case .iptv: return "antenna.radiowaves.left.and.right"
        case .extensions: return "puzzlepiece.extension"
        case .servers: return "server.rack"
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
    static let tmdb = "tmdbAPIKey"
    static let tvdb = "tvdbAPIKey"
    /// NihonSub bridge on your Mac. Entered by hand, never built in.
    static let nihonSubAddress = "nihonSubAddress"
    static let nihonSubToken = "nihonSubToken"

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
        case tmdb: plistKey = "TMDBAPIKey"
        case tvdb: plistKey = "TVDBAPIKey"
        default: return ""
        }
        let value = (Bundle.main.object(forInfoDictionaryKey: plistKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting can arrive as the literal "$(NAME)".
        return value.hasPrefix("$(") ? "" : value
    }
}

/// The link of a stream that was started, kept in memory so your Mac can fetch its audio for NihonSub.
/// It is never saved to disk, so it is gone when the app quits.
struct StreamLink: Identifiable {
    let itemID: MediaItem.ID
    let url: URL
    let headers: [String: String]?
    let playedAt: Date

    var id: MediaItem.ID { itemID }

    /// The Mac can only fetch normal web links. The on-device server that plays torrents
    /// (localhost) is only visible to the Apple TV or iPhone itself.
    var canSendToMac: Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let loopback = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
        return !loopback.contains(host) && !host.hasPrefix("127.")
    }
}

/// Where a NihonSub job stands for one title.
struct NihonSubStatus: Equatable {
    var language: NihonSubClient.Language
    var progress: String
    var failure: String?
    var isRunning: Bool
}

extension NihonSubClient.Status {
    /// "Listening · 40%" for the progress line.
    var progressText: String {
        let step: String
        switch state {
        case "queued": step = "Waiting"
        case "extracting": step = "Reading the audio"
        case "transcribing": step = "Listening"
        case "translating": step = "Translating"
        case "done": step = "Done"
        default: step = message.isEmpty ? "Working" : message
        }
        return percent > 0 ? "\(step) · \(percent)%" : step
    }
}

/// One shared, in-memory store for the whole app.
@Observable
final class AppState {
    var items: [MediaItem]
    private var watchMap: [String: WatchRecord]

    var profiles: [Profile]
    var discover = DiscoverFeed()
    var activeProfileID: UUID {
        didSet { ProfileStore.saveActiveID(activeProfileID) }
    }
    var subtitleStyle = SubtitleStyle.default
    /// Goes up when a profile photo is added, changed or removed, so every avatar redraws.
    var photoRevision = 0
    var selectedSection: AppSection = .home
    var playing: MediaItem?
    /// The compatibility engine (VLC) is on, so MKV and other files Apple's player can't open still play.
    var router = PlaybackRouter(compatibilityEngineEnabled: true)
    /// Set when the user picks a torrent stream; clears after the sheet is dismissed.
    var pendingTorrentHash: InfoHash?

    /// Subtitle files loaded for each title (downloaded, or found next to the video).
    var subtitleLibrary: [MediaItem.ID: [LoadedSubtitle]] = [:]
    /// The viewer's choice per title: a track ID, or `Self.subtitlesOff`. No entry means automatic.
    var subtitleChoice: [MediaItem.ID: String] = [:]
    static let subtitlesOff = "off"
    /// What the automatic English subtitle lookup is doing for a title, or why it found nothing.
    var autoSubtitleNote: [MediaItem.ID: String] = [:]
    @ObservationIgnored private var autoSubtitleTried: Set<MediaItem.ID> = []
    /// Streams started this session, by title. Used to hand a link to the NihonSub bridge. Never saved.
    var streamLinks: [MediaItem.ID: StreamLink] = [:]
    /// What each NihonSub job is doing. Kept here so a job goes on after the subtitle screen is closed.
    var nihonSubStatus: [MediaItem.ID: NihonSubStatus] = [:]
    @ObservationIgnored private var nihonSubTasks: [MediaItem.ID: Task<Void, Never>] = [:]

    init() {
        let history = WatchHistory.load()
        var library = LibraryStore.load()
        WatchHistory.apply(history, to: &library)
        items = library
        watchMap = history

        let saved = ProfileStore.load()
        profiles = saved
        activeProfileID = ProfileStore.loadActiveID(in: saved)
    }

    /// Adds a title found online and remembers it across launches.
    func addToLibrary(_ item: MediaItem) {
        items.append(item)
        LibraryStore.save(items)
    }

    /// Fetches a TMDB film, adds it to the library (once), and returns its library ID.
    @MainActor
    func openMovie(tmdbID: Int) async throws -> MediaItem.ID? {
        guard let client = tmdbClient else { return nil }
        return adopt(client.toMediaItem(try await client.movieDetail(id: tmdbID)))
    }

    @MainActor
    func openShow(tmdbID: Int) async throws -> MediaItem.ID? {
        guard let client = tmdbClient else { return nil }
        return adopt(client.toMediaItem(try await client.showDetail(id: tmdbID)))
    }

    private func adopt(_ item: MediaItem) -> MediaItem.ID {
        if let index = items.firstIndex(where: { $0.historyKey == item.historyKey }) {
            var changed = false
            if !item.cast.isEmpty, items[index].cast != item.cast {
                items[index].cast = item.cast
                changed = true
            }
            if items[index].tmdbMovieID == nil, let movieID = item.tmdbMovieID {
                items[index].tmdbMovieID = movieID
                changed = true
            }
            if changed { LibraryStore.save(items) }
            return items[index].id
        }
        var fresh = [item]
        WatchHistory.apply(watchMap, to: &fresh)
        addToLibrary(fresh[0])
        return item.id
    }

    /// Titles viewers of this one also watch, from TMDB. Empty when there is no key or no match.
    func relatedTitles(for item: MediaItem) async -> [DiscoverTitle] {
        guard let client = tmdbClient else { return [] }
        do {
            if let showID = item.tmdbShowID {
                return try await client.recommendedTV(id: showID).prefix(12).map(DiscoverTitle.init)
            }
            if let movieID = item.tmdbMovieID {
                return try await client.recommendedMovies(id: movieID).prefix(12).map(DiscoverTitle.init)
            }
        } catch {
            return []
        }
        return []
    }

    var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    func addProfile(name: String, hue: Double, isKids: Bool) {
        let p = Profile(name: name, hue: hue, isKids: isKids)
        profiles.append(p)
        ProfileStore.save(profiles)
    }

    /// Saves a picture as the photo of a profile. False when the data is not a picture.
    @discardableResult
    func setProfilePhoto(_ data: Data, for id: UUID) -> Bool {
        guard ProfilePhotoStore.save(data, for: id) else { return false }
        photoRevision += 1
        return true
    }

    func removeProfilePhoto(for id: UUID) {
        ProfilePhotoStore.remove(for: id)
        photoRevision += 1
    }

    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        ProfilePhotoStore.remove(for: id)
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = profiles[0].id }
        ProfileStore.save(profiles)
    }

    /// Removes every profile except the one in use, and their photos.
    func keepOnlyActiveProfile() {
        let keep = activeProfile
        for profile in profiles where profile.id != keep.id {
            ProfilePhotoStore.remove(for: profile.id)
        }
        profiles = [keep]
        activeProfileID = keep.id
        ProfileStore.save(profiles)
        photoRevision += 1
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
        items.first { $0.id == id } ?? episodes.first { $0.id == id }
    }

    // MARK: Episodes

    /// Episodes being watched. Kept out of the library; their progress is saved like any title.
    private(set) var episodes: [MediaItem] = []

    static func episodeItem(show: MediaItem, season: Int, episode: Int, runtimeMinutes: Int?) -> MediaItem {
        var item = MediaItem(
            title: "\(show.title) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))",
            year: show.year,
            kind: .episode,
            runtimeSeconds: TimeInterval((runtimeMinutes ?? 0) * 60),
            file: MediaFileInfo(container: .mp4, videoCodec: .h264),
            artHue: show.artHue
        )
        item.posterPath = show.posterPath
        item.backdropPath = show.backdropPath
        item.parentIMDbID = show.imdbID
        item.seasonNumber = season
        item.episodeNumber = episode
        return item
    }

    /// Returns the ID to play an episode under, creating it with any saved progress.
    func registerEpisode(show: MediaItem, season: Int, episode: Int, runtimeMinutes: Int?) -> MediaItem.ID {
        let fresh = Self.episodeItem(show: show, season: season, episode: episode, runtimeMinutes: runtimeMinutes)
        if let existing = episodes.first(where: { $0.historyKey == fresh.historyKey }) {
            return existing.id
        }
        var list = [fresh]
        WatchHistory.apply(watchMap, to: &list)
        episodes.append(list[0])
        return fresh.id
    }

    func watchRecord(forKey key: String) -> WatchRecord? {
        watchMap[key]
    }

    func play(_ item: MediaItem) {
        playing = items.first { $0.id == item.id } ?? item
        findEnglishSubtitles(for: item.id)
    }

    /// Plays a chosen stream as a library title so progress is saved to it. The URL is never persisted.
    func play(libraryItemID id: MediaItem.ID, streamURL: URL, headers: [String: String]?, file: MediaFileInfo) -> Bool {
        guard var copy = item(id: id) else { return false }
        copy.streamURL = streamURL
        copy.streamHeaders = headers
        copy.file = file
        streamLinks[id] = StreamLink(itemID: id, url: streamURL, headers: headers, playedAt: Date())
        playing = copy
        findEnglishSubtitles(for: id)
        return true
    }

    func startOver(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progressSeconds = 0
        items[index].isWatched = false
        playing = items[index]
        persistWatch(items[index])
    }

    func toggleFavorite(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
        persistWatch(items[index])
    }

    func toggleWatched(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isWatched.toggle()
        if items[index].isWatched { items[index].progressSeconds = 0 }
        persistWatch(items[index])
    }

    func updateProgress(id: MediaItem.ID, seconds: TimeInterval) {
        if let index = episodes.firstIndex(where: { $0.id == id }) {
            episodes[index].progressSeconds = seconds
            episodes[index].lastPlayedAt = Date()
            if episodes[index].progressFraction >= 0.95 { episodes[index].isWatched = true }
            persistWatch(episodes[index])
            return
        }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progressSeconds = seconds
        items[index].lastPlayedAt = Date()
        if items[index].progressFraction >= 0.95 { items[index].isWatched = true }
        persistWatch(items[index])
    }

    private func persistWatch(_ item: MediaItem) {
        watchMap[item.historyKey] = WatchRecord(
            key: item.historyKey,
            progressSeconds: item.progressSeconds,
            isWatched: item.isWatched,
            isFavorite: item.isFavorite,
            lastPlayedAt: item.lastPlayedAt
        )
        WatchHistory.save(watchMap)
    }

    // MARK: Subtitles

    func subtitleOptions(for id: MediaItem.ID) -> [LoadedSubtitle] {
        subtitleLibrary[id] ?? []
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

    // MARK: Automatic English subtitles

    /// Looks for English subtitles on OpenSubtitles without the viewer asking, and switches them on.
    /// It runs when a title's page opens and when playback starts, once per title per session.
    func findEnglishSubtitles(for id: MediaItem.ID) {
        guard !autoSubtitleTried.contains(id) else { return }
        Task { @MainActor in
            await self.autoFindEnglishSubtitles(for: id)
        }
    }

    private func subtitleQuery(for item: MediaItem) -> OpenSubtitlesClient.Query? {
        if item.kind == .episode {
            guard let parent = item.parentIMDbID, !parent.isEmpty,
                  let season = item.seasonNumber, let episode = item.episodeNumber else { return nil }
            return .episode(parentIMDb: parent, season: season, episode: episode)
        }
        // A show's own card has no video; its episodes are looked up when they play.
        if item.tmdbShowID != nil { return nil }
        if let imdb = item.imdbID, !imdb.isEmpty { return .imdb(imdb) }
        return .title(item.title, year: item.year)
    }

    /// Never replaces subtitles that are already loaded, never changes a choice the viewer made, and does
    /// nothing without an OpenSubtitles key. A failed lookup is tried again the next time.
    @MainActor
    private func autoFindEnglishSubtitles(for id: MediaItem.ID) async {
        guard !autoSubtitleTried.contains(id), subtitleOptions(for: id).isEmpty,
              let item = item(id: id), let query = subtitleQuery(for: item),
              let client = openSubtitlesClient else { return }
        autoSubtitleTried.insert(id)
        autoSubtitleNote[id] = "Finding English subtitles…"
        do {
            let results = try await client.search(query, languages: ["en"])
            // Forced tracks only cover foreign-language lines; plain English beats SDH when both exist.
            let usable = results.filter { !$0.isForced }
            guard let best = usable.first(where: { !$0.isSDH }) ?? usable.first else {
                autoSubtitleNote[id] = "No English subtitles found for this title yet."
                return
            }
            let cues = try await client.download(best)
            if subtitleOptions(for: id).isEmpty {
                let previousChoice = subtitleChoice[id]
                addSubtitle(LoadedSubtitle(track: best.track, cues: cues), for: id)
                if let previousChoice { subtitleChoice[id] = previousChoice }
            }
            autoSubtitleNote[id] = nil
        } catch {
            autoSubtitleTried.remove(id)
            if Task.isCancelled {
                autoSubtitleNote[id] = nil
            } else {
                autoSubtitleNote[id] = "Couldn't get English subtitles. \(error.localizedDescription)"
            }
        }
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

    var tmdbClient: TMDBClient? {
        let key = ServiceKeys.value(ServiceKeys.tmdb)
        return key.isEmpty ? nil : TMDBClient(apiKey: key)
    }

    /// TheTVDB: backs up TMDB for episode lists and fills in missing titles, summaries and pictures.
    var tvdbClient: TVDBClient? {
        let key = ServiceKeys.value(ServiceKeys.tvdb)
        return key.isEmpty ? nil : TVDBClient(apiKey: key)
    }

    /// The NihonSub bridge on your Mac. Nil until its address and token are entered.
    var nihonSubClient: NihonSubClient? {
        NihonSubClient(
            address: ServiceKeys.value(ServiceKeys.nihonSubAddress),
            token: ServiceKeys.value(ServiceKeys.nihonSubToken)
        )
    }

    /// Asks your Mac to write subtitles for a stream. The job keeps going if the screen is closed,
    /// and the finished track is added to the title and switched on.
    func generateSubtitles(link: StreamLink, language: NihonSubClient.Language) {
        let id = link.itemID
        guard let client = nihonSubClient, nihonSubTasks[id] == nil else { return }
        nihonSubStatus[id] = NihonSubStatus(language: language, progress: "Sending to your Mac…", failure: nil, isRunning: true)
        nihonSubTasks[id] = Task { @MainActor in
            do {
                let cues = try await client.generate(url: link.url, headers: link.headers, language: language) { status in
                    self.nihonSubStatus[id]?.progress = status.progressText
                }
                let track = SubtitleTrack(
                    id: "nihonsub-\(language.rawValue)-\(id.uuidString)",
                    languageCode: language.trackLanguageCode,
                    displayName: "\(language.displayName) (NihonSub AI)",
                    origin: .online,
                    format: .srt
                )
                self.addSubtitle(LoadedSubtitle(track: track, cues: cues), for: id)
                self.nihonSubStatus[id] = NihonSubStatus(language: language, progress: "Subtitles ready", failure: nil, isRunning: false)
            } catch {
                // A stopped job can surface as a cancelled network call, not only a CancellationError.
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    self.nihonSubStatus[id] = nil
                } else {
                    self.nihonSubStatus[id] = NihonSubStatus(language: language, progress: "", failure: error.localizedDescription, isRunning: false)
                }
            }
            self.nihonSubTasks[id] = nil
        }
    }

    /// Stops a running job, on the Mac too.
    func cancelNihonSub(for id: MediaItem.ID) {
        nihonSubTasks[id]?.cancel()
    }

    /// Dismisses a finished or failed job's message. A running job is left alone.
    func clearNihonSubStatus(for id: MediaItem.ID) {
        guard nihonSubTasks[id] == nil else { return }
        nihonSubStatus[id] = nil
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
