// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

final class TVDBClientTests: XCTestCase {

    private func ok(_ text: String) -> HTTPResponse {
        HTTPResponse(status: 200, body: Data(text.utf8))
    }

    private let episodesJSON = """
    {"status": "success", "data": {"series": {"id": 81189}, "episodes": [
        {"id": 3, "name": "Cat's in the Bag...", "overview": "Walt and Jesse clean up.",
         "aired": "2008-01-27", "runtime": 48,
         "image": "http://artworks.thetvdb.com/banners/episodes/81189/349233.jpg",
         "number": 2, "seasonNumber": 1},
        {"id": 2, "name": "Pilot", "overview": "A teacher turns to crime.",
         "aired": "2008-01-20", "runtime": 58, "image": null, "number": 1, "seasonNumber": 1},
        {"id": 9, "name": "A special", "number": 1, "seasonNumber": 0},
        {"id": 4, "name": "", "number": 3, "seasonNumber": 1},
        {"id": "broken", "name": 5, "number": "x"}
    ]}, "links": {"next": null}}
    """

    private func makeTransport() -> FakeTransport {
        let transport = FakeTransport()
        transport.routes["/v4/login"] = ok(#"{"status": "success", "data": {"token": "tok-1"}}"#)
        transport.routes["/v4/series/81189/episodes/official"] = ok(episodesJSON)
        return transport
    }

    // MARK: Episodes

    func testEpisodesAreParsedSortedAndFilteredToTheSeason() async throws {
        let transport = makeTransport()
        let client = TVDBClient(apiKey: "tvdb-test-episodes", transport: transport)
        let episodes = try await client.episodes(seriesID: 81189, season: 1)

        XCTAssertEqual(episodes.map(\.number), [1, 2, 3])
        XCTAssertEqual(episodes[0].name, "Pilot")
        XCTAssertNil(episodes[0].imageURL)
        XCTAssertEqual(episodes[0].runtimeMinutes, 58)
        XCTAssertEqual(episodes[1].name, "Cat's in the Bag...")
        XCTAssertEqual(episodes[1].airDate, "2008-01-27")
        XCTAssertEqual(episodes[1].imageURL?.absoluteString,
                       "https://artworks.thetvdb.com/banners/episodes/81189/349233.jpg")
        XCTAssertEqual(episodes[2].name, "Episode 3")   // blank title gets a plain label

        let request = try XCTUnwrap(transport.sent.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")
        XCTAssertTrue(request.url?.query?.contains("season=1") ?? false)
    }

    func testTokenIsReusedAcrossRequests() async throws {
        let transport = makeTransport()
        let client = TVDBClient(apiKey: "tvdb-test-cache", transport: transport)
        _ = try await client.episodes(seriesID: 81189, season: 1)
        _ = try await client.episodes(seriesID: 81189, season: 1)
        let logins = transport.sent.filter { $0.url?.path == "/v4/login" }
        XCTAssertEqual(logins.count, 1)
    }

    func testLoginSendsTheKeyInTheBody() async throws {
        let transport = makeTransport()
        let client = TVDBClient(apiKey: "  tvdb-test-body  ", transport: transport)
        try await client.verify()
        let login = try XCTUnwrap(transport.sent.first)
        XCTAssertEqual(login.httpMethod, "POST")
        let body = try XCTUnwrap(login.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["apikey"], "tvdb-test-body")
    }

    func testRefusedKeyThrowsMissingKey() async {
        let transport = FakeTransport()
        transport.routes["/v4/login"] = HTTPResponse(status: 401, body: Data())
        let client = TVDBClient(apiKey: "tvdb-test-refused", transport: transport)
        do {
            try await client.verify()
            XCTFail("Expected the key to be refused")
        } catch {
            XCTAssertEqual(error as? OnlineServiceError, .missingAPIKey(service: "TheTVDB"))
        }
    }

    func testEmptyKeyThrowsWithoutCallingTheNetwork() async {
        let transport = FakeTransport()
        let client = TVDBClient(apiKey: "   ", transport: transport)
        do {
            try await client.verify()
            XCTFail("Expected a missing key error")
        } catch {
            XCTAssertEqual(error as? OnlineServiceError, .missingAPIKey(service: "TheTVDB"))
        }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testUnknownSeriesIsNotFound() async {
        let transport = makeTransport()
        let client = TVDBClient(apiKey: "tvdb-test-404", transport: transport)
        do {
            _ = try await client.episodes(seriesID: 1, season: 1)
            XCTFail("Expected not found")
        } catch {
            XCTAssertEqual(error as? OnlineServiceError, .notFound)
        }
    }

    // MARK: Lookup by IMDb ID

    func testSeriesIDFoundFromIMDbID() async throws {
        let transport = makeTransport()
        transport.routes["/v4/search/remoteid/tt0903747"] = ok("""
        {"status": "success", "data": [
            {"episode": {"id": 5}},
            {"series": {"id": 81189, "name": "Breaking Bad"}}
        ]}
        """)
        let client = TVDBClient(apiKey: "tvdb-test-lookup", transport: transport)
        let id = try await client.seriesID(imdbID: "tt0903747")
        XCTAssertEqual(id, 81189)
    }

    func testSeriesIDAcceptsNumbersSentAsText() {
        let data = Data(#"{"data": [{"series": {"id": "81189"}}]}"#.utf8)
        XCTAssertEqual(TVDBClient.parseSeriesID(data), 81189)
    }

    func testSeriesIDMissingGivesNil() {
        XCTAssertNil(TVDBClient.parseSeriesID(Data(#"{"data": []}"#.utf8)))
        XCTAssertNil(TVDBClient.parseSeriesID(Data("not json".utf8)))
    }

    // MARK: Images

    func testImageURLsAreAlwaysHTTPS() {
        XCTAssertEqual(TVDBClient.imageURL("/banners/x.jpg")?.absoluteString,
                       "https://artworks.thetvdb.com/banners/x.jpg")
        XCTAssertEqual(TVDBClient.imageURL("banners/x.jpg")?.absoluteString,
                       "https://artworks.thetvdb.com/banners/x.jpg")
        XCTAssertEqual(TVDBClient.imageURL("http://artworks.thetvdb.com/a.jpg")?.absoluteString,
                       "https://artworks.thetvdb.com/a.jpg")
        XCTAssertNil(TVDBClient.imageURL(nil))
        XCTAssertNil(TVDBClient.imageURL("  "))
    }
}
