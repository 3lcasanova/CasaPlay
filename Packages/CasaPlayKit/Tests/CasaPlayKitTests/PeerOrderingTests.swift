// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Streams with the most peers are listed first (within the same quality).

import XCTest
@testable import CasaPlayKit

final class PeerOrderingTests: XCTestCase {
    private let movie = ContentRequest.movie(id: "tt0111161", title: "Example Film", year: 2020)

    func testPeerCountIsReadFromCommonLabels() {
        XCTAssertEqual(StreamCandidate.peerCount(in: "⚡ Absolute Cinema\n1080P 👥 4331 🇬🇧\nVisionQuest S01E08"), 4331)
        XCTAssertEqual(StreamCandidate.peerCount(in: "1080p 👤 12 💾 1.1 GB"), 12)
        XCTAssertEqual(StreamCandidate.peerCount(in: "Seeders: 1,204"), 1204)
        XCTAssertEqual(StreamCandidate.peerCount(in: "seeds 1.2k"), 1200)
        XCTAssertNil(StreamCandidate.peerCount(in: "VisionQuest S01E08 1080p WEB H264"))
        XCTAssertNil(StreamCandidate.peerCount(in: ""))
    }

    func testMostPeersComesFirstWithinTheSameQuality() async {
        let base = FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0)
        let file = "Example.Film.2020.1080p.WEB.mkv"
        var p = base
        p.results = [
            base.candidate(0, url: "https://p/0.mp4", label: "1080P 👥 131", filename: file),
            base.candidate(1, url: "https://p/1.mp4", label: "1080P 👥 4331", filename: file),
            base.candidate(2, url: "https://p/2.mp4", label: "1080P 👥 8", filename: file),
            base.candidate(3, url: "https://p/3.mp4", label: "1080P", filename: file),
        ]
        let probe = FakeProbe(answers: Dictionary(uniqueKeysWithValues: (0..<4).map { ("https://p/\($0).mp4", verified(1920, 1080)) }))
        let final = await collect(SourceAggregator(providers: [p], probe: probe).run(movie, mode: .preferUHD)).last!
        XCTAssertEqual(final.ranked.map(\.id), ["p#1", "p#0", "p#2", "p#3"])
    }

    func testBetterQualityStillBeatsMorePeers() async {
        let base = FakeProvider(providerID: "p", name: "P", role: .primary, priority: 0)
        var p = base
        p.results = [
            base.candidate(0, url: "https://p/a.mp4", label: "2160p 👥 5", filename: "Example.Film.2020.2160p.mkv"),
            base.candidate(1, url: "https://p/b.mp4", label: "1080p 👥 9000", filename: "Example.Film.2020.1080p.mkv"),
        ]
        let probe = FakeProbe(answers: [
            "https://p/a.mp4": verified(3840, 2160),
            "https://p/b.mp4": verified(1920, 1080),
        ])
        let final = await collect(SourceAggregator(providers: [p], probe: probe).run(movie, mode: .preferUHD)).last!
        XCTAssertEqual(final.ranked.map(\.id), ["p#0", "p#1"])
    }
}
