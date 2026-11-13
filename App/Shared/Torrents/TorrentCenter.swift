// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// App-side owner of the torrent engine. Transfers only run while CasaPlay is open:
// iOS, iPadOS and tvOS suspend apps in the background, so sessions are saved and
// closed when the app leaves the foreground and pick up again when it returns.

import SwiftUI
import CasaPlayKit

struct TorrentFeed: Codable, Hashable, Identifiable {
    var id: String { url }
    var name: String
    var url: String
}

@MainActor
@Observable
final class TorrentCenter {
    static let shared = TorrentCenter()

    let engine: TorrentEngine
    private(set) var summaries: [TorrentSummary] = []
    private(set) var usedBytes: Int64 = 0
    var settings: TorrentSettings
    var feeds: [TorrentFeed]
    /// Last problem to show the user.
    var message: String?
    private var poller: Task<Void, Never>?
    private var restored = false

    private static let settingsKey = "torrentSettings"
    private static let feedsKey = "torrentFeeds"

    init() {
        let defaults = UserDefaults.standard
        let settings = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(TorrentSettings.self, from: $0) } ?? TorrentSettings()
        self.settings = settings
        self.feeds = defaults.data(forKey: Self.feedsKey)
            .flatMap { try? JSONDecoder().decode([TorrentFeed].self, from: $0) } ?? []
        let engine = TorrentEngine(root: Self.storageRoot(), settings: settings, peerFactory: NetworkPeerTransport.factory)
        self.engine = engine
        TorrentResourceLoader.engine = engine
    }

    /// Apple TV: Caches, the only place tvOS allows (the system may purge it when the app isn't running).
    /// iPhone and iPad: Application Support, kept out of iCloud and computer backups.
    static func storageRoot() -> URL {
        let fm = FileManager.default
        #if os(tvOS)
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        #else
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        var url = base.appendingPathComponent("Torrents", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        #if !os(tvOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        #endif
        return url
    }

    // MARK: Lifecycle

    /// App became active: restore saved torrents once, then refresh stats every second.
    func start() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            guard let self else { return }
            if !self.restored {
                self.restored = true
                await self.engine.restore()
            }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// App is leaving the foreground: save progress and close connections.
    func suspend() {
        poller?.cancel()
        poller = nil
        Task { await engine.suspendAll() }
    }

    func refresh() async {
        summaries = await engine.summaries()
        usedBytes = await engine.usedBytes()
    }

    func summary(_ hash: InfoHash) -> TorrentSummary? { summaries.first { $0.infoHash == hash } }

    // MARK: Adding

    func add(magnet text: String) async -> InfoHash? {
        await perform { try await self.engine.add(magnet: text).infoHash }
    }

    func add(torrentFile data: Data) async -> InfoHash? {
        await perform { try await self.engine.add(torrentFile: data).infoHash }
    }

    func add(_ candidate: TorrentCandidate) async -> InfoHash? {
        if let magnet = candidate.magnet { return await add(magnet: magnet) }
        guard let url = candidate.torrentURL else { return nil }
        return await perform { try await self.engine.add(torrentURL: url).infoHash }
    }

    private func perform(_ body: () async throws -> InfoHash) async -> InfoHash? {
        message = nil
        do {
            let hash = try await body()
            await refresh()
            return hash
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: Control

    func pause(_ hash: InfoHash) async {
        await engine.session(hash)?.pause()
        await refresh()
    }

    func resume(_ hash: InfoHash) async {
        await engine.session(hash)?.start()
        await refresh()
    }

    func remove(_ hash: InfoHash) async {
        await engine.remove(hash, deleteData: true)
        await refresh()
    }

    func files(_ hash: InfoHash) async -> [TorrentFile] {
        await engine.session(hash)?.files() ?? []
    }

    func select(_ hash: InfoHash, file: Int) async -> Bool {
        do {
            try await engine.session(hash)?.selectFile(file)
            return true
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func clearCache() async {
        await engine.clearAll()
        await refresh()
    }

    /// Removes least recently used torrents until the cache is under its limit.
    func trimCache(keep: Set<InfoHash> = []) async {
        await engine.cleanUp(toFit: settings.storageLimit, keep: keep)
        await refresh()
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        let current = settings
        Task { await engine.update(settings: current) }
    }

    // MARK: Sources

    var providers: [any TorrentSourceProvider] {
        var list: [any TorrentSourceProvider] = [InternetArchiveProvider()]
        for feed in feeds {
            if let url = URL(string: feed.url), url.scheme?.lowercased() == "https" {
                list.append(RSSFeedProvider(name: feed.name, feedURL: url))
            }
        }
        return list
    }

    func addFeed(name: String, url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), parsed.scheme?.lowercased() == "https", parsed.host != nil else {
            message = "Feeds must be HTTPS addresses."
            return false
        }
        feeds.removeAll { $0.url == trimmed }
        feeds.append(TorrentFeed(name: name.isEmpty ? (parsed.host ?? "Feed") : name, url: trimmed))
        saveFeeds()
        return true
    }

    func removeFeed(_ feed: TorrentFeed) {
        feeds.removeAll { $0 == feed }
        saveFeeds()
    }

    private func saveFeeds() {
        if let data = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(data, forKey: Self.feedsKey)
        }
    }

    // MARK: Playback

    /// A library-style item for CasaPlay's player. The stream URL uses CasaPlay's own scheme,
    /// which `TorrentResourceLoader` serves from verified torrent pieces.
    func mediaItem(hash: InfoHash, file: TorrentFile) -> MediaItem? {
        guard let url = TorrentResourceLoader.url(hash: hash, fileIndex: file.index, fileName: file.name) else { return nil }
        let container = MediaContainer(fileExtension: file.fileExtension)
        // The real codecs are only known once AVFoundation reads the file; containers Apple's
        // player opens are routed to it, everything else gets the "needs another player" message.
        let info = MediaFileInfo(
            container: container,
            videoCodec: container.isNativeToApplePlayer ? .h264 : .other,
            sizeBytes: file.length
        )
        let parsed = FilenameParser.parse(file.name)
        return MediaItem(
            title: parsed.title.isEmpty ? file.name : parsed.title,
            year: parsed.year,
            runtimeSeconds: 0,
            file: info,
            sourceName: "BitTorrent",
            imdbID: parsed.imdbID,
            artHue: 32,
            streamURL: url
        )
    }
}

extension TorrentFile {
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "webm", "ts", "m2ts", "mpg", "mpeg", "wmv", "ogv"]

    var isVideo: Bool { Self.videoExtensions.contains(fileExtension) }
    var playsInCasaPlay: Bool { MediaContainer(fileExtension: fileExtension).isNativeToApplePlayer }
}
