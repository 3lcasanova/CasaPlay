// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Live checks with official, openly available services. Off by default.
//   CASAPLAY_LIVE_EXTENSIONS=1 swift test --filter LiveExtensionTests

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

final class LiveExtensionTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CASAPLAY_LIVE_EXTENSIONS"] == "1", "live network test")
    }

    func testCinemetaCatalogAndSeriesEpisodes() async throws {
        let m = ExtensionManager(file: tempRoot().appendingPathComponent("e.json"), transport: liveTransport, secrets: MemorySecretStore())
        let addon = try await m.install(manifestURL: URL(string: "https://v3-cinemeta.strem.io/manifest.json")!)
        print("LIVE Cinemeta \(addon.version) capabilities \(addon.capabilities.map(\.rawValue))")
        let clientOpt = await m.client(for: addon)
        let client = try XCTUnwrap(clientOpt)
        let top = try await client.catalog(type: "movie", id: "top")
        print("LIVE catalog: \(top.count) titles, first \(top.first?.name ?? "-")")
        XCTAssertFalse(top.isEmpty)
        let meta = try await client.meta(type: "series", id: "tt0944947")
        let episodes = meta.videos ?? []
        print("LIVE series \(meta.name): \(episodes.count) episodes")
        XCTAssertTrue(episodes.contains { $0.season == 1 && $0.episode == 2 && $0.id == "tt0944947:1:2" })
    }

    func testOpenSubtitlesAddon() async throws {
        let client = try StremioClient(manifestURL: URL(string: "https://opensubtitles-v3.strem.io/manifest.json")!, transport: liveTransport)
        let manifest = try await client.manifest()
        XCTAssertEqual(manifest.capabilities, [.subtitles])
        let subs = try await client.subtitles(type: "movie", id: "tt0111161")
        print("LIVE OpenSubtitles: \(subs.count) subtitles, languages \(Set(subs.map(\.lang)).sorted().prefix(8))")
        XCTAssertFalse(subs.isEmpty)
    }

    func testAppleHLSExamplePlaylist() async throws {
        let p = FakeProvider(providerID: "apple", name: "Apple example", role: .primary, priority: 0)
        let c = p.candidate(0, url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8", label: "")
        let state = await PlaylistProbe(transport: liveTransport).probe(c)
        let q = try XCTUnwrap(state.verified, "\(state)")
        print("LIVE Apple HEVC example: best \(q.width)×\(q.height) \(q.codec ?? "?") \(q.dynamicRange?.rawValue ?? "?") variants \(q.variants.map { "\($0.width)x\($0.height)" })")
        XCTAssertEqual(q.source, .playlist)
    }

    #if canImport(AVFoundation)
    /// Real AVFoundation read of an openly licensed file (Big Buck Bunny, CC BY 3.0).
    func testAVFoundationReadsRealFile() async throws {
        let p = FakeProvider(providerID: "ia", name: "Internet Archive", role: .primary, priority: 0)
        let c = p.candidate(0, url: "https://archive.org/download/BigBuckBunny_124/Content/big_buck_bunny_720p_surround.mp4", label: "1080p")
        let state = await AVFoundationProbe(timeout: 60).probe(c)
        let q = try XCTUnwrap(state.verified, "\(state)")
        print("LIVE AVFoundation: \(q.width)×\(q.height) \(q.codec ?? "?") \(q.bitrate ?? 0) b/s audio \(q.audioFormats)")
        XCTAssertEqual(q.resolution, .hd720, "the '1080p' label is overruled by the file's real size")
        XCTAssertEqual(q.source, .containerMetadata)
    }
    #endif
}
