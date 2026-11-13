// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

/// Answers requests from a table keyed by URL path and records what was sent.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var routes: [String: HTTPResponse] = [:]
    private(set) var sent: [URLRequest] = []
    private let lock = NSLock()

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.withLock { sent.append(request) }
        let path = request.url?.path ?? ""
        return routes[path] ?? HTTPResponse(status: 404, body: Data())
    }
}

private func json(_ text: String) -> Data { Data(text.utf8) }

final class IMDbTests: XCTestCase {
    func testIDValidationAndExtraction() {
        XCTAssertTrue(IMDb.isValidID("tt1234567"))
        XCTAssertTrue(IMDb.isValidID("tt12345678"))
        XCTAssertFalse(IMDb.isValidID("1234567"))
        XCTAssertFalse(IMDb.isValidID("tt123"))
        XCTAssertEqual(IMDb.extractID(from: "Night Ferry (2025) {imdb-tt1234567}"), "tt1234567")
        XCTAssertEqual(IMDb.extractID(from: "https://www.imdb.com/title/tt0111161/"), "tt0111161")
        XCTAssertNil(IMDb.extractID(from: "Night.Ferry.2025.2160p.mkv"))
    }

    func testLinksAndFormatting() {
        XCTAssertEqual(IMDb.titleURL("tt0111161")?.absoluteString, "https://www.imdb.com/title/tt0111161/")
        XCTAssertNil(IMDb.titleURL("nope"))
        XCTAssertEqual(IMDb.ratingText(7.0), "7.0")
        XCTAssertEqual(IMDb.votesText(950), "950")
        XCTAssertEqual(IMDb.votesText(128_456), "128K")
        XCTAssertEqual(IMDb.votesText(2_950_000), "3.0M")
    }

    func testFilenameParserReadsAndRemovesIMDbID() {
        let parsed = FilenameParser.parse("Night Ferry (2025) {imdb-tt1234567}.mkv")
        XCTAssertEqual(parsed.title, "Night Ferry")
        XCTAssertEqual(parsed.year, 2025)
        XCTAssertEqual(parsed.imdbID, "tt1234567")

        let dotted = FilenameParser.parse("Night.Ferry.2025.tt1234567.2160p.mkv")
        XCTAssertEqual(dotted.title, "Night Ferry")
        XCTAssertEqual(dotted.imdbID, "tt1234567")
    }

    func testMediaItemIMDbURL() {
        var item = SampleData.movies[0]
        XCTAssertNil(item.imdbURL)
        item.imdbID = "tt0111161"
        XCTAssertEqual(item.imdbURL?.absoluteString, "https://www.imdb.com/title/tt0111161/")
    }

    func testOMDbParsesRating() async throws {
        let transport = FakeTransport()
        transport.routes["/"] = HTTPResponse(status: 200, body: json("""
        {"Title":"Example","imdbID":"tt0111161","imdbRating":"9.3","imdbVotes":"2,950,123","Response":"True"}
        """))
        let client = OMDbClient(apiKey: "KEY", transport: transport)
        let result = try await client.rating(imdbID: "tt0111161")
        XCTAssertEqual(result, IMDbRating(imdbID: "tt0111161", rating: 9.3, votes: 2_950_123))

        let query = transport.sent.first?.url?.query ?? ""
        XCTAssertTrue(query.contains("i=tt0111161"))
        XCTAssertTrue(query.contains("apikey=KEY"))
    }

    func testOMDbNotFoundAndNA() async throws {
        let transport = FakeTransport()
        transport.routes["/"] = HTTPResponse(status: 200, body: json(#"{"Response":"False","Error":"Movie not found!"}"#))
        let client = OMDbClient(apiKey: "KEY", transport: transport)
        do {
            _ = try await client.rating(title: "Nothing", year: 2025)
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? OnlineServiceError, .notFound)
        }

        transport.routes["/"] = HTTPResponse(status: 200, body: json(#"{"imdbID":"tt7654321","imdbRating":"N/A","imdbVotes":"N/A","Response":"True"}"#))
        let unrated = try await client.rating(imdbID: "tt7654321")
        XCTAssertNil(unrated.rating)
        XCTAssertNil(unrated.votes)
    }

    func testOMDbNeedsKey() async {
        let client = OMDbClient(apiKey: "  ", transport: FakeTransport())
        do {
            _ = try await client.rating(imdbID: "tt0111161")
            XCTFail("expected missing key")
        } catch {
            XCTAssertEqual(error as? OnlineServiceError, .missingAPIKey(service: "OMDb"))
        }
    }
}

final class OpenSubtitlesTests: XCTestCase {
    private let searchJSON = """
    {"total_count":4,"data":[
      {"id":"1","attributes":{"language":"fr","release":"Example.FR","download_count":900,"from_trusted":true,
        "files":[{"file_id":11,"file_name":"fr.srt"}]}},
      {"id":"2","attributes":{"language":"en","release":"Example.MT","download_count":99999,"machine_translated":true,
        "files":[{"file_id":22,"file_name":"en-mt.srt"}]}},
      {"id":"3","attributes":{"language":"en","release":"Example.2160p.WEB","download_count":5000,"hearing_impaired":true,
        "files":[{"file_id":33,"file_name":"en-sdh.srt"}]}},
      {"id":"4","attributes":{"language":"en","release":"Example.1080p","download_count":8000,
        "files":[{"file_id":44,"file_name":"en.srt"}]}},
      {"id":"5","attributes":{"language":"en","release":"No files"}}
    ]}
    """

    func testSearchRequestShape() throws {
        let client = OpenSubtitlesClient(apiKey: "KEY", token: "TOKEN")
        let request = try client.searchRequest(.imdb("tt0111161"), languages: ["fr", "en"])
        XCTAssertEqual(request.url?.path, "/api/v1/subtitles")
        XCTAssertEqual(request.url?.query, "imdb_id=111161&languages=en,fr")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Api-Key"), "KEY")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer TOKEN")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))

        let byTitle = try client.searchRequest(.title("Night Ferry", year: 2025), languages: ["en"])
        XCTAssertEqual(byTitle.url?.query, "languages=en&query=night%20ferry&year=2025")
    }

    func testSearchParsesAndRanks() async throws {
        let transport = FakeTransport()
        transport.routes["/api/v1/subtitles"] = HTTPResponse(status: 200, body: json(searchJSON))
        let client = OpenSubtitlesClient(apiKey: "KEY", transport: transport)
        let results = try await client.search(.imdb("tt0111161"), languages: ["en", "fr"])

        // English first (preferred), human-made before machine-translated, then most downloaded; French last.
        XCTAssertEqual(results.map(\.fileID), [44, 33, 22, 11])
        XCTAssertTrue(results[1].isSDH)
        XCTAssertTrue(results[2].isMachineTranslated)
        XCTAssertEqual(results[1].track.origin, .online)
        XCTAssertEqual(results[1].track.id, "os-33")
        XCTAssertTrue(results[1].track.isSDH)
    }

    func testDownloadFetchesAndParses() async throws {
        let transport = FakeTransport()
        transport.routes["/api/v1/download"] = HTTPResponse(status: 200, body: json(
            #"{"link":"https://dl.example.com/files/abc.srt","remaining":4}"#
        ))
        transport.routes["/files/abc.srt"] = HTTPResponse(status: 200, body: json("""
        1
        00:00:01,000 --> 00:00:02,000
        Hello.
        """))
        let client = OpenSubtitlesClient(apiKey: "KEY", transport: transport)
        let cues = try await client.download(OnlineSubtitle(fileID: 44, languageCode: "en", release: "x"))
        XCTAssertEqual(cues, [SubtitleCue(start: 1, end: 2, text: "Hello.")])

        let post = transport.sent[0]
        XCTAssertEqual(post.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: post.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["file_id"] as? Int, 44)
    }

    func testQuotaMessageIsPassedOn() async {
        let transport = FakeTransport()
        transport.routes["/api/v1/download"] = HTTPResponse(status: 406, body: json(
            #"{"message":"You have downloaded your allowed 5 subtitles for 24h."}"#
        ))
        let client = OpenSubtitlesClient(apiKey: "KEY", transport: transport)
        do {
            _ = try await client.download(OnlineSubtitle(fileID: 1, languageCode: "en", release: "x"))
            XCTFail("expected quota error")
        } catch {
            XCTAssertEqual(
                error as? OnlineServiceError,
                .quotaReached(message: "You have downloaded your allowed 5 subtitles for 24h.")
            )
        }
    }

    func testMissingKey() {
        let client = OpenSubtitlesClient(apiKey: "")
        XCTAssertThrowsError(try client.searchRequest(.imdb("tt0111161"), languages: ["en"])) { error in
            XCTAssertEqual(error as? OnlineServiceError, .missingAPIKey(service: "OpenSubtitles"))
        }
    }
}

final class SubtitleFileTests: XCTestCase {
    func testSidecarMatching() {
        let siblings = [
            "Night.Ferry.2025.2160p.mkv",
            "Night.Ferry.2025.2160p.srt",
            "Night.Ferry.2025.2160p.en.srt",
            "Night.Ferry.2025.2160p.en.sdh.srt",
            "Night.Ferry.2025.2160p.fr.forced.srt",
            "Night.Ferry.2025.2160p.pt-BR.vtt",
            "Night.Ferry.2025.2160p.French.ass",
            "Night.Ferry.2025.2160p.nfo",
            "Night.Ferry.2025.2160p-sample.srt",
            "Other.Movie.en.srt"
        ]
        let found = SidecarSubtitles.match(videoFileName: "Night.Ferry.2025.2160p.mkv", siblings: siblings)
        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.fileName, $0.track) })

        XCTAssertEqual(found.count, 6)
        XCTAssertEqual(byName["Night.Ferry.2025.2160p.srt"]?.languageCode, "und")
        XCTAssertEqual(byName["Night.Ferry.2025.2160p.en.srt"]?.languageCode, "en")
        XCTAssertEqual(byName["Night.Ferry.2025.2160p.en.sdh.srt"]?.isSDH, true)
        XCTAssertEqual(byName["Night.Ferry.2025.2160p.fr.forced.srt"]?.isForced, true)
        XCTAssertEqual(byName["Night.Ferry.2025.2160p.pt-BR.vtt"]?.languageCode, "pt-br")
        XCTAssertEqual(byName["Night.Ferry.2025.2160p.pt-BR.vtt"]?.format, .vtt)
        XCTAssertEqual(byName["Night.Ferry.2025.2160p.French.ass"]?.languageCode, "fr")
        XCTAssertEqual(byName["Night.Ferry.2025.2160p.French.ass"]?.format, .ass)
        XCTAssertNil(byName["Night.Ferry.2025.2160p-sample.srt"])
        XCTAssertTrue(found.allSatisfy { $0.track.origin == .sidecar })
    }

    func testSidecarTracksWorkWithSelector() {
        let found = SidecarSubtitles.match(
            videoFileName: "Movie.mkv",
            siblings: ["Movie.fr.srt", "Movie.en.srt", "Movie.en.forced.srt"]
        ).map(\.track)
        let pick = SubtitleSelector.defaultTrack(from: found, preferredLanguages: ["fr", "en"], audioLanguage: "en")
        XCTAssertEqual(pick?.languageCode, "fr")
        let forced = SubtitleSelector.defaultTrack(from: found, preferredLanguages: ["en"], audioLanguage: "en")
        XCTAssertEqual(forced?.isForced, true)
    }

    func testLoaderHandlesEncodingsAndFormats() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nCafé crème\n"
        XCTAssertEqual(SubtitleLoader.cues(from: Data(srt.utf8)).first?.text, "Café crème")

        // "Café crème" in Windows-1252: é = 0xE9, è = 0xE8.
        var latin = Data("1\n00:00:01,000 --> 00:00:02,000\nCaf".utf8)
        latin.append(contentsOf: [0xE9, 0x20, 0x63, 0x72, 0xE8, 0x6D, 0x65, 0x0A])
        XCTAssertEqual(SubtitleLoader.cues(from: latin, format: .srt).first?.text, "Café crème")

        let vtt = "WEBVTT\n\n00:01.000 --> 00:02.000\nBonjour\n"
        XCTAssertEqual(SubtitleLoader.guessFormat(vtt), .vtt)
        // A WebVTT file mislabelled as SRT still parses.
        XCTAssertEqual(SubtitleLoader.cues(from: Data(vtt.utf8), format: .other).first?.text, "Bonjour")
    }

    func testDemoSubtitlesParse() {
        let cues = SRTParser.parse(SampleData.demoSubtitleSRT)
        XCTAssertEqual(cues.count, 6)
        XCTAssertEqual(cues[2].text, "Forty strangers. One way across.")
    }

    func testSampleLibraryHasIMDbRatings() {
        XCTAssertTrue(SampleData.movies.allSatisfy { $0.imdbRating != nil })
        XCTAssertTrue(SampleData.movies.allSatisfy { $0.imdbID == nil }, "sample titles are invented, so no IMDb pages")
    }
}
