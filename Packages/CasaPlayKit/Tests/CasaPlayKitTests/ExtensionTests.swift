// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

// MARK: - Fakes

/// Serves fixed responses by full URL or path.
final class FakeWeb: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    var routes: [String: HTTPResponse] = [:]
    var delay: TimeInterval = 0
    private(set) var hits: [String] = []

    func json(_ key: String, _ text: String) { routes[key] = HTTPResponse(status: 200, body: Data(text.utf8)) }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = request.url!
        lock.withLock { hits.append(url.absoluteString) }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return routes[url.absoluteString] ?? routes[url.path] ?? HTTPResponse(status: 404, body: Data())
    }
}

func manifestJSON(id: String = "org.example.addon", version: String = "1.0.0", resources: String = #"["stream"]"#,
                  types: String = #"["movie","series"]"#, extra: String = "") -> String {
    #"{"id":"\#(id)","version":"\#(version)","name":"Example \#(id)","resources":\#(resources),"types":\#(types),"catalogs":[],"idPrefixes":["tt"]\#(extra)}"#
}

struct FakeProvider: StreamProvider {
    let providerID: String
    let name: String
    let role: ProviderRole
    let priority: Int
    var delay: TimeInterval = 0
    var error: Error?
    var results: [StreamCandidate] = []

    func streams(for request: ContentRequest) async throws -> [StreamCandidate] {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if let error { throw error }
        return results
    }

    func candidate(_ n: Int, url: String, label: String, filename: String? = nil) -> StreamCandidate {
        StreamCandidate(id: "\(providerID)#\(n)", providerID: providerID, providerName: name, providerRole: role,
                        providerPriority: priority, location: .http(URL(string: url)!, headers: [:]),
                        label: label, filename: filename, advertised: .parse(label + " " + (filename ?? "")), fetchedAt: Date())
    }
}

/// Answers with fixed qualities keyed by URL.
struct FakeProbe: StreamProbe {
    var answers: [String: VerificationState]
    var delay: TimeInterval = 0
    func probe(_ c: StreamCandidate) async -> VerificationState {
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        guard case .http(let url, _) = c.location else { return .unreadable("n/a") }
        return answers[url.absoluteString] ?? .unreadable("unknown")
    }
}

func verified(_ w: Int, _ h: Int, bitrate: Int? = nil, range: DynamicRange? = .sdr) -> VerificationState {
    .verified(VerifiedQuality(source: .containerMetadata, width: w, height: h, dynamicRange: range, codec: "HEVC", bitrate: bitrate))
}

func collect(_ stream: AsyncStream<SourceResults>) async -> [SourceResults] {
    var all: [SourceResults] = []
    for await s in stream { all.append(s) }
    return all
}

// MARK: - Manifests and repositories

final class ManifestTests: XCTestCase {
    func testValidManifestAndResourceForms() throws {
        let m = try StremioManifest.validate(Data(manifestJSON(resources: #"["catalog",{"name":"stream","types":["movie"],"idPrefixes":["tt"]},"subtitles"]"#).utf8))
        XCTAssertEqual(m.capabilities, [.catalog, .stream, .subtitles])
        XCTAssertTrue(m.handles(.stream, type: "movie", id: "tt0111161"))
        XCTAssertFalse(m.handles(.stream, type: "series", id: "tt0944947:1:1"), "stream resource is movie-only")
        XCTAssertFalse(m.handles(.stream, type: "movie", id: "kitsu:1"), "id prefix must match")
        XCTAssertTrue(m.handles(.subtitles, type: "series", id: "tt0944947:1:1"))
        XCTAssertEqual(m.compatibility, .supported)
    }

    func testRejectsBadManifests() {
        let bad = [
            #"{"name":"x"}"#,
            manifestJSON(version: "latest"),
            manifestJSON(resources: "[]"),
            #"{"id":"","version":"1.0.0","name":"x","resources":["stream"],"types":[],"catalogs":[]}"#,
            "not json"
        ]
        for text in bad { XCTAssertThrowsError(try StremioManifest.validate(Data(text.utf8)), text) }
        XCTAssertThrowsError(try StremioManifest.validate(Data(repeating: 32, count: 600_000)))
    }

    func testConfigurationRequiredIsLimitedAndNoResourcesUnsupported() throws {
        let configured = try StremioManifest.validate(Data(manifestJSON(extra: #","behaviorHints":{"configurable":true,"configurationRequired":true}"#).utf8))
        if case .limited = configured.compatibility {} else { XCTFail("expected limited") }
        let useless = try StremioManifest.validate(Data(manifestJSON(resources: #"["addon_catalog"]"#).utf8))
        XCTAssertFalse(useless.compatibility.isUsable)
    }

    func testRepositoryFormatsAreToldApart() {
        let base = URL(string: "https://repo.example.com/index.json")!
        let nuvio = #"{"name":"Plugins","version":"1.0","scrapers":[{"id":"a","name":"Provider A","filename":"providers/a.js","supportedTypes":["movie"]}]}"#
        let n = RepositoryReader.read(Data(nuvio.utf8), from: base)
        XCTAssertEqual(n.format, .nuvioPlugins)
        XCTAssertEqual(n.entries.count, 1)
        XCTAssertFalse(n.entries[0].compatibility.isUsable)
        XCTAssertNil(n.entries[0].manifestURL, "no script URL is ever kept")
        XCTAssertTrue(n.lastError?.contains("JavaScript") == true)

        let kodi = #"<?xml version="1.0"?><addons><addon id="plugin.video.x" name="X" version="1.2.3" provider-name="y"></addon></addons>"#
        let k = RepositoryReader.read(Data(kodi.utf8), from: base)
        XCTAssertEqual(k.format, .kodiRepository)
        XCTAssertEqual(k.entries.first?.name, "X")
        XCTAssertFalse(k.entries[0].compatibility.isUsable)

        let casa = #"{"name":"My repo","addons":[{"manifest":"https://a.example.com/manifest.json","name":"A"},"https://b.example.com/manifest.json",{"manifest":"http://c.example.com/manifest.json"},{"manifest":"http://192.168.1.5:7000/manifest.json"}]}"#
        let c = RepositoryReader.read(Data(casa.utf8), from: base)
        XCTAssertEqual(c.format, .casaPlayRepository)
        XCTAssertEqual(c.entries.map(\.compatibility.isUsable), [true, true, false, true], "plain HTTP only on the home network")

        let list = RepositoryReader.read(Data(#"["https://a.example.com/manifest.json"]"#.utf8), from: base)
        XCTAssertEqual(list.entries.count, 1)

        let single = RepositoryReader.read(Data(manifestJSON().utf8), from: URL(string: "https://a.example.com/manifest.json")!)
        XCTAssertEqual(single.format, .stremioAddon)

        XCTAssertEqual(RepositoryReader.read(Data("hello".utf8), from: base).format, .unknown)
    }
}

final class ExtensionManagerTests: XCTestCase {
    private func manager(_ web: FakeWeb, file: URL = tempRoot().appendingPathComponent("extensions.json"),
                         secrets: SecretStore = MemorySecretStore()) -> ExtensionManager {
        ExtensionManager(file: file, transport: web, secrets: secrets)
    }

    func testInstallProtectsTokensAndPersists() async throws {
        let web = FakeWeb()
        let url = URL(string: "https://addon.example.com/SECRET-TOKEN-123/manifest.json")!
        web.json(url.absoluteString, manifestJSON(resources: #"["stream","subtitles"]"#))
        let file = tempRoot().appendingPathComponent("extensions.json")
        let secrets = MemorySecretStore()
        let m = manager(web, file: file, secrets: secrets)
        let installed = try await m.install(manifestURL: url)
        XCTAssertEqual(installed.displaySource, "addon.example.com")
        XCTAssertEqual(secrets.get(installed.secretKey), url.absoluteString)
        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(saved.contains("SECRET-TOKEN"), "tokens never reach the settings file")

        do { _ = try await m.install(manifestURL: url); XCTFail("duplicate") } catch {
            XCTAssertEqual(error as? ExtensionError, .duplicate)
        }

        // Upgrade path: a new manager reads the same file.
        let reloaded = manager(web, file: file, secrets: secrets)
        let state = await reloaded.state
        XCTAssertEqual(state.installed.map(\.id), ["org.example.addon"])
        XCTAssertEqual(state.schema, ExtensionState.currentSchema)
    }

    func testEnableOrderUpdateRemove() async throws {
        let web = FakeWeb()
        let a = URL(string: "https://a.example.com/manifest.json")!, b = URL(string: "https://b.example.com/manifest.json")!
        web.json(a.absoluteString, manifestJSON(id: "a"))
        web.json(b.absoluteString, manifestJSON(id: "b"))
        let secrets = MemorySecretStore()
        let m = manager(web, secrets: secrets)
        try await m.install(manifestURL: a)
        try await m.install(manifestURL: b, role: .backup)
        await m.move("b", by: -1)
        var ids = await m.enabledAddons.map(\.id)
        XCTAssertEqual(ids, ["b", "a"])
        await m.setEnabled("b", false)
        ids = await m.enabledAddons.map(\.id)
        XCTAssertEqual(ids, ["a"])

        web.json(a.absoluteString, manifestJSON(id: "a", version: "1.2.0"))
        await m.checkForUpdates()
        var item = await m.state.installed.first { $0.id == "a" }!
        XCTAssertTrue(item.updateAvailable)
        XCTAssertEqual(item.version, "1.0.0", "updates are never applied automatically")
        try await m.update("a")
        item = await m.state.installed.first { $0.id == "a" }!
        XCTAssertEqual(item.version, "1.2.0")
        XCTAssertFalse(item.updateAvailable)

        web.routes[b.absoluteString] = HTTPResponse(status: 500, body: Data())
        await m.checkForUpdates()
        let health = await m.state.installed.first { $0.id == "b" }!.health
        XCTAssertEqual(health.status, .failing("The server answered with error 500."))

        let key = await m.state.installed.first { $0.id == "a" }!.secretKey
        await m.remove("a")
        XCTAssertNil(secrets.get(key))
        let left = await m.state.installed.map(\.id)
        XCTAssertEqual(left, ["b"])
    }

    func testRefusesUnsupportedAndInsecure() async throws {
        let web = FakeWeb()
        let u = URL(string: "https://x.example.com/manifest.json")!
        web.json(u.absoluteString, manifestJSON(resources: #"["addon_catalog"]"#))
        let m = manager(web)
        do { _ = try await m.install(manifestURL: u); XCTFail() } catch {
            guard case .unsupported = error as? ExtensionError else { return XCTFail("\(error)") }
        }
        do { _ = try await m.install(manifestURL: URL(string: "http://x.example.com/manifest.json")!); XCTFail() } catch {
            XCTAssertEqual(error as? ExtensionError, .insecureURL)
        }
    }

    func testRepositoriesAndSingleManifestURLs() async throws {
        let web = FakeWeb()
        web.json("https://repo.example.com/nuvio.json", #"{"name":"P","version":"1","scrapers":[{"id":"a","name":"A","filename":"a.js"}]}"#)
        web.json("https://a.example.com/tok/manifest.json", manifestJSON())
        let m = manager(web)
        let repo = try await m.addRepository("https://repo.example.com/nuvio.json")
        XCTAssertEqual(repo.format, .nuvioPlugins)
        let single = try await m.addRepository("https://a.example.com/tok/manifest.json")
        XCTAssertEqual(single.format, .stremioAddon)
        let saved = await m.state.repositories.map(\.url.absoluteString)
        XCTAssertEqual(saved, ["https://repo.example.com/nuvio.json"], "single add-on URLs (which may hold tokens) aren't stored as repositories")
    }

    func testDamagedStateIsKeptAside() throws {
        let dir = tempRoot()
        let file = dir.appendingPathComponent("extensions.json")
        try Data("{broken".utf8).write(to: file)
        let state = ExtensionManager.load(file)
        XCTAssertEqual(state, ExtensionState())
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("extensions.unreadable-") })
    }
}

// MARK: - Streams, matching, quality

final class StreamParsingTests: XCTestCase {
    func testStremioStreamLocations() throws {
        let json = """
        {"streams":[
          {"name":"Example\\n4K","title":"Film.2019.2160p.HDR.HEVC","url":"https://cdn.example.com/a.mp4","behaviorHints":{"filename":"Film.2019.2160p.mp4","videoSize":12000000000,"proxyHeaders":{"request":{"Referer":"https://example.com","Host":"evil","User-Agent":"X"}}}},
          {"infoHash":"dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c","fileIdx":2,"sources":["tracker:udp://t.example.org:1337/announce","dht:x"],"title":"1080p"},
          {"ytId":"abc"},
          {"externalUrl":"https://example.com/watch"},
          {"url":"http://cdn.example.com/plain.mp4"},
          {"url":"http://192.168.1.20:8096/stream.mp4"}
        ]}
        """
        struct R: Decodable { let streams: [StremioStream] }
        let streams = try JSONDecoder().decode(R.self, from: Data(json.utf8)).streams
        let locations = streams.map(StremioStreamProvider.location)
        guard case .http(_, let headers) = locations[0] else { return XCTFail() }
        XCTAssertEqual(headers["Referer"], "https://example.com")
        XCTAssertNil(headers["Host"], "host headers are never forwarded")
        guard case .torrent(let hash, let idx, let trackers) = locations[1] else { return XCTFail() }
        XCTAssertEqual(hash.hex, "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c")
        XCTAssertEqual(idx, 2)
        XCTAssertEqual(trackers.map(\.absoluteString), ["udp://t.example.org:1337/announce"])
        for i in [2, 4] { guard case .unsupported = locations[i] else { return XCTFail("\(i)") } }
        guard case .external(let link) = locations[3] else { return XCTFail("an https externalUrl is a where-to-watch link") }
        XCTAssertEqual(link.absoluteString, "https://example.com/watch")
        guard case .http = locations[5] else { return XCTFail("home-network HTTP is allowed") }
        let q = AdvertisedQuality.parse(streams[0].label + " " + (streams[0].behaviorHints?.filename ?? ""), size: streams[0].behaviorHints?.videoSize)
        XCTAssertEqual(q.resolution, .uhd2160)
        XCTAssertEqual(q.dynamicRange, .hdr10)
        XCTAssertEqual(q.codec, "HEVC")
    }

    func testAdvertisedParsing() {
        XCTAssertEqual(AdvertisedQuality.parse("Movie 4K DV Atmos").dynamicRange, .dolbyVision)
        XCTAssertEqual(AdvertisedQuality.parse("Movie 4K DV Atmos").audio, "Atmos")
        XCTAssertEqual(AdvertisedQuality.parse("movie.1080p.x264.DDP5.1").resolution, .fhd1080)
        XCTAssertEqual(AdvertisedQuality.parse("movie.1080p.x264.DDP5.1").audio, "Dolby Digital Plus")
        XCTAssertEqual(AdvertisedQuality.parse("movie").resolution, .unknown)
        XCTAssertEqual(ResolutionClass(width: 3840, height: 1600), .uhd2160, "scope 4K counts by width")
        XCTAssertEqual(ResolutionClass(width: 1920, height: 800), .fhd1080)
    }

    func testMatching() {
        let ep = ContentRequest.episode(seriesID: "tt0944947", title: "Game of Thrones", season: 1, episode: 2)
        XCTAssertEqual(ep.stremioID, "tt0944947:1:2")
        func c(_ label: String, file: String? = nil) -> StreamCandidate {
            FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0).candidate(0, url: "https://x/a.mp4", label: label, filename: file)
        }
        XCTAssertEqual(ContentMatcher.check(c("Game.of.Thrones.S01E02.1080p"), against: ep), .accept)
        XCTAssertEqual(ContentMatcher.check(c("Game.of.Thrones.S01E03.1080p"), against: ep), .reject("Wrong episode: S01E03."))
        XCTAssertEqual(ContentMatcher.check(c("x", file: "got.1x05.mkv"), against: ep), .reject("Wrong episode: S01E05."))
        XCTAssertEqual(ContentMatcher.check(c("Game of Thrones Season 2 pack"), against: ep), .reject("Wrong season: season 2."))
        XCTAssertEqual(ContentMatcher.check(c("4K", file: "Breaking.Bad.S01E02.mkv"), against: ep), .reject("Different title (Breaking Bad)."))

        let movie = ContentRequest.movie(id: "tt0111161", title: "The Shawshank Redemption", year: 1994)
        XCTAssertEqual(ContentMatcher.check(c("4K", file: "The.Shawshank.Redemption.1994.2160p.mkv"), against: movie), .accept)
        XCTAssertEqual(ContentMatcher.check(c("4K", file: "The.Shawshank.Redemption.2004.2160p.mkv"), against: movie), .reject("Different year (2004)."))
        XCTAssertEqual(ContentMatcher.check(c("Shawshank S01E01"), against: movie), .reject("This is an episode (S01E01), not the film."))
        XCTAssertEqual(ContentMatcher.check(c("Provider\n2160p"), against: movie), .accept, "no file name: nothing to contradict")
    }

    func testHLSMasterPlaylist() throws {
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",VIDEO-RANGE=SDR
        v1080.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=25000000,RESOLUTION=3840x2160,CODECS="hvc1.2.4.L153.B0,ec-3",VIDEO-RANGE=PQ
        v2160.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=26000000,RESOLUTION=3840x2160,CODECS="dvh1.05.06,ec-3",VIDEO-RANGE=PQ
        dv.m3u8
        """
        let q = try XCTUnwrap(HLSPlaylist.quality(master))
        XCTAssertEqual(q.source, .playlist)
        XCTAssertEqual(q.resolution, .uhd2160)
        XCTAssertEqual(q.variants.count, 3)
        XCTAssertEqual(q.dynamicRange, .dolbyVision)
        XCTAssertEqual(q.codec, "HEVC (Dolby Vision)")
        XCTAssertEqual(q.audioFormats, ["Dolby Digital Plus"])
        XCTAssertNil(HLSPlaylist.quality("#EXTM3U\n#EXTINF:6,\nseg1.ts"))
    }

    func testPlaylistProbe() async {
        let web = FakeWeb()
        web.json("https://cdn.example.com/master.m3u8", "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=3840x2160,CODECS=\"hvc1.2.4.L150\",VIDEO-RANGE=HLG\nx.m3u8")
        web.routes["https://cdn.example.com/expired.m3u8"] = HTTPResponse(status: 403, body: Data())
        let probe = PlaylistProbe(transport: web)
        let p = FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0)
        let ok = await probe.probe(p.candidate(0, url: "https://cdn.example.com/master.m3u8", label: ""))
        XCTAssertEqual(ok.verified?.resolution, .uhd2160)
        XCTAssertEqual(ok.verified?.dynamicRange, .hlg)
        let expired = await probe.probe(p.candidate(1, url: "https://cdn.example.com/expired.m3u8", label: ""))
        XCTAssertFalse(expired.isPlayable)
        let mkv = await probe.probe(p.candidate(2, url: "https://cdn.example.com/film.mkv", label: "4K"))
        XCTAssertEqual(mkv, .unplayable("MKV files don't play in Apple's player."))
    }
}

// MARK: - Aggregation

final class AggregatorTests: XCTestCase {
    let movie = ContentRequest.movie(id: "tt0111161", title: "Example Film", year: 2020)

    func testVerified4KFromBackupBeatsPrimary1080AndClaimsAreChecked() async {
        var primary = FakeProvider(providerID: "primary", name: "Primary", role: .primary, priority: 0)
        primary.results = [
            primary.candidate(0, url: "https://p/1080.mp4", label: "1080p"),
            primary.candidate(1, url: "https://p/fake4k.mp4", label: "4K UHD"),          // claims 4K, really 1080p
            primary.candidate(2, url: "https://p/1080low.mp4", label: "1080p small"),
        ]
        var backup = FakeProvider(providerID: "backup", name: "Backup", role: .backup, priority: 1)
        backup.results = [backup.candidate(0, url: "https://b/2160.mp4", label: "")]   // no claim at all
        let probe = FakeProbe(answers: [
            "https://p/1080.mp4": verified(1920, 1080, bitrate: 15_000_000),
            "https://p/fake4k.mp4": verified(1920, 1080, bitrate: 9_000_000),
            "https://p/1080low.mp4": verified(1920, 1080, bitrate: 2_500_000),
            "https://b/2160.mp4": verified(3840, 2160, bitrate: 40_000_000, range: .hdr10),
        ])
        let agg = SourceAggregator(providers: [primary, backup], probe: probe)
        let final = await collect(agg.run(movie, mode: .preferUHD)).last!
        XCTAssertTrue(final.finished)
        XCTAssertEqual(final.ranked.map(\.id), ["backup#0", "primary#0", "primary#1", "primary#2"])
        XCTAssertEqual(final.ranked[1].verification.verified?.resolution, .fhd1080, "the '4K' label was not trusted")
        XCTAssertTrue(QualityRanking.isLowBitrate(final.ranked[3].verification.verified!))
        XCTAssertEqual(final.bestChoice?.id, "backup#0")
    }

    func testFourKOnlyReportsNothingExplicitly() async {
        var p = FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0)
        p.results = [p.candidate(0, url: "https://p/a.mp4", label: "4K"), p.candidate(1, url: "https://p/b.mp4", label: "1080p")]
        let probe = FakeProbe(answers: ["https://p/a.mp4": verified(1920, 1080), "https://p/b.mp4": verified(1920, 1080)])
        let final = await collect(SourceAggregator(providers: [p], probe: probe).run(movie, mode: .uhdOnly)).last!
        XCTAssertTrue(final.ranked.isEmpty)
        XCTAssertEqual(final.hidden.count, 2)
        XCTAssertEqual(final.emptyMessage, "No verified 4K stream was found. 2 other streams (lower or unconfirmed resolution) are hidden by 4K only.")
        XCTAssertNil(final.bestChoice)
    }

    func testAllResultsForAnotherFilmAreExplainedNotJustEmpty() async {
        var p = FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0)
        p.results = [p.candidate(0, url: "https://p/a.mp4", label: "1080p", filename: "Example.Film.1999.1080p.mkv"),
                     p.candidate(1, url: "https://p/b.mp4", label: "1080p", filename: "Example.Film.1985.720p.mkv")]
        let final = await collect(SourceAggregator(providers: [p], probe: nil).run(movie, mode: .preferUHD)).last!
        XCTAssertTrue(final.ranked.isEmpty)
        XCTAssertEqual(final.rejected.count, 2)
        XCTAssertEqual(final.outcomes.first?.rejected, 2)
        XCTAssertEqual(final.emptyMessage, "2 results were found, but they are all for a different title, year or episode, not this film. None of your sources has it.")
    }

    func testExternalLinksBecomeWhereToWatchNotStreams() async {
        var p = FakeProvider(providerID: "hub", name: "WatchHub", role: .backup, priority: 0)
        func link(_ n: Int, _ label: String, _ url: String) -> StreamCandidate {
            var c = p.candidate(n, url: "https://unused/x.mp4", label: label)
            c.location = .external(URL(string: url)!)
            return c
        }
        p.results = [link(0, "Amazon Prime Video\nSubscription, Rent, Buy", "https://app.primevideo.com/detail?gti=1"),
                     link(1, "Apple TV\nRent, Buy", "https://tv.apple.com/movie/1"),
                     link(2, "Apple TV\nRent, Buy", "https://tv.apple.com/movie/1?alt")]   // same service and offer twice
        let final = await collect(SourceAggregator(providers: [p], probe: nil).run(movie, mode: .preferUHD)).last!
        XCTAssertTrue(final.ranked.isEmpty, "a link to another service is never offered as a stream")
        XCTAssertTrue(final.rejected.isEmpty, "service names are not checked against the film title")
        XCTAssertEqual(final.whereToWatch.compactMap { $0.externalService?.name }, ["Amazon Prime Video", "Apple TV"])
        XCTAssertEqual(final.whereToWatch.first?.externalService?.detail, "Subscription, Rent, Buy")
        XCTAssertEqual(final.hiddenStreamCount, 0)
        XCTAssertEqual(final.emptyMessage, "No playable stream was found.")
    }

    func testExternalUrlMustBeHTTPS() {
        func stream(_ json: String) -> StremioStream { try! JSONDecoder().decode(StremioStream.self, from: Data(json.utf8)) }
        XCTAssertEqual(StremioStreamProvider.location(stream(#"{"name":"Netflix","externalUrl":"https://www.netflix.com/title/1"}"#)),
                       .external(URL(string: "https://www.netflix.com/title/1")!))
        if case .external = StremioStreamProvider.location(stream(#"{"name":"X","externalUrl":"someapp://open"}"#)) {
            XCTFail("only https links are kept")
        }
    }

    func testFallbackModeHidesSubFHDAndUnverifiedNeverCountsAs4K() async {
        var p = FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0)
        p.results = [p.candidate(0, url: "https://p/720.mp4", label: "720p"),
                     p.candidate(1, url: "https://p/1080.mp4", label: "1080p"),
                     p.candidate(2, url: "https://p/claim.mp4", label: "2160p")]
        let probe = FakeProbe(answers: ["https://p/720.mp4": verified(1280, 720), "https://p/1080.mp4": verified(1920, 1080)])
        let final = await collect(SourceAggregator(providers: [p], probe: probe).run(movie, mode: .allowFHDFallback)).last!
        XCTAssertEqual(final.ranked.map(\.id), ["p#2", "p#1"], "unverifiable 4K claim ranks above 1080p but stays unverified")
        XCTAssertNil(final.ranked[0].verification.verified)
        XCTAssertEqual(final.hidden.map(\.id), ["p#0"])
        let only4K = await collect(SourceAggregator(providers: [p], probe: probe).run(movie, mode: .uhdOnly)).last!
        XCTAssertTrue(only4K.ranked.isEmpty, "a label alone never qualifies for 4K only")
    }

    func testBackupsDontBlockPrimaryAndFailuresAreIsolated() async {
        var primary = FakeProvider(providerID: "primary", name: "Primary", role: .primary, priority: 0)
        primary.results = [primary.candidate(0, url: "https://p/a.mp4", label: "1080p")]
        let slowBackup = FakeProvider(providerID: "slow", name: "Slow", role: .backup, priority: 1, delay: 5)
        let broken = FakeProvider(providerID: "broken", name: "Broken", role: .primary, priority: 2, error: ExtensionError.requestFailed(502))
        let agg = SourceAggregator(providers: [primary, slowBackup, broken], probe: nil, providerTimeout: 1)
        let started = Date()
        var firstPrimaryDone: TimeInterval?
        var last: SourceResults?
        for await s in agg.run(movie, mode: .preferUHD) {
            if s.primaryFinished, firstPrimaryDone == nil { firstPrimaryDone = Date().timeIntervalSince(started) }
            last = s
        }
        XCTAssertLessThan(firstPrimaryDone ?? 99, 0.9, "primary results don't wait for the backup")
        XCTAssertEqual(last?.ranked.map(\.id), ["primary#0"])
        let statuses = Dictionary(uniqueKeysWithValues: (last?.outcomes ?? []).map { ($0.providerID, $0.status) })
        XCTAssertEqual(statuses["slow"], .timedOut)
        XCTAssertEqual(statuses["broken"], .failed("The server answered with error 502."))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "the slow provider was cut off by its timeout")
    }

    func testDedupeAndRejection() async {
        var a = FakeProvider(providerID: "a", name: "A", role: .primary, priority: 0)
        a.results = [a.candidate(0, url: "https://cdn/x.mp4", label: "1080p")]
        var b = FakeProvider(providerID: "b", name: "B", role: .backup, priority: 1)
        b.results = [b.candidate(0, url: "https://CDN/x.mp4#t", label: "1080p"),
                     b.candidate(1, url: "https://cdn/ep.mp4", label: "Example Film S01E01")]
        let final = await collect(SourceAggregator(providers: [a, b], probe: nil).run(movie, mode: .preferUHD)).last!
        XCTAssertEqual(final.ranked.map(\.id), ["a#0"], "the duplicate keeps the higher-priority provider")
        XCTAssertEqual(final.rejected.map(\.reason), ["This is an episode (S01E01), not the film."])
        XCTAssertEqual(final.outcomes.first { $0.providerID == "b" }?.rejected, 1)
    }

    func testBestChoiceWaitsForPending4KCheck() async {
        var p = FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0)
        p.results = [p.candidate(0, url: "https://p/1080.mp4", label: "1080p"), p.candidate(1, url: "https://p/4k.mp4", label: "4K")]
        let probe = FakeProbe(answers: ["https://p/1080.mp4": verified(1920, 1080), "https://p/4k.mp4": verified(3840, 2160)], delay: 0.2)
        let snapshots = await collect(SourceAggregator(providers: [p], probe: probe).run(movie, mode: .preferUHD))
        XCTAssertTrue(snapshots.dropLast().allSatisfy { $0.bestChoice?.id != "p#0" }, "1080p is never auto-picked while 4K is being checked")
        XCTAssertEqual(snapshots.last?.bestChoice?.id, "p#1")
    }

    func testCancellationStopsProviders() async {
        let slow = FakeProvider(providerID: "slow", name: "Slow", role: .primary, priority: 0, delay: 10)
        let agg = SourceAggregator(providers: [slow], probe: nil, providerTimeout: 30)
        let started = Date()
        let task = Task { await collect(agg.run(movie, mode: .preferUHD)) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        _ = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testStremioProviderEndToEnd() async throws {
        let web = FakeWeb()
        web.json("https://addon.example.com/manifest.json", manifestJSON())
        web.json("/stream/series/tt0944947%3A1%3A2.json", "{}")
        web.json("/stream/series/tt0944947:1:2.json", #"{"streams":[{"url":"https://cdn.example.com/e2.mp4","title":"S01E02 2160p"},{"url":"https://cdn.example.com/e3.mp4","title":"S01E03 2160p"}]}"#)
        let m = ExtensionManager(file: tempRoot().appendingPathComponent("e.json"), transport: web, secrets: MemorySecretStore())
        let installed = try await m.install(manifestURL: URL(string: "https://addon.example.com/manifest.json")!)
        let clientOpt = await m.client(for: installed)
        let client = try XCTUnwrap(clientOpt)
        let provider = StremioStreamProvider(installed: installed, client: client)
        let request = ContentRequest.episode(seriesID: "tt0944947", title: "Example Show", season: 1, episode: 2)
        let final = await collect(SourceAggregator(providers: [provider], probe: nil).run(request, mode: .preferUHD)).last!
        XCTAssertEqual(final.ranked.count, 1)
        XCTAssertEqual(final.rejected.first?.reason, "Wrong episode: S01E03.")
    }

    func testExpiry() {
        let p = FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0)
        var c = p.candidate(0, url: "https://x/a.mp4", label: "")
        c.fetchedAt = Date().addingTimeInterval(-30 * 60)
        XCTAssertTrue(c.isProbablyExpired())
    }
}
