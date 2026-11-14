// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Key checks for TMDB and OpenSubtitles, and the two kinds of TMDB key.

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

final class ServiceVerifyTests: XCTestCase {

    // MARK: TMDB

    func testLongReadAccessTokenIsSentAsBearer() async throws {
        let transport = FakeTransport()
        transport.routes["/3/configuration"] = HTTPResponse(status: 200, body: Data("{}".utf8))
        let token = "eyJhbGciOiJIUzI1NiJ9.payload-part.signature-part"
        try await TMDBClient(apiKey: token, transport: transport).verify()

        let request = try XCTUnwrap(transport.sent.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertFalse(request.url?.query?.contains("api_key") ?? false)
    }

    func testShortAPIKeyIsSentInTheURL() async throws {
        let transport = FakeTransport()
        transport.routes["/3/configuration"] = HTTPResponse(status: 200, body: Data("{}".utf8))
        let key = "0123456789abcdef0123456789abcdef"
        try await TMDBClient(apiKey: key, transport: transport).verify()

        let request = try XCTUnwrap(transport.sent.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request.url?.query?.contains("api_key=\(key)") ?? false)
    }

    func testWhichTMDBKeysCountAsBearer() {
        XCTAssertFalse(TMDBClient.usesBearer("0123456789abcdef0123456789abcdef"))
        XCTAssertTrue(TMDBClient.usesBearer("0123456789abcdef0123456789abcdeg"))   // not hex
        XCTAssertTrue(TMDBClient.usesBearer("0123456789abcdef"))                  // wrong length
        XCTAssertTrue(TMDBClient.usesBearer("test-key"))
    }

    func testKeyIsTrimmedBeforeUse() async throws {
        let transport = FakeTransport()
        transport.routes["/3/configuration"] = HTTPResponse(status: 200, body: Data("{}".utf8))
        try await TMDBClient(apiKey: "  test-key\n", transport: transport).verify()
        XCTAssertEqual(transport.sent.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testTMDBVerifyRejectsABadKey() async {
        let transport = FakeTransport()
        transport.routes["/3/configuration"] = HTTPResponse(status: 401, body: Data())
        do {
            try await TMDBClient(apiKey: "bad", transport: transport).verify()
            XCTFail("Expected TMDBError.unauthorized")
        } catch TMDBError.unauthorized {
            // correct
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: OpenSubtitles

    func testOpenSubtitlesVerifyNeedsOnlyTheAPIKey() async throws {
        let transport = FakeTransport()
        transport.routes["/api/v1/infos/formats"] = HTTPResponse(status: 200, body: Data("{}".utf8))
        let client = OpenSubtitlesClient(apiKey: "os-key", token: "stale-token", transport: transport)
        try await client.verify()

        let request = try XCTUnwrap(transport.sent.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Api-Key"), "os-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "CasaPlay v0.1.0")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testOpenSubtitlesVerifyRejectsABadKey() async {
        let transport = FakeTransport()
        transport.routes["/api/v1/infos/formats"] = HTTPResponse(status: 401, body: Data())
        let client = OpenSubtitlesClient(apiKey: "bad", transport: transport)
        do {
            try await client.verify()
            XCTFail("Expected the key to be refused")
        } catch {
            XCTAssertEqual(error as? OnlineServiceError, .missingAPIKey(service: "OpenSubtitles"))
        }
    }
}
