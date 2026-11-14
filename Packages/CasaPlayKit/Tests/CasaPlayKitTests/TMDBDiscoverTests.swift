// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

final class TMDBDiscoverTests: XCTestCase {
    private func makeClient(_ transport: FakeTransport) -> TMDBClient {
        TMDBClient(apiKey: "test-key", transport: transport)
    }

    private func query(_ request: URLRequest?) -> [String: String] {
        let items = URLComponents(url: request?.url ?? URL(string: "https://x")!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    func testDiscoverMoviesAsksForGenreLanguageAndPopularity() async throws {
        let transport = FakeTransport()
        transport.routes["/3/discover/movie"] = HTTPResponse(status: 200, body: Data("""
        {"results": [{"id": 1, "title": "Film A", "release_date": "2025-04-01"}, {"id": 2, "title": "Film B"}]}
        """.utf8))
        let films = try await makeClient(transport).discoverMovies(genre: 16, language: "ja", fromYear: 2020, page: 2)
        XCTAssertEqual(films.map(\.title), ["Film A", "Film B"])

        let sent = query(transport.sent.first)
        XCTAssertEqual(sent["with_genres"], "16")
        XCTAssertEqual(sent["with_original_language"], "ja")
        XCTAssertEqual(sent["page"], "2")
        XCTAssertEqual(sent["sort_by"], "popularity.desc")
        XCTAssertEqual(sent["include_adult"], "false")
        XCTAssertEqual(sent["vote_count.gte"], "100")
        XCTAssertEqual(sent["primary_release_date.gte"], "2020-01-01")
    }

    func testTopRatedListNeedsManyMoreVotes() async throws {
        let transport = FakeTransport()
        transport.routes["/3/discover/movie"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":1,"title":"A"}]}"#.utf8))
        _ = try await makeClient(transport).discoverMovies(fromYear: 2020, sort: .rating)
        let sent = query(transport.sent.first)
        XCTAssertEqual(sent["sort_by"], "vote_average.desc")
        XCTAssertEqual(sent["vote_count.gte"], "500")
    }

    func testShowsUseTheFirstAirDateForTheYear() async throws {
        let transport = FakeTransport()
        transport.routes["/3/discover/tv"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":2,"name":"B"}]}"#.utf8))
        _ = try await makeClient(transport).discoverTV(fromYear: 2020)
        let sent = query(transport.sent.first)
        XCTAssertEqual(sent["first_air_date.gte"], "2020-01-01")
        XCTAssertNil(sent["primary_release_date.gte"])
    }

    func testDiscoverTVLeavesOutGenreAndLanguageWhenNotGiven() async throws {
        let transport = FakeTransport()
        transport.routes["/3/discover/tv"] = HTTPResponse(status: 200, body: Data("""
        {"results": [{"id": 9, "name": "Show A", "first_air_date": "2023-01-01"}]}
        """.utf8))
        let shows = try await makeClient(transport).discoverTV()
        XCTAssertEqual(shows.first?.firstAirYear, 2023)

        let sent = query(transport.sent.first)
        XCTAssertNil(sent["with_genres"])
        XCTAssertNil(sent["with_original_language"])
        XCTAssertNil(sent["first_air_date.gte"])
        XCTAssertEqual(sent["page"], "1")
        XCTAssertEqual(sent["vote_count.gte"], "50")
    }

    func testPageNumberNeverGoesBelowOne() {
        let low = TMDBClient.discoverParams(genre: nil, language: nil, fromYear: nil, sort: .popularity,
                                            page: 0, minVotes: 10, dateKey: "d")
        XCTAssertEqual(low["page"], "1")
        let empty = TMDBClient.discoverParams(genre: nil, language: "", fromYear: nil, sort: .popularity,
                                              page: -4, minVotes: 10, dateKey: "d")
        XCTAssertNil(empty["with_original_language"])
        XCTAssertNil(empty["d"])
    }

    func testNowPlayingAndUpcomingUseTheRegion() async throws {
        let transport = FakeTransport()
        transport.routes["/3/movie/now_playing"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":5,"title":"Now"}]}"#.utf8))
        transport.routes["/3/movie/upcoming"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":6,"title":"Soon"}]}"#.utf8))
        let client = makeClient(transport)
        let now = try await client.nowPlayingMovies(region: "ca")
        let soon = try await client.upcomingMovies()
        XCTAssertEqual(now.first?.title, "Now")
        XCTAssertEqual(soon.first?.title, "Soon")
        XCTAssertEqual(query(transport.sent.first)["region"], "CA")
        XCTAssertNil(query(transport.sent.last)["region"])
    }

    func testRegionMustBeATwoLetterCode() {
        XCTAssertEqual(TMDBClient.regionParams("CA"), ["region": "CA"])
        XCTAssertEqual(TMDBClient.regionParams(" fr "), ["region": "FR"])
        XCTAssertTrue(TMDBClient.regionParams("Canada").isEmpty)
        XCTAssertTrue(TMDBClient.regionParams(nil).isEmpty)
    }

    func testAiringTodayAndOnTheAir() async throws {
        let transport = FakeTransport()
        transport.routes["/3/tv/airing_today"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":20,"name":"Tonight"}]}"#.utf8))
        transport.routes["/3/tv/on_the_air"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":21,"name":"This Week"}]}"#.utf8))
        let client = makeClient(transport)
        let today = try await client.airingTodayTV()
        let week = try await client.onTheAirTV()
        XCTAssertEqual(today.first?.name, "Tonight")
        XCTAssertEqual(week.first?.name, "This Week")
    }
}

final class TMDBBrowseTests: XCTestCase {
    private func query(_ request: URLRequest?) -> [String: String] {
        let items = URLComponents(url: request?.url ?? URL(string: "https://x")!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    func testListsCanBePaged() async throws {
        let transport = FakeTransport()
        transport.routes["/3/movie/now_playing"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":1,"title":"A"}]}"#.utf8))
        transport.routes["/3/tv/airing_today"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":2,"name":"B"}]}"#.utf8))
        transport.routes["/3/trending/movie/week"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":3,"title":"C"}]}"#.utf8))
        let client = TMDBClient(apiKey: "test-key", transport: transport)
        _ = try await client.nowPlayingMovies(region: "CA", page: 3)
        _ = try await client.airingTodayTV(page: 2)
        _ = try await client.trendingMovies(page: 0)
        XCTAssertEqual(query(transport.sent[0])["page"], "3")
        XCTAssertEqual(query(transport.sent[0])["region"], "CA")
        XCTAssertEqual(query(transport.sent[1])["page"], "2")
        XCTAssertEqual(query(transport.sent[2])["page"], "1")
    }

    func testStreamingServiceRowsAskForSubscriptionTitlesInTheRegion() async throws {
        let transport = FakeTransport()
        transport.routes["/3/discover/tv"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":9,"name":"Show"}]}"#.utf8))
        let client = TMDBClient(apiKey: "test-key", transport: transport)
        _ = try await client.discoverTV(fromYear: 2020, provider: 8, watchRegion: "ca")
        let sent = query(transport.sent.first)
        XCTAssertEqual(sent["with_watch_providers"], "8")
        XCTAssertEqual(sent["watch_region"], "CA")
        XCTAssertEqual(sent["with_watch_monetization_types"], "flatrate")
    }

    func testRelatedTitlesComeFromTheRecommendationsLists() async throws {
        let transport = FakeTransport()
        transport.routes["/3/movie/603/recommendations"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":1,"title":"A"}]}"#.utf8))
        transport.routes["/3/tv/1396/recommendations"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":2,"name":"B"}]}"#.utf8))
        let client = TMDBClient(apiKey: "test-key", transport: transport)
        let films = try await client.recommendedMovies(id: 603)
        let shows = try await client.recommendedTV(id: 1396)
        XCTAssertEqual(films.first?.title, "A")
        XCTAssertEqual(shows.first?.name, "B")
        XCTAssertEqual(transport.sent.count, 2)
    }

    func testPosterURLCanAskForABigWidth() {
        XCTAssertEqual(TMDBClient.posterURL("/a.jpg", width: 780)?.absoluteString, "https://image.tmdb.org/t/p/w780/a.jpg")
        XCTAssertEqual(TMDBClient.posterURL("/a.jpg")?.absoluteString, "https://image.tmdb.org/t/p/w500/a.jpg")
    }

    func testTitleLogoPrefersTheBestEnglishPictureAndSkipsSVG() async throws {
        let transport = FakeTransport()
        transport.routes["/3/movie/5/images"] = HTTPResponse(status: 200, body: Data("""
        {"logos": [
          {"file_path": "/fr.png", "iso_639_1": "fr", "vote_average": 9},
          {"file_path": "/en-low.png", "iso_639_1": "en", "vote_average": 1},
          {"file_path": "/en-best.png", "iso_639_1": "en", "vote_average": 5},
          {"file_path": "/en.svg", "iso_639_1": "en", "vote_average": 9}
        ]}
        """.utf8))
        let path = try await TMDBClient(apiKey: "test-key", transport: transport).titleLogoPath(movieID: 5)
        XCTAssertEqual(path, "/en-best.png")
        XCTAssertEqual(query(transport.sent.first)["include_image_language"], "en,null")
    }

    func testTitleLogoFallsBackToOneWithNoLanguageThenToNothing() async throws {
        let transport = FakeTransport()
        transport.routes["/3/tv/8/images"] = HTTPResponse(status: 200, body: Data("""
        {"logos": [{"file_path": "/de.png", "iso_639_1": "de"}, {"file_path": "/none.png", "iso_639_1": null}]}
        """.utf8))
        XCTAssertEqual(try await TMDBClient(apiKey: "test-key", transport: transport).titleLogoPath(showID: 8), "/none.png")

        transport.routes["/3/tv/9/images"] = HTTPResponse(status: 200, body: Data(#"{"logos": []}"#.utf8))
        let none = try await TMDBClient(apiKey: "test-key", transport: transport).titleLogoPath(showID: 9)
        XCTAssertNil(none)
        XCTAssertEqual(TMDBClient.logoURL("/x.png")?.absoluteString, "https://image.tmdb.org/t/p/w500/x.png")
    }

    func testOriginalBackdropURLUsesTheFullSize() {
        XCTAssertEqual(TMDBClient.originalBackdropURL("/b.jpg")?.absoluteString, "https://image.tmdb.org/t/p/original/b.jpg")
        XCTAssertEqual(TMDBClient.backdropURL("/b.jpg")?.absoluteString, "https://image.tmdb.org/t/p/w1280/b.jpg")
    }

    func testNoProviderMeansNoWatchFilters() async throws {
        let transport = FakeTransport()
        transport.routes["/3/discover/movie"] = HTTPResponse(status: 200, body: Data(#"{"results":[{"id":1,"title":"A"}]}"#.utf8))
        let client = TMDBClient(apiKey: "test-key", transport: transport)
        _ = try await client.discoverMovies(fromYear: 2020)
        let sent = query(transport.sent.first)
        XCTAssertNil(sent["with_watch_providers"])
        XCTAssertNil(sent["watch_region"])
    }

    func testShowAirInfoReadsTheLatestAndNextEpisode() async throws {
        let transport = FakeTransport()
        transport.routes["/3/tv/77"] = HTTPResponse(status: 200, body: Data("""
        {"id": 77, "status": "Returning Series",
         "last_episode_to_air": {"season_number": 1, "episode_number": 3, "air_date": "2026-11-07"},
         "next_episode_to_air": {"season_number": 1, "episode_number": 4, "air_date": "2026-11-14"}}
        """.utf8))
        let info = try await TMDBClient(apiKey: "test-key", transport: transport).showAirInfo(id: 77)
        XCTAssertEqual(info.last_episode_to_air?.label, "S01 E03")
        XCTAssertEqual(info.next_episode_to_air?.label, "S01 E04")
        XCTAssertEqual(info.status, "Returning Series")
    }

    func testShowAirInfoToleratesMissingEpisodes() async throws {
        let transport = FakeTransport()
        transport.routes["/3/tv/78"] = HTTPResponse(status: 200, body: Data(#"{"id": 78, "last_episode_to_air": null}"#.utf8))
        let info = try await TMDBClient(apiKey: "test-key", transport: transport).showAirInfo(id: 78)
        XCTAssertNil(info.last_episode_to_air)
        XCTAssertNil(info.next_episode_to_air)
    }
}
