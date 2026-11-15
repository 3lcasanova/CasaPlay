import XCTest
@testable import CasaPlayKit

final class StreamPickTests: XCTestCase {
    private func candidate(_ provider: String = "comet", url: String, label: String = "4K HDR\n👥 120",
                           filename: String? = nil) -> StreamCandidate {
        StreamCandidate(id: "\(provider)#0", providerID: provider, providerName: provider, providerRole: .primary,
                        providerPriority: 0, location: .http(URL(string: url)!, headers: [:]), label: label,
                        filename: filename, advertised: AdvertisedQuality(), fetchedAt: Date())
    }

    func testTheSameLinkIsFoundAgainEvenWhenItsTokenChanges() throws {
        let saved = candidate(url: "https://host.example/play/abc/movie.mkv?token=one")
        let pick = try XCTUnwrap(StreamPick(key: "tt1", candidate: saved))
        let fresh = candidate(url: "https://host.example/play/abc/movie.mkv?token=two")
        XCTAssertEqual(pick.score(fresh), 3)
    }

    func testTheLinkItselfIsNeverKept() throws {
        let saved = candidate(url: "https://host.example/secret-config/movie.mkv?token=hunter2")
        let pick = try XCTUnwrap(StreamPick(key: "tt1", candidate: saved))
        let data = try JSONEncoder().encode(pick)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("hunter2"))
        XCTAssertFalse(text.contains("secret-config"))
        XCTAssertFalse(text.contains("host.example"))
    }

    func testAFileNameFindsTheStreamWhenTheLinkChanged() throws {
        let pick = try XCTUnwrap(StreamPick(key: "tt1", candidate: candidate(url: "https://a.example/1", filename: "Film.2160p.mkv")))
        XCTAssertEqual(pick.score(candidate(url: "https://a.example/2", filename: "Film.2160p.mkv")), 2)
    }

    func testTheSeederCountDoesNotStopTheLabelMatching() throws {
        let pick = try XCTUnwrap(StreamPick(key: "tt1", candidate: candidate(url: "https://a.example/1", label: "4K HDR Atmos\n👥 120")))
        XCTAssertEqual(pick.score(candidate(url: "https://a.example/2", label: "4K HDR Atmos\n👥 4,331")), 1)
    }

    func testAnotherAddonOrAnotherStreamIsNotAMatch() throws {
        let pick = try XCTUnwrap(StreamPick(key: "tt1", candidate: candidate(url: "https://a.example/1", label: "4K HDR")))
        XCTAssertEqual(pick.score(candidate("other", url: "https://a.example/1", label: "4K HDR")), 0)
        XCTAssertEqual(pick.score(candidate(url: "https://a.example/9", label: "1080p")), 0)
    }

    func testTheSurestMatchWinsAndATieGoesToTheBestRanked() throws {
        let pick = try XCTUnwrap(StreamPick(key: "tt1", candidate: candidate(url: "https://a.example/exact", label: "4K HDR")))
        let weak = candidate(url: "https://a.example/other", label: "4K HDR")
        let exact = candidate(url: "https://a.example/exact", label: "different words")
        XCTAssertEqual(pick.bestMatch(in: [weak, exact])?.location, exact.location)
        let first = candidate(url: "https://a.example/one", label: "4K HDR")
        let second = candidate(url: "https://a.example/two", label: "4K HDR")
        XCTAssertEqual(pick.bestMatch(in: [first, second])?.location, first.location)
    }

    func testATorrentCannotBeStartedByItself() {
        let torrent = StreamCandidate(id: "t#0", providerID: "t", providerName: "T", providerRole: .backup, providerPriority: 0,
                                      location: .torrentFile(URL(string: "https://a.example/f.torrent")!), label: "x",
                                      filename: nil, advertised: AdvertisedQuality(), fetchedAt: Date())
        XCTAssertNil(StreamPick(key: "tt1", candidate: torrent))
    }
}
