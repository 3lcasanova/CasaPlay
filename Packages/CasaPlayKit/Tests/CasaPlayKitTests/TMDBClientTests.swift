// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

final class TMDBClientTests: XCTestCase {

    private func makeClient(_ transport: FakeTransport) -> TMDBClient {
        TMDBClient(apiKey: "test-key", transport: transport)
    }

    // MARK: - searchMovies

    func testSearchMoviesDecodesResults() async throws {
        let transport = FakeTransport()
        transport.routes["/3/search/movie"] = HTTPResponse(status: 200, body: Data("""
        {
            "results": [
                {"id": 278, "title": "The Shawshank Redemption",
                 "release_date": "1994-09-23", "poster_path": "/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg",
                 "overview": "Two imprisoned men bond.", "vote_average": 8.7}
            ]
        }
        """.utf8))
        let client = makeClient(transport)
        let results = try await client.searchMovies(query: "shawshank")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, 278)
        XCTAssertEqual(results[0].title, "The Shawshank Redemption")
        XCTAssertEqual(results[0].releaseYear, 1994)
        XCTAssertEqual(results[0].poster_path, "/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg")
    }

    func testSearchMoviesEmptyResults() async throws {
        let transport = FakeTransport()
        transport.routes["/3/search/movie"] = HTTPResponse(status: 200, body: Data("""
        {"results": []}
        """.utf8))
        let results = try await makeClient(transport).searchMovies(query: "xyzzy404")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchMovies401ThrowsUnauthorized() async {
        let transport = FakeTransport()
        transport.routes["/3/search/movie"] = HTTPResponse(status: 401, body: Data())
        do {
            _ = try await makeClient(transport).searchMovies(query: "anything")
            XCTFail("Expected TMDBError.unauthorized")
        } catch TMDBError.unauthorized {
            // correct
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - searchTV

    func testSearchTVDecodesResults() async throws {
        let transport = FakeTransport()
        transport.routes["/3/search/tv"] = HTTPResponse(status: 200, body: Data("""
        {
            "results": [
                {"id": 1396, "name": "Breaking Bad",
                 "first_air_date": "2008-01-20", "poster_path": "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
                 "overview": "Chemistry teacher Walter White.", "vote_average": 9.5}
            ]
        }
        """.utf8))
        let results = try await makeClient(transport).searchTV(query: "breaking bad")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Breaking Bad")
        XCTAssertEqual(results[0].firstAirYear, 2008)
    }

    // MARK: - movieDetail

    func testMovieDetailBuildsMediaItem() async throws {
        let transport = FakeTransport()
        transport.routes["/3/movie/278"] = HTTPResponse(status: 200, body: Data("""
        {
            "id": 278,
            "title": "The Shawshank Redemption",
            "overview": "Two imprisoned men bond.",
            "release_date": "1994-09-23",
            "runtime": 142,
            "vote_average": 8.7,
            "poster_path": "/abc.jpg",
            "backdrop_path": "/backdrop.jpg",
            "genres": [{"id": 18, "name": "Drama"}],
            "external_ids": {"imdb_id": "tt0111161"},
            "credits": {
                "cast": [{"name": "Tim Robbins", "character": "Andy Dufresne"}]
            }
        }
        """.utf8))
        let client = makeClient(transport)
        let detail = try await client.movieDetail(id: 278)
        XCTAssertEqual(detail.external_ids?.imdb_id, "tt0111161")
        XCTAssertEqual(detail.runtime, 142)

        let item = client.toMediaItem(detail)
        XCTAssertEqual(item.title, "The Shawshank Redemption")
        XCTAssertEqual(item.year, 1994)
        XCTAssertEqual(item.imdbID, "tt0111161")
        XCTAssertEqual(item.runtimeSeconds, 142 * 60)
        XCTAssertEqual(item.posterPath, "/abc.jpg")
        XCTAssertEqual(item.backdropPath, "/backdrop.jpg")
        XCTAssertEqual(item.genres, ["Drama"])
        XCTAssertEqual(item.cast.first?.name, "Tim Robbins")
        XCTAssertEqual(item.cast.first?.role, "Andy Dufresne")
    }

    // MARK: - showDetail

    func testShowDetailBuildsMediaItem() async throws {
        let transport = FakeTransport()
        transport.routes["/3/tv/1396"] = HTTPResponse(status: 200, body: Data("""
        {
            "id": 1396,
            "name": "Breaking Bad",
            "overview": "Chemistry teacher.",
            "first_air_date": "2008-01-20",
            "vote_average": 9.5,
            "poster_path": "/show.jpg",
            "backdrop_path": "/backdrop.jpg",
            "genres": [{"id": 18, "name": "Drama"}, {"id": 80, "name": "Crime"}],
            "external_ids": {"imdb_id": "tt0903747"},
            "credits": {"cast": []}
        }
        """.utf8))
        let client = makeClient(transport)
        let detail = try await client.showDetail(id: 1396)
        let item = client.toMediaItem(detail)
        XCTAssertEqual(item.title, "Breaking Bad")
        XCTAssertEqual(item.year, 2008)
        XCTAssertEqual(item.imdbID, "tt0903747")
        XCTAssertEqual(item.posterPath, "/show.jpg")
        XCTAssertEqual(item.genres, ["Drama", "Crime"])
    }

    // MARK: - Image URLs

    func testPosterURLBuildsCorrectly() {
        let url = TMDBClient.posterURL("/abc123.jpg")
        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w500/abc123.jpg")
    }

    func testBackdropURLBuildsCorrectly() {
        let url = TMDBClient.backdropURL("/wide.jpg")
        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w1280/wide.jpg")
    }

    // MARK: - Auth header

    func testBearerHeaderIsSentOnSearch() async throws {
        let transport = FakeTransport()
        transport.routes["/3/search/movie"] = HTTPResponse(status: 200, body: Data("""
        {"results": []}
        """.utf8))
        _ = try await makeClient(transport).searchMovies(query: "test")
        XCTAssertEqual(transport.sent.first?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer test-key")
    }
}
