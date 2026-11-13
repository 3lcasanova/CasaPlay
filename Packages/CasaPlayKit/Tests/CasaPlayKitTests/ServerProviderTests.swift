// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Unit tests for PlexProvider and JellyfinProvider.
// All network calls are stubbed via FakeWeb (no real server needed).

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

// MARK: - PlexProviderTests

final class PlexProviderTests: XCTestCase {

    private func plexConfig() -> ServerConfig {
        ServerConfig(kind: .plex, name: "Test Plex",
                     baseURL: URL(string: "http://localhost:32400")!)
    }

    // MARK: Movie by GUID → 4K candidate with stream URL and token header

    func testMovieMatchByGUID() async throws {
        let web = FakeWeb()
        web.json("/library/all", """
        {"MediaContainer":{"Metadata":[{
            "title":"The Shawshank Redemption","year":1994,
            "Media":[{"videoResolution":"4k","width":3840,"height":2160,
                       "Part":[{"id":101,"file":"/media/shawshank.mkv","size":25000000000}]}]
        }]}}
        """)

        let config = plexConfig()
        let provider = PlexProvider(config: config, token: "tok123", transport: web)
        let req = ContentRequest.movie(id: "tt0111161", title: "The Shawshank Redemption", year: 1994)
        let candidates = try await provider.streams(for: req)

        XCTAssertEqual(candidates.count, 1)
        let c = candidates[0]
        XCTAssertEqual(c.advertised.resolution, .uhd2160)
        XCTAssertEqual(c.advertised.sizeBytes, 25_000_000_000)
        XCTAssertEqual(c.filename, "shawshank.mkv")

        guard case .http(let url, let headers) = c.location else {
            return XCTFail("Expected .http location")
        }
        XCTAssertTrue(url.absoluteString.contains("/library/parts/101/file"),
                      "Stream URL should reference part 101, got: \(url)")
        XCTAssertEqual(headers["X-Plex-Token"], "tok123")
    }

    // MARK: Episode filter — returns only the requested season/episode

    func testEpisodeMatch() async throws {
        let web = FakeWeb()
        web.json("/library/all", """
        {"MediaContainer":{"Metadata":[
            {"title":"Pilot","index":1,"parentIndex":1,
             "Media":[{"Part":[{"id":201,"file":"/media/breaking-bad-s01e01.mkv","size":1500000000}]}]},
            {"title":"Cat in the Bag","index":2,"parentIndex":1,
             "Media":[{"Part":[{"id":202,"file":"/media/breaking-bad-s01e02.mkv","size":1200000000}]}]}
        ]}}
        """)

        let config = plexConfig()
        let provider = PlexProvider(config: config, token: "tok456", transport: web)
        let req = ContentRequest.episode(seriesID: "tt0903747", title: "Breaking Bad", season: 1, episode: 2)
        let candidates = try await provider.streams(for: req)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates[0].filename?.contains("s01e02") ?? false,
                      "Should pick episode 2, got filename: \(candidates[0].filename ?? "nil")")
    }

    // MARK: Empty Metadata array → empty candidates

    func testNoMatchReturnsEmpty() async throws {
        let web = FakeWeb()
        web.json("/library/all", #"{"MediaContainer":{"Metadata":[]}}"#)

        let config = plexConfig()
        let provider = PlexProvider(config: config, token: "tok", transport: web)
        let req = ContentRequest.movie(id: "tt9999999", title: "Nonexistent", year: nil)
        let candidates = try await provider.streams(for: req)
        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: HTTP 401 propagates as an error

    func testHTTPErrorThrows() async {
        let web = FakeWeb()
        web.routes["/library/all"] = HTTPResponse(status: 401, body: Data())

        let config = plexConfig()
        let provider = PlexProvider(config: config, token: "bad", transport: web)
        let req = ContentRequest.movie(id: "tt0111161", title: "Any", year: nil)
        do {
            _ = try await provider.streams(for: req)
            XCTFail("Should have thrown on 401")
        } catch {}
    }
}

// MARK: - JellyfinProviderTests

final class JellyfinProviderTests: XCTestCase {

    private func jellyfinConfig() -> ServerConfig {
        ServerConfig(kind: .jellyfin, name: "Test Jellyfin",
                     baseURL: URL(string: "http://localhost:8096")!)
    }

    // MARK: Movie → stream URL contains item ID and static=true

    func testMovieStreamURL() async throws {
        let web = FakeWeb()
        web.json("/Items", """
        {"Items":[{
            "Id":"abc123","Name":"Inception",
            "Width":3840,"Height":2160,
            "MediaSources":[{"Id":"src1","Path":"/media/inception.mkv","Size":28000000000}]
        }],"TotalRecordCount":1}
        """)

        let config = jellyfinConfig()
        let provider = JellyfinProvider(config: config, apiKey: "jf_key_xyz", transport: web)
        let req = ContentRequest.movie(id: "tt1375666", title: "Inception", year: 2010)
        let candidates = try await provider.streams(for: req)

        XCTAssertEqual(candidates.count, 1)
        let c = candidates[0]
        XCTAssertEqual(c.advertised.resolution, .uhd2160)
        XCTAssertEqual(c.advertised.sizeBytes, 28_000_000_000)

        guard case .http(let url, let headers) = c.location else {
            return XCTFail("Expected .http location")
        }
        XCTAssertTrue(url.absoluteString.contains("/Videos/abc123/stream"),
                      "URL should reference item abc123, got: \(url)")
        XCTAssertTrue(url.absoluteString.contains("static=true"),
                      "URL should contain static=true, got: \(url)")
        XCTAssertTrue(headers["Authorization"]?.contains("MediaBrowser") ?? false,
                      "Authorization header missing or malformed")
    }

    // MARK: Episode filter — returns only the matching season+episode

    func testEpisodeSeasonFilter() async throws {
        let web = FakeWeb()
        web.json("/Items", """
        {"Items":[
            {"Id":"ep01","Name":"Pilot","IndexNumber":1,"ParentIndexNumber":1,
             "MediaSources":[{"Id":"s1"}]},
            {"Id":"ep02","Name":"The Roof","IndexNumber":2,"ParentIndexNumber":1,
             "MediaSources":[{"Id":"s2"}]}
        ],"TotalRecordCount":2}
        """)

        let config = jellyfinConfig()
        let provider = JellyfinProvider(config: config, apiKey: "key", transport: web)
        let req = ContentRequest.episode(seriesID: "tt0903747", title: "Breaking Bad", season: 1, episode: 1)
        let candidates = try await provider.streams(for: req)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates[0].id.contains("ep01"),
                      "Should pick ep01, got: \(candidates[0].id)")
    }

    // MARK: Empty Items array → empty candidates

    func testEmptyResponse() async throws {
        let web = FakeWeb()
        web.json("/Items", #"{"Items":[],"TotalRecordCount":0}"#)

        let config = jellyfinConfig()
        let provider = JellyfinProvider(config: config, apiKey: "key", transport: web)
        let req = ContentRequest.movie(id: "tt0000000", title: "Nothing", year: nil)
        let candidates = try await provider.streams(for: req)
        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: HTTP 403 propagates as an error

    func testHTTPErrorThrows() async {
        let web = FakeWeb()
        web.routes["/Items"] = HTTPResponse(status: 403, body: Data())

        let config = jellyfinConfig()
        let provider = JellyfinProvider(config: config, apiKey: "bad", transport: web)
        let req = ContentRequest.movie(id: "tt0111161", title: "Any", year: nil)
        do {
            _ = try await provider.streams(for: req)
            XCTFail("Should have thrown on 403")
        } catch {}
    }
}

// MARK: - ServerConfigTests

final class ServerConfigTests: XCTestCase {

    func testSecretKeyIsStable() {
        let id = UUID()
        let config = ServerConfig(id: id, kind: .plex, name: "P",
                                  baseURL: URL(string: "http://localhost:32400")!)
        XCTAssertEqual(config.secretKey, "server.\(id.uuidString)")
    }

    func testDisplaySourceShowsHostOnly() {
        let config = ServerConfig(kind: .jellyfin, name: "J",
                                  baseURL: URL(string: "http://192.168.1.50:8096")!)
        XCTAssertEqual(config.displaySource, "192.168.1.50")
    }

    func testPriorityDefault() {
        let c = ServerConfig(kind: .plex, name: "P",
                             baseURL: URL(string: "http://host")!)
        XCTAssertEqual(c.priority, 100)
    }

    func testKindLabel() {
        XCTAssertEqual(ServerKind.plex.label, "Plex")
        XCTAssertEqual(ServerKind.jellyfin.label, "Jellyfin")
    }

    func testDefaultPort() {
        XCTAssertEqual(ServerKind.plex.defaultPort, 32400)
        XCTAssertEqual(ServerKind.jellyfin.defaultPort, 8096)
    }

    func testServerStoreRoundTrip() throws {
        var store = ServerStore()
        store.servers.append(ServerConfig(kind: .plex, name: "P",
                                          baseURL: URL(string: "http://host:32400")!))
        store.servers.append(ServerConfig(kind: .jellyfin, name: "J",
                                          baseURL: URL(string: "http://host:8096")!))
        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(ServerStore.self, from: data)
        XCTAssertEqual(decoded.servers.count, 2)
        XCTAssertEqual(decoded.servers[0].kind, .plex)
        XCTAssertEqual(decoded.servers[1].kind, .jellyfin)
    }
}
