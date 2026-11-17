import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

final class NativePlaylistProviderTests: XCTestCase {
    private let url = URL(string: "https://example.com/catalog/list.m3u")!

    private func provider(_ playlist: String) -> NativePlaylistProvider {
        let web = FakeWeb()
        web.json(url.absoluteString, playlist)
        return NativePlaylistProvider(config: ServerConfig(kind: .nativePlaylist,
            name: "Native test", baseURL: url), transport: web)
    }

    func testEpisodeUsesExactIDSeasonAndEpisode() async throws {
        let source = provider("""
        #EXTM3U
        #EXTINF:-1 tvg-id="tt123" season="1" episode="2",Anime S01E02 1080p
        episode2.m3u8
        #EXTINF:-1 tvg-id="tt123" season="2" episode="2",Anime S02E02
        wrong-season.m3u8
        #EXTINF:-1 tvg-id="tt456" season="1" episode="2",Same name
        wrong-title.m3u8
        #EXTINF:-1 tvg-id="tt123",Movie
        movie.mp4
        """)
        let result = try await source.streams(for: .episode(seriesID: "tt123", title: "Anime", season: 1, episode: 2))
        XCTAssertEqual(result.count, 1)
        guard case .http(let stream, let headers) = result.first?.location else { return XCTFail("Missing HTTP stream") }
        XCTAssertEqual(stream.absoluteString, "https://example.com/catalog/episode2.m3u8")
        XCTAssertTrue(headers.isEmpty)
    }

    func testMovieDoesNotMatchEpisodeOrSimilarID() async throws {
        let source = provider("""
        #EXTM3U
        #EXTINF:-1 tvg-id="tt123" group-title="Movies, Anime",Movie, Part One
        https://media.example.com/movie.mp4
        #EXTINF:-1 tvg-id="tt1234",Other
        https://media.example.com/other.mp4
        #EXTINF:-1 tvg-id="tt123" season="1" episode="1",Episode
        https://media.example.com/episode.mp4
        """)
        let result = try await source.streams(for: .movie(id: "tt123", title: "Movie", year: nil))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.label, "Movie, Part One")
        let absent = try await source.streams(for: .movie(id: "tt999", title: "Movie", year: nil))
        XCTAssertTrue(absent.isEmpty)
    }

    func testRejectsHLSHTMLAndEmptyCatalogs() {
        for text in ["<html>Error</html>", "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts", "#EXTM3U"] {
            XCTAssertThrowsError(try NativePlaylistProvider.parse(Data(text.utf8), relativeTo: url))
        }
    }

    func testRejectsMalformedEpisodeAndUnsafeURLs() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="tt123" episode="12",Unmapped absolute episode
        https://media.example.com/12.mp4
        #EXTINF:-1 tvg-id="tt123" season="x" episode="2",Malformed
        https://media.example.com/2.mp4
        #EXTINF:-1 tvg-id="tt123",Unsafe
        file:///etc/passwd
        #EXTINF:-1 tvg-id="tt123",Credentials
        https://user:secret@media.example.com/file.mp4
        #EXTINF:-1 tvg-id="tt123",Cleartext remote
        http://media.example.com/file.mp4
        #EXTINF:-1 tvg-id="tt123" season="0" episode="1",Special
        https://media.example.com/special.mp4
        """
        let entries = try NativePlaylistProvider.parse(Data(text.utf8), relativeTo: url)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.season, 0)
    }

    func testUserInfoAndOtherSchemesAreRefusedButAQueryIsAccepted() {
        for value in ["https://user:pass@example.com/list", "ftp://example.com/list"] {
            XCTAssertThrowsError(try NativePlaylistProvider.validateURL(URL(string: value)!))
        }
        XCTAssertNoThrow(try NativePlaylistProvider.validateURL(url))
        XCTAssertNoThrow(try NativePlaylistProvider.validateURL(URL(string: "http://192.168.1.2/list.m3u")!))
        XCTAssertNoThrow(try NativePlaylistProvider.validateURL(URL(string: "https://example.com/get.php?username=a&password=b&type=m3u_plus")!))
    }

    func testTheQueryIsKeptOutOfTheSavedAddress() {
        let link = URL(string: "https://example.com/get.php?username=me&password=p%40ss&type=m3u_plus#top")!
        let parts = NativePlaylistAccess.split(link, token: "bearer")
        XCTAssertEqual(parts.address.absoluteString, "https://example.com/get.php")
        XCTAssertEqual(parts.access.query, "username=me&password=p%40ss&type=m3u_plus")
        XCTAssertEqual(parts.access.token, "bearer")

        // What goes into the Keychain reads back the same, and rebuilds the link that was entered.
        let restored = NativePlaylistAccess(stored: parts.access.stored)
        XCTAssertEqual(restored, parts.access)
        XCTAssertEqual(restored.attach(to: parts.address).absoluteString,
                       "https://example.com/get.php?username=me&password=p%40ss&type=m3u_plus")
    }

    func testAPlainStoredTokenAndALinkWithoutAQueryStillWork() {
        let plain = NativePlaylistAccess(stored: "secret")
        XCTAssertEqual(plain.token, "secret")
        XCTAssertEqual(plain.query, "")
        XCTAssertEqual(plain.attach(to: url), url)

        let parts = NativePlaylistAccess.split(url)
        XCTAssertEqual(parts.address, url)
        XCTAssertEqual(NativePlaylistAccess(stored: parts.access.stored), NativePlaylistAccess())
    }

    func testThePlaylistIsRequestedWithItsQueryAndToken() async throws {
        final class Recorder: HTTPTransport, @unchecked Sendable {
            var requested: URLRequest?
            func send(_ request: URLRequest) async throws -> HTTPResponse {
                requested = request
                return HTTPResponse(status: 200, body: Data("#EXTM3U\n#EXTINF:-1 tvg-id=\"tt123\",Movie\nhttps://cdn.example.com/movie.mp4".utf8))
            }
        }
        let web = Recorder()
        let link = URL(string: "https://example.com/get.php?username=me&password=secret")!
        let parts = NativePlaylistAccess.split(link, token: "bearer")
        let source = NativePlaylistProvider(config: ServerConfig(kind: .nativePlaylist, name: "Query playlist",
            baseURL: parts.address), token: parts.access.stored, transport: web)
        let result = try await source.streams(for: .movie(id: "tt123", title: "Movie", year: nil))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(web.requested?.url?.absoluteString, link.absoluteString)
        XCTAssertEqual(web.requested?.value(forHTTPHeaderField: "Authorization"), "Bearer bearer")
    }

    func testAuthenticationIsOnlySentToPlaylist() async throws {
        struct AuthWeb: HTTPTransport {
            func send(_ request: URLRequest) async throws -> HTTPResponse {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                return HTTPResponse(status: 200, body: Data("#EXTM3U\n#EXTINF:-1 tvg-id=\"tt123\",Movie\nhttps://cdn.example.com/movie.mp4".utf8))
            }
        }
        let source = NativePlaylistProvider(config: ServerConfig(kind: .nativePlaylist,
            name: "Private playlist", baseURL: url), token: "secret", transport: AuthWeb())
        let result = try await source.streams(for: .movie(id: "tt123", title: "Movie", year: nil))
        guard case .http(_, let headers) = result.first?.location else { return XCTFail("Missing stream") }
        XCTAssertTrue(headers.isEmpty, "Playlist credentials must not leak to a video CDN")
    }

    func testNetworkFailureIsNotReportedAsEmptySuccess() async {
        struct Unavailable: HTTPTransport {
            func send(_ request: URLRequest) async throws -> HTTPResponse { HTTPResponse(status: 403, body: Data()) }
        }
        let source = NativePlaylistProvider(config: ServerConfig(kind: .nativePlaylist,
            name: "Unavailable", baseURL: url), transport: Unavailable())
        do { try await source.verify(); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? OnlineServiceError, .badStatus(403)) }
    }
}
