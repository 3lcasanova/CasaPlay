// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Asks every enabled provider for streams at once, with a timeout each, and keeps going
// when one fails. Primary results are published as soon as they arrive; backups never
// hold them up. Results are matched strictly to the requested film or episode,
// de-duplicated, checked for real quality, and ranked.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ContentRequest: Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable { case movie, episode }
    public var kind: Kind
    /// Stremio-style id of the film or series, e.g. "tt0111161".
    public var id: String
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?

    public static func movie(id: String, title: String, year: Int?) -> ContentRequest {
        ContentRequest(kind: .movie, id: id, title: title, year: year)
    }

    public static func episode(seriesID: String, title: String, season: Int, episode: Int, year: Int? = nil) -> ContentRequest {
        ContentRequest(kind: .episode, id: seriesID, title: title, year: year, season: season, episode: episode)
    }

    public var stremioType: String { kind == .movie ? "movie" : "series" }
    public var stremioID: String {
        guard kind == .episode, let season, let episode else { return id }
        return "\(id):\(season):\(episode)"
    }

    public var label: String {
        guard kind == .episode, let season, let episode else { return title }
        return "\(title) · S\(String(format: "%02d", season))E\(String(format: "%02d", episode))"
    }
}

public struct StreamCandidate: Identifiable, Equatable, Sendable {
    public enum Location: Equatable, Sendable {
        case http(URL, headers: [String: String])
        case torrent(InfoHash, fileIndex: Int?, trackers: [URL])
        /// An HTTPS link to a .torrent file. Its info hash is only known once the file has
        /// been downloaded, which happens when the user picks it.
        case torrentFile(URL)
        /// A link to the title on another service's website or app. Never played in CasaPlay;
        /// listed under "Where to watch".
        case external(URL)
        case unsupported(String)
    }

    /// Text shown when an external link is treated as a stream.
    public static let externalReason = "This opens in another app or website."

    /// Shown for a stream Apple's player can't open when the compatibility player (VLC) can.
    public static let compatibilityNote = "Plays in CasaPlay's compatibility player; checked once playback starts."

    /// For a "Where to watch" entry: the service ("Amazon Prime Video") and the offer
    /// ("Subscription, Rent, Buy"), taken from the two lines of the add-on's label.
    public var externalService: (name: String, detail: String?)? {
        guard case .external = location else { return nil }
        let lines = label.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        let name = lines.first.flatMap { $0.isEmpty ? nil : $0 } ?? providerName
        return (name, lines.count > 1 ? lines[1] : nil)
    }
    public var id: String
    public var providerID: String
    public var providerName: String
    public var providerRole: ProviderRole
    public var providerPriority: Int
    public var location: Location
    public var originalMagnet: String?
    public var label: String
    public var filename: String?
    public var advertised: AdvertisedQuality
    public var verification: VerificationState = .notChecked
    public var fetchedAt: Date
    public var bingeGroup: String?

    public init(id: String, providerID: String, providerName: String,
                providerRole: ProviderRole, providerPriority: Int,
                location: Location, label: String, filename: String?,
                advertised: AdvertisedQuality, fetchedAt: Date,
                bingeGroup: String? = nil) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.providerRole = providerRole
        self.providerPriority = providerPriority
        self.location = location
        self.label = label
        self.filename = filename
        self.advertised = advertised
        self.fetchedAt = fetchedAt
        self.bingeGroup = bingeGroup
    }

    /// Provider links often expire; re-resolve before playing after this long.
    public func isProbablyExpired(now: Date = Date(), after: TimeInterval = 20 * 60) -> Bool {
        if case .http = location { return now.timeIntervalSince(fetchedAt) > after }
        return false
    }

    var dedupeKey: String {
        switch location {
        case .http(let url, _):
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
            c?.fragment = nil
            return "http:" + (c?.string ?? url.absoluteString).lowercased()
        case .torrent(let hash, let index, _):
            return "bt:\(hash.hex):\(index ?? -1)"
        case .torrentFile(let url):
            return "btfile:" + url.absoluteString.lowercased()
        case .external(let url):
            return "ext:" + url.absoluteString.lowercased()
        case .unsupported:
            return "x:" + id
        }
    }
}

/// Anything that turns a request into stream candidates.
public protocol StreamProvider: Sendable {
    var providerID: String { get }
    var name: String { get }
    var role: ProviderRole { get }
    var priority: Int { get }
    func streams(for request: ContentRequest) async throws -> [StreamCandidate]
}

/// Reads real quality from a stream.
public protocol StreamProbe: Sendable {
    func probe(_ candidate: StreamCandidate) async -> VerificationState
}

// MARK: - Stremio add-ons as providers

public struct StremioStreamProvider: StreamProvider {
    public let providerID: String
    public let name: String
    public let role: ProviderRole
    public let priority: Int
    let manifest: StremioManifest
    let client: StremioClient
    let timeout: TimeInterval

    public init(installed: InstalledExtension, client: StremioClient, timeout: TimeInterval = 12) {
        self.providerID = installed.id
        self.name = installed.name
        self.role = installed.role
        self.priority = installed.priority
        self.manifest = installed.manifest
        self.client = client
        self.timeout = timeout
    }

    public func streams(for request: ContentRequest) async throws -> [StreamCandidate] {
        guard manifest.handles(.stream, type: request.stremioType, id: request.stremioID) else { return [] }
        let now = Date()
        return try await client.streams(type: request.stremioType, id: request.stremioID, timeout: timeout)
            .prefix(200).enumerated().map { index, s in
                StreamCandidate(
                    id: "\(providerID)#\(index)",
                    providerID: providerID, providerName: name, providerRole: role, providerPriority: priority,
                    location: Self.location(s),
                    label: String(s.label.prefix(500)),
                    filename: s.behaviorHints?.filename.map { String($0.prefix(300)) },
                    advertised: AdvertisedQuality.parse([s.label, s.behaviorHints?.filename ?? ""].joined(separator: " "),
                                                        size: s.behaviorHints?.videoSize),
                    fetchedAt: now,
                    bingeGroup: s.behaviorHints?.bingeGroup
                )
            }
    }

    static func location(_ s: StremioStream) -> StreamCandidate.Location {
        if let text = s.url, let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            guard scheme == "https" || (scheme == "http" && URLPolicy.isLocal(url.host ?? "")) else {
                return .unsupported(scheme == "http"
                    ? "Plain HTTP streams from the internet are blocked by Apple's App Transport Security."
                    : "Unsupported link type (\(scheme)).")
            }
            var headers: [String: String] = [:]
            for (k, v) in s.behaviorHints?.proxyHeaders?.request ?? [:] where Self.allowedHeader(k) {
                headers[k] = String(v.prefix(2000))
            }
            return .http(url, headers: headers)
        }
        if let hex = s.infoHash, let hash = InfoHash(hex: hex.lowercased()) {
            // Torrents with no usable tracker still play: the engine falls back to public trackers.
            let trackers = (s.sources ?? []).compactMap { src -> URL? in
                guard src.hasPrefix("tracker:") else { return nil }
                return URL(string: String(src.dropFirst("tracker:".count)))
            }.filter { $0.host != nil && ["http", "https", "udp"].contains($0.scheme?.lowercased() ?? "") }
            if let filename = s.behaviorHints?.filename,
               ["mkv", "avi", "webm"].contains((filename as NSString).pathExtension.lowercased()) {
                return .unsupported("This file format requires a compatibility player.")
            }
            return .torrent(hash, fileIndex: s.fileIdx, trackers: trackers)
        }
        if s.ytId != nil { return .unsupported("YouTube links can't be played in CasaPlay.") }
        if let text = s.externalUrl {
            // Only ordinary web links are kept; anything else could be an arbitrary app scheme.
            if let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil { return .external(url) }
            return .unsupported("This opens an external website or app.")
        }
        return .unsupported("No playable link.")
    }

    /// Headers an add-on may ask for. Hop-by-hop and host headers are never forwarded.
    static func allowedHeader(_ name: String) -> Bool {
        let n = name.lowercased()
        let blocked: Set<String> = ["host", "connection", "content-length", "transfer-encoding", "upgrade", "proxy-authorization", "te", "keep-alive"]
        return !blocked.contains(n) && n.count < 100 && n.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}

// MARK: - Matching

public enum ContentMatcher {
    public enum Result: Equatable, Sendable { case accept, reject(String) }

    /// Rejects results that name a different episode, a different film year or a clearly different title.
    public static func check(_ candidate: StreamCandidate, against request: ContentRequest) -> Result {
        let texts = [candidate.filename, candidate.label].compactMap { $0 }.filter { !$0.isEmpty }
        for text in texts {
            if let (s, e) = episodeMarker(text) {
                if request.kind == .movie { return .reject("This is an episode (S\(pad(s))E\(pad(e))), not the film.") }
                if s != request.season || e != request.episode {
                    return .reject("Wrong episode: S\(pad(s))E\(pad(e)).")
                }
            } else if request.kind == .episode, let s = seasonOnlyMarker(text), s != request.season {
                return .reject("Wrong season: season \(s).")
            }
        }
        if let filename = candidate.filename, !filename.isEmpty {
            let parsed = FilenameParser.parse(filename)
            if request.kind == .movie, let y = parsed.year, let want = request.year, abs(y - want) > 1 {
                return .reject("Different year (\(y)).")
            }
            if !request.title.isEmpty, titleSimilarity(parsed.title, request.title) < 0.34,
               tokens(parsed.title).count >= 2 {
                return .reject("Different title (\(parsed.title)).")
            }
        }
        return .accept
    }

    static func pad(_ n: Int) -> String { String(format: "%02d", n) }

    static func episodeMarker(_ text: String) -> (Int, Int)? {
        let patterns = [#"(?i)\bS(\d{1,2})[ ._-]?E(\d{1,3})\b"#, #"(?i)\b(\d{1,2})x(\d{2,3})\b"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let a = Range(m.range(at: 1), in: text), let b = Range(m.range(at: 2), in: text),
                  let s = Int(text[a]), let e = Int(text[b]) else { continue }
            return (s, e)
        }
        return nil
    }

    static func seasonOnlyMarker(_ text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: #"(?i)\b(?:S|Season[ ._]?)(\d{1,2})\b(?![ ._-]?E\d)"#),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let a = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[a])
    }

    static func tokens(_ s: String) -> Set<String> {
        let stop: Set<String> = ["the", "a", "an", "of", "and", "le", "la", "les", "el", "de"]
        return Set(s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stop.contains($0) })
    }

    /// Share of the requested title's words present in the found title.
    static func titleSimilarity(_ found: String, _ wanted: String) -> Double {
        let w = tokens(wanted), f = tokens(found)
        guard !w.isEmpty else { return 1 }
        return Double(w.intersection(f).count) / Double(w.count)
    }
}

// MARK: - Aggregation

public struct ProviderOutcome: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable {
        case waiting
        case finished(count: Int, ms: Int)
        case failed(String)
        case timedOut
    }
    public var id: String { providerID }
    public var providerID: String
    public var name: String
    public var role: ProviderRole
    public var status: Status
    public var rejected: Int = 0
}

public struct SourceResults: Equatable, Sendable {
    /// Placeholder used before the first aggregator snapshot arrives.
    public init() {
        self.request = ContentRequest(kind: .movie, id: "", title: "", year: nil)
        self.mode = .preferUHD
    }
    /// Used by SourceAggregator to build a live snapshot.
    public init(request: ContentRequest, mode: QualityMode) {
        self.request = request
        self.mode = mode
    }
    public var request: ContentRequest
    public var mode: QualityMode
    public var outcomes: [ProviderOutcome] = []
    /// Admitted under `mode`, best first.
    public var ranked: [StreamCandidate] = []
    /// Found but not admitted under `mode` (still shown on request).
    public var hidden: [StreamCandidate] = []
    public var rejected: [(candidate: StreamCandidate, reason: String)] = []
    public var primaryFinished = false
    public var finished = false

    /// Other services the title is available on, from add-ons such as WatchHub. One entry per
    /// service and offer, in the order the add-ons returned them.
    public var whereToWatch: [StreamCandidate] {
        var seen = Set<String>()
        return hidden
            .filter { $0.externalService != nil }
            .sorted { $0.id.compare($1.id, options: .numeric) == .orderedAscending }
            .filter { c in
                guard let s = c.externalService else { return false }
                return seen.insert((s.name + "|" + (s.detail ?? "")).lowercased()).inserted
            }
    }

    /// Hidden streams that are real streams, not "Where to watch" links.
    public var hiddenStreamCount: Int {
        hidden.filter {
            if case .unplayable = $0.verification { return false }
            return $0.externalService == nil
        }.count
    }

    public var unavailableReasons: [String] {
        Set(hidden.compactMap { candidate -> String? in
            guard candidate.externalService == nil,
                  case .unplayable(let reason) = candidate.verification else { return nil }
            return reason
        }).sorted()
    }
    /// Probes still running.
    public var checking = 0

    public static func == (a: SourceResults, b: SourceResults) -> Bool {
        a.request == b.request && a.mode == b.mode && a.outcomes == b.outcomes && a.ranked == b.ranked
            && a.hidden == b.hidden && a.primaryFinished == b.primaryFinished && a.finished == b.finished && a.checking == b.checking
            && a.rejected.map(\.reason) == b.rejected.map(\.reason)
    }

    /// The stream to start automatically, or nil while a claimed-4K stream is still being checked
    /// (so a 1080p link is never picked just because it answered first).
    public var bestChoice: StreamCandidate? {
        // Only modes that can offer 4K wait for a claimed-4K stream to be checked.
        let offers4K = mode.onlyResolution == nil || mode == .uhdOnly
        let pending4K = offers4K && (ranked + hidden).contains { c in
            c.advertised.resolution == .uhd2160 && (c.verification == .notChecked || c.verification == .checking)
        }
        guard let first = ranked.first else { return nil }
        if first.verification.verified?.resolution == .uhd2160 { return first }
        if pending4K || !primaryFinished { return nil }
        return first
    }

    /// The explicit "4K only found nothing" message, once everything has finished.
    public var emptyMessage: String? {
        guard finished, ranked.isEmpty else { return nil }
        let total = hiddenStreamCount
        if total == 0, !unavailableReasons.isEmpty {
            return "Sources returned matching results, but CasaPlay couldn't play them."
        }
        if hidden.isEmpty, !rejected.isEmpty {
            return request.kind == .movie
                ? "No results matched this movie."
                : "No results matched this episode."
        }
        switch mode {
        case .uhdOnly:
            return total == 0
                ? "No verified 4K stream was found. No provider returned a playable stream."
                : "No verified 4K stream was found. \(total) other stream\(total == 1 ? "" : "s") (lower or unconfirmed resolution) are hidden by 4K only."
        case .allowFHDFallback:
            return total == 0 ? "No playable 4K or 1080p stream was found." : "No 4K or 1080p stream was found. \(total) lower-resolution stream\(total == 1 ? " is" : "s are") hidden."
        case .preferUHD:
            return "No playable stream was found."
        case .fhdOnly, .hd720Only, .sdOnly:
            let name = mode.onlyResolution?.label ?? "matching"
            return total == 0
                ? "No playable \(name) stream was found."
                : "No \(name) stream was found. \(total) stream\(total == 1 ? "" : "s") at other resolutions \(total == 1 ? "is" : "are") hidden."
        }
    }
}

public actor SourceAggregator {
    private let providers: [any StreamProvider]
    private let probe: (any StreamProbe)?
    public var providerTimeout: TimeInterval
    public var maxConcurrentProbes: Int

    public init(providers: [any StreamProvider], probe: (any StreamProbe)?, providerTimeout: TimeInterval = 15, maxConcurrentProbes: Int = 4) {
        self.providers = providers
        self.probe = probe
        self.providerTimeout = providerTimeout
        self.maxConcurrentProbes = maxConcurrentProbes
    }

    /// Streams snapshots as providers answer and probes finish. Stop iterating to cancel everything.
    public nonisolated func run(_ request: ContentRequest, mode: QualityMode) -> AsyncStream<SourceResults> {
        AsyncStream { continuation in
            let task = Task { await self.execute(request, mode: mode, continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(_ request: ContentRequest, mode: QualityMode, _ out: AsyncStream<SourceResults>.Continuation) async {
        var results = SourceResults(request: request, mode: mode)
        results.outcomes = providers.map { ProviderOutcome(providerID: $0.providerID, name: $0.name, role: $0.role, status: .waiting) }
        var all: [String: StreamCandidate] = [:]   // by dedupe key
        var byID: [String: String] = [:]           // candidate id -> dedupe key
        var probeQueue: [String] = []

        func publish() {
            let admitted = all.values.filter { QualityRanking.admits($0.advertised, $0.verification, mode: mode) }
            let order: (StreamCandidate, StreamCandidate) -> Bool = { a, b in
                let ta = QualityRanking.tier(a.advertised, a.verification), tb = QualityRanking.tier(b.advertised, b.verification)
                if ta != tb { return ta < tb }
                if a.providerPriority != b.providerPriority { return a.providerPriority < b.providerPriority }
                let ba = a.verification.verified?.bitrate ?? 0, bb = b.verification.verified?.bitrate ?? 0
                if ba != bb { return ba > bb }
                return (a.advertised.sizeBytes ?? 0) > (b.advertised.sizeBytes ?? 0)
            }
            results.ranked = admitted.sorted(by: order)
            let admittedIDs = Set(admitted.map(\.id))
            results.hidden = all.values.filter { !admittedIDs.contains($0.id) }.sorted(by: order)
            results.primaryFinished = !results.outcomes.contains { $0.role == .primary && $0.status == .waiting }
            out.yield(results)
        }

        func add(_ found: [StreamCandidate], from index: Int) {
            for var c in found {
                // A "where to watch" link is named after the service, not the film, so the
                // title check does not apply to it.
                if case .external = c.location {
                    c.verification = .unplayable(StreamCandidate.externalReason)
                } else if case .reject(let reason) = ContentMatcher.check(c, against: request) {
                    results.rejected.append((c, reason))
                    results.outcomes[index].rejected += 1
                    continue
                }
                if case .unsupported(let why) = c.location { c.verification = .unplayable(why) }
                let key = c.dedupeKey
                if let existing = all[key], existing.providerPriority <= c.providerPriority { continue }
                all[key] = c
                byID[c.id] = key
                if case .notChecked = c.verification { probeQueue.append(c.id) }
            }
        }

        await withTaskGroup(of: (Int, Result<[StreamCandidate], Error>, Int).self) { group in
            for (index, provider) in providers.enumerated() {
                let timeout = providerTimeout
                group.addTask {
                    let start = Date()
                    do {
                        let found = try await withTimeout(timeout) { try await provider.streams(for: request) }
                        return (index, .success(found), Int(Date().timeIntervalSince(start) * 1000))
                    } catch {
                        return (index, .failure(error), Int(Date().timeIntervalSince(start) * 1000))
                    }
                }
            }
            publish()
            var probesRunning = 0
            var probeTasks = Set<String>()

            func startProbes(_ group: inout TaskGroup<(Int, Result<[StreamCandidate], Error>, Int)>) {
                guard let probe else { probeQueue = []; return }
                // Check claimed-4K streams first: they decide the ranking.
                probeQueue.sort { a, b in
                    let ca = all[byID[a] ?? ""]?.advertised.resolution ?? .unknown
                    let cb = all[byID[b] ?? ""]?.advertised.resolution ?? .unknown
                    return ca > cb
                }
                while probesRunning < maxConcurrentProbes, !probeQueue.isEmpty {
                    let id = probeQueue.removeFirst()
                    guard let key = byID[id], let candidate = all[key], !probeTasks.contains(id) else { continue }
                    probeTasks.insert(id)
                    probesRunning += 1
                    all[key]?.verification = .checking
                    group.addTask {
                        let state = await probe.probe(candidate)
                        var updated = candidate
                        updated.verification = state
                        return (-1, .success([updated]), 0)
                    }
                }
                results.checking = probesRunning + probeQueue.count
            }

            startProbes(&group)
            while let (index, result, ms) = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                if index == -1 {
                    probesRunning -= 1
                    if case .success(let list) = result, let updated = list.first, let key = byID[updated.id] {
                        all[key]?.verification = updated.verification
                    }
                } else {
                    switch result {
                    case .success(let found):
                        add(found, from: index)
                        results.outcomes[index].status = .finished(count: found.count, ms: ms)
                    case .failure(let error):
                        results.outcomes[index].status = (error as? ExtensionError) == .timedOut
                            ? .timedOut
                            : .failed((error as? LocalizedError)?.errorDescription ?? "Request failed.")
                    }
                }
                startProbes(&group)
                publish()
            }
        }
        results.checking = 0
        results.finished = true
        publish()
        out.finish()
    }
}

// MARK: - Probe for HLS playlists (all platforms)

/// Reads HLS master playlists directly; hands other streams to `fallback` (AVFoundation on Apple platforms).
public struct PlaylistProbe: StreamProbe {
    let transport: HTTPTransport
    let fallback: (any StreamProbe)?
    let timeout: TimeInterval
    /// True when the app bundles a compatibility player (VLC). Then MKV, AVI and similar files
    /// are playable, not "can't play".
    let compatibilityPlays: Bool

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        fallback: (any StreamProbe)? = nil,
        timeout: TimeInterval = 12,
        compatibilityPlays: Bool = false
    ) {
        self.transport = transport
        self.fallback = fallback
        self.timeout = timeout
        self.compatibilityPlays = compatibilityPlays
    }

    public func probe(_ candidate: StreamCandidate) async -> VerificationState {
        switch candidate.location {
        case .unsupported(let why): return .unplayable(why)
        case .external: return .unplayable(StreamCandidate.externalReason)
        case .torrent, .torrentFile: return .unreadable("Checked once playback starts (the data comes from peers).")
        case .http(let url, let headers):
            let ext = url.pathExtension.lowercased()
            if ["mkv", "avi", "webm", "wmv", "flv"].contains(ext) {
                return compatibilityPlays
                    ? .unreadable(StreamCandidate.compatibilityNote)
                    : .unplayable("\(ext.uppercased()) files don't play in Apple's player.")
            }
            if ext == "m3u8" || ext == "m3u" {
                var request = URLRequest(url: url)
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                let finalRequest = request
                guard let response = try? await withTimeout(timeout, { try await transport.send(finalRequest) }) else {
                    return .unreadable("The playlist didn't answer in time.")
                }
                guard response.status == 200 else {
                    return [401, 403, 410].contains(response.status)
                        ? .unplayable("The link was refused (\(response.status)); it may have expired.")
                        : .unreadable("The playlist answered \(response.status).")
                }
                let text = String(decoding: response.body.prefix(512 * 1024), as: UTF8.self)
                guard text.hasPrefix("#EXTM3U") else { return .unplayable("Not a valid HLS playlist.") }
                if HLSPlaylist.isMaster(text), let q = HLSPlaylist.quality(text) { return .verified(q) }
                return .unreadable("Single-quality playlist: the resolution is confirmed during playback.")
            }
            return await fallback?.probe(candidate) ?? .unreadable("Checked during playback.")
        }
    }
}
