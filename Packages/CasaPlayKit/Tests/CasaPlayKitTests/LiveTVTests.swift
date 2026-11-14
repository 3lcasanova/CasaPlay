// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

final class LiveTVTests: XCTestCase {

    // MARK: - Manifest

    private let manifestJSON = """
    {
      "id": "test.iptv", "version": "1.0.0", "name": "Test IPTV",
      "resources": ["catalog", {"name": "stream", "types": ["tv"], "idPrefixes": ["iptv:"]}],
      "types": ["tv", "movie"],
      "catalogs": [
        {"id": "channels", "type": "tv", "name": "All channels",
         "extra": [{"name": "genre", "options": ["News", "Sports", "Kids"]}, {"name": "search"}, {"name": "skip"}]},
        {"id": "by-country", "type": "tv", "name": "By country",
         "extra": [{"name": "genre", "isRequired": true, "options": ["US", "CA"]}]},
        {"id": "legacy", "type": "channel", "extraSupported": ["search", "skip"], "extraRequired": []},
        {"id": "needs-search", "type": "tv", "extra": [{"name": "search", "isRequired": true}]},
        {"id": "films", "type": "movie", "name": "Films"},
        {"id": "custom", "type": "other", "name": "Live Sports"}
      ]
    }
    """

    private func manifest() throws -> StremioManifest {
        try StremioManifest.validate(Data(manifestJSON.utf8))
    }

    func testGenreOptionsAndFlagsAreRead() throws {
        let m = try manifest()
        let all = try XCTUnwrap(m.catalogs.first { $0.id == "channels" })
        XCTAssertEqual(all.genreOptions, ["News", "Sports", "Kids"])
        XCTAssertTrue(all.supportsGenre)
        XCTAssertTrue(all.supportsSearch)
        XCTAssertTrue(all.supportsSkip)
        XCTAssertFalse(all.genreRequired)
        let country = try XCTUnwrap(m.catalogs.first { $0.id == "by-country" })
        XCTAssertTrue(country.genreRequired)
        XCTAssertTrue(country.requiresExtra)
    }

    func testLegacyExtraListsAreUnderstood() throws {
        let legacy = try XCTUnwrap(try manifest().catalogs.first { $0.id == "legacy" })
        XCTAssertTrue(legacy.supportsSearch)
        XCTAssertTrue(legacy.supportsSkip)
        XCTAssertFalse(legacy.requiresExtra)
    }

    func testLiveCatalogsAreChosenByTypeAndName() throws {
        let ids = try manifest().liveCatalogs.map(\.id)
        XCTAssertEqual(Set(ids), ["channels", "by-country", "legacy", "custom"])
        XCTAssertFalse(ids.contains("films"))
        XCTAssertFalse(ids.contains("needs-search"))
    }

    func testBrowsableCatalogsIncludeMoviesButNotSearchOnly() throws {
        let ids = try manifest().browsableCatalogs.map(\.id)
        XCTAssertTrue(ids.contains("films"))
        XCTAssertFalse(ids.contains("needs-search"))
    }

    func testSeriesNamedTVIsNotLive() {
        let c = StremioManifest.Catalog(id: "tv-shows", type: "series", name: "TV Shows")
        XCTAssertFalse(LiveTV.isLive(c))
    }

    func testBadOptionsDoNotBreakTheManifest() throws {
        let json = """
        {"id":"x","version":"1","name":"X","resources":["catalog"],"types":["tv"],
         "catalogs":[{"id":"c","type":"tv","extra":[{"name":"genre","options":[1,2]}]}]}
        """
        let m = try StremioManifest.validate(Data(json.utf8))
        XCTAssertEqual(m.catalogs[0].genreOptions, [])
        XCTAssertTrue(m.catalogs[0].supportsGenre)
    }

    // MARK: - Client

    private func channelsJSON(_ names: [String]) -> Data {
        let metas = names.map { #"{"id":"iptv:\#($0)","type":"tv","name":"\#($0)","logo":"https://img.example/\#($0).png"}"# }
        return Data(#"{"metas":[\#(metas.joined(separator: ","))]}"#.utf8)
    }

    func testCatalogRequestCarriesGenreAndSkip() async throws {
        let transport = FakeTransport()
        transport.routes["/catalog/tv/channels/genre=News & Weather&skip=100.json"] =
            HTTPResponse(status: 200, body: channelsJSON(["a"]))
        let client = try StremioClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, transport: transport)
        let metas = try await client.catalog(type: "tv", id: "channels", genre: "News & Weather", skip: 100)
        XCTAssertEqual(metas.first?.logo, "https://img.example/a.png")
        XCTAssertEqual(transport.sent.last?.url?.absoluteString,
                       "https://addon.example/catalog/tv/channels/genre=News%20%26%20Weather&skip=100.json")
    }

    func testCatalogRequestWithoutExtrasIsPlain() async throws {
        let transport = FakeTransport()
        transport.routes["/catalog/tv/channels.json"] = HTTPResponse(status: 200, body: channelsJSON([]))
        let client = try StremioClient(manifestURL: URL(string: "https://addon.example/manifest.json")!, transport: transport)
        let metas = try await client.catalog(type: "tv", id: "channels")
        XCTAssertTrue(metas.isEmpty)
        XCTAssertEqual(transport.sent.last?.url?.absoluteString, "https://addon.example/catalog/tv/channels.json")
    }

    // MARK: - Channels

    private func channel(_ id: String, _ name: String, poster: String? = nil, logo: String? = nil) -> StremioMetaPreview {
        StremioMetaPreview(id: id, type: "tv", name: name, poster: poster, logo: logo)
    }

    func testMergeSkipsRepeatsAndCountsNewChannels() {
        let first = [channel("1", "One"), channel("2", "Two")]
        let page = [channel("2", "Two"), channel("3", "Three")]
        let merged = LiveTV.merge(first, with: page)
        XCTAssertEqual(merged.channels.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(merged.added, 1)
        XCTAssertEqual(LiveTV.merge(merged.channels, with: page).added, 0)
    }

    func testFilterMatchesEveryWordIgnoringCase() {
        let list = [channel("1", "BBC News HD"), channel("2", "CNN"), channel("3", "News 24")]
        XCTAssertEqual(LiveTV.filter(list, matching: "news").map(\.id), ["1", "3"])
        XCTAssertEqual(LiveTV.filter(list, matching: "bbc hd").map(\.id), ["1"])
        XCTAssertEqual(LiveTV.filter(list, matching: "  ").count, 3)
    }

    func testArtworkPrefersPosterThenLogoAndOnlyWebAddresses() {
        XCTAssertEqual(LiveTV.artworkURL(for: channel("1", "A", poster: "https://p/1.png", logo: "https://l/1.png"))?.host, "p")
        XCTAssertEqual(LiveTV.artworkURL(for: channel("1", "A", poster: "javascript:alert(1)", logo: "https://l/1.png"))?.host, "l")
        XCTAssertNil(LiveTV.artworkURL(for: channel("1", "A", poster: "file:///etc/passwd")))
        XCTAssertEqual(LiveTV.artworkURL(for: channel("1", "A", logo: "http://cdn.example/a.png"))?.absoluteString, "https://cdn.example/a.png")
        XCTAssertEqual(LiveTV.artworkURL(for: channel("1", "A", logo: "http://192.168.1.5/a.png"))?.scheme, "http")
    }

    // MARK: - Streams

    private func streams(_ json: String) throws -> [StremioStream] {
        struct R: Decodable { let streams: [StremioStream] }
        return try JSONDecoder().decode(R.self, from: Data(json.utf8)).streams
    }

    func testOptionsKeepOnlyWebLinksAndPreferHLS() throws {
        let list = try streams("""
        {"streams":[
          {"url":"http://host.example:8080/live/1.ts","name":"Backup"},
          {"url":"https://host.example/live/1/index.m3u8","name":"Main HD\\nsecond line"},
          {"url":"https://host.example/live/1/index.m3u8","name":"Duplicate"},
          {"url":"rtmp://host.example/live/1","name":"RTMP"},
          {"ytId":"abc","name":"YouTube"},
          {"externalUrl":"https://example.com","name":"Site"},
          {"infoHash":"0123456789abcdef0123456789abcdef01234567"}
        ]}
        """)
        let options = LiveTV.options(from: list)
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].container, .hls)
        XCTAssertEqual(options[0].title, "Main HD")
        XCTAssertEqual(options[1].container, .ts)
        XCTAssertEqual(options[1].url.scheme, "http")
    }

    func testHeadersAreFilteredLikeOtherStreams() throws {
        let list = try streams("""
        {"streams":[{"url":"https://h.example/a.m3u8","behaviorHints":{"proxyHeaders":{"request":{"Referer":"https://site.example/","Host":"evil","Connection":"close"}}}}]}
        """)
        let option = try XCTUnwrap(LiveTV.options(from: list).first)
        XCTAssertEqual(option.headers, ["Referer": "https://site.example/"])
    }

    func testLinkWithoutExtensionIsHandedToTheCompatibilityPlayer() throws {
        let list = try streams(#"{"streams":[{"url":"http://host.example:8080/user/pass/1234"}]}"#)
        let option = try XCTUnwrap(LiveTV.options(from: list).first)
        XCTAssertEqual(option.container, .other)
        XCTAssertEqual(option.title, "Stream 1")
    }

    func testUnplayableOnlyDetection() throws {
        XCTAssertTrue(LiveTV.hasOnlyUnplayableLinks(try streams(#"{"streams":[{"ytId":"x"},{"externalUrl":"https://a.example"}]}"#)))
        XCTAssertFalse(LiveTV.hasOnlyUnplayableLinks(try streams(#"{"streams":[{"url":"https://a.example/x.m3u8"}]}"#)))
        XCTAssertFalse(LiveTV.hasOnlyUnplayableLinks([]))
    }
}
