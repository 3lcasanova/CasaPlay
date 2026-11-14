// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

final class CompatibilityProbeTests: XCTestCase {
    private func candidate(_ address: String) -> StreamCandidate {
        StreamCandidate(
            id: "test",
            providerID: "test",
            providerName: "Test",
            providerRole: .primary,
            providerPriority: 1,
            location: .http(URL(string: address)!, headers: [:]),
            label: "Test",
            filename: nil,
            advertised: AdvertisedQuality.parse("Test", size: nil),
            fetchedAt: Date()
        )
    }

    func testMKVIsUnplayableWithoutTheCompatibilityEngine() async {
        let state = await PlaylistProbe().probe(candidate("https://example.com/movie.mkv"))
        XCTAssertFalse(state.isPlayable)
    }

    func testMKVIsPlayableWhenTheCompatibilityEngineExists() async {
        let state = await PlaylistProbe(compatibilityPlays: true).probe(candidate("https://example.com/movie.mkv"))
        XCTAssertTrue(state.isPlayable)
    }

    func testOtherContainersFollowTheSameRule() async {
        for ext in ["avi", "webm", "wmv", "flv"] {
            let off = await PlaylistProbe().probe(candidate("https://example.com/movie.\(ext)"))
            let on = await PlaylistProbe(compatibilityPlays: true).probe(candidate("https://example.com/movie.\(ext)"))
            XCTAssertFalse(off.isPlayable, ext)
            XCTAssertTrue(on.isPlayable, ext)
        }
    }
}
