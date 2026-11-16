// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

final class TrailerTests: XCTestCase {

    // MARK: - YouTube links

    func testVideoIDIsReadFromTheUsualLinkShapes() {
        let id = "dQw4w9WgXcQ"
        for text in [
            "https://www.youtube.com/watch?v=\(id)",
            "https://youtube.com/watch?feature=share&v=\(id)&t=10",
            "https://m.youtube.com/watch?v=\(id)",
            "https://youtu.be/\(id)?si=abc",
            "https://www.youtube.com/embed/\(id)",
            "https://www.youtube-nocookie.com/embed/\(id)",
            "https://www.youtube.com/shorts/\(id)",
        ] {
            XCTAssertEqual(YouTubeLink.videoID(from: URL(string: text)!), id, text)
        }
    }

    func testOtherLinksAndBadIDsAreRefused() {
        for text in [
            "https://vimeo.com/123456789",
            "https://www.youtube.com/watch?v=short",
            "https://www.youtube.com/watch?v=dQw4w9WgXc%22",
            "https://www.youtube.com/channel/UCabcdefghijk",
            "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
            "youtube://watch?v=dQw4w9WgXcQ",
        ] {
            XCTAssertNil(YouTubeLink.videoID(from: URL(string: text)!), text)
        }
        XCTAssertNil(Trailer(youTubeID: "dQw4w9WgXc\""))
        XCTAssertNil(Trailer(youTubeID: "tooShort"))
    }

    // MARK: - Cinemeta

    func testCinemetaTrailersAreReadFromBothLists() async throws {
        let transport = FakeTransport()
        transport.routes["/meta/movie/tt0111161.json"] = HTTPResponse(status: 200, body: Data("""
        {"meta": {
          "trailers": [{"source": "trailer0001", "type": "Trailer"}, {"source": "clip0000001", "type": "Clip"}],
          "trailerStreams": [{"title": "Main", "ytId": "trailer0001"}, {"title": "Second", "ytId": "trailer0002"}]
        }}
        """.utf8))
        let trailers = try await CinemetaTrailers(transport: transport).trailers(imdbID: "tt0111161", isSeries: false)
        XCTAssertEqual(trailers.map(\.youTubeID), ["trailer0001", "trailer0002"])
    }

    func testCinemetaAsksForSeriesAndRefusesABadID() async throws {
        let transport = FakeTransport()
        transport.routes["/meta/series/tt0903747.json"] = HTTPResponse(status: 200, body: Data(#"{"meta": {}}"#.utf8))
        let client = CinemetaTrailers(transport: transport)
        let none = try await client.trailers(imdbID: "tt0903747", isSeries: true)
        XCTAssertTrue(none.isEmpty)
        let refused = try await client.trailers(imdbID: "../etc", isSeries: false)
        XCTAssertTrue(refused.isEmpty)
        XCTAssertEqual(transport.sent.count, 1)
    }
}
