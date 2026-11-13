// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

final class PlaybackRouterTests: XCTestCase {
    private let router = PlaybackRouter(capabilities: .appleTV4K, compatibilityEngineEnabled: false)

    func testNativeFileDirectPlays() {
        let file = MediaFileInfo(
            container: .mp4, videoCodec: .hevc, hdr: .dolbyVision,
            width: 3840, height: 2160, audioCodecs: [.eac3Atmos, .aac]
        )
        let decision = router.decide(for: file)
        XCTAssertEqual(decision.engine, .apple)
        XCTAssertTrue(decision.isDirectPlay)
        XCTAssertEqual(decision.badgeText, "Direct Play · Apple engine")
    }

    func testMKVIsUnsupportedUntilFallbackExists() {
        let file = MediaFileInfo(container: .mkv, videoCodec: .h264, audioCodecs: [.ac3])
        let decision = router.decide(for: file)
        XCTAssertEqual(decision.engine, .unsupported)
        XCTAssertFalse(decision.isPlayable)
        XCTAssertEqual(decision.reasons, ["MKV container"])
    }

    func testServerStreamBeatsFallbackEngine() {
        let file = MediaFileInfo(container: .mkv, videoCodec: .h264, audioCodecs: [.ac3])
        let enabled = PlaybackRouter(capabilities: .appleTV4K, compatibilityEngineEnabled: true)
        XCTAssertEqual(enabled.decide(for: file, serverCanStream: true).engine, .appleViaServerStream)
        XCTAssertEqual(enabled.decide(for: file, serverCanStream: false).engine, .compatibility)
    }

    func testDTSOnlyAudioBlocksDirectPlay() {
        let file = MediaFileInfo(container: .mp4, videoCodec: .h264, audioCodecs: [.dts])
        let decision = router.decide(for: file)
        XCTAssertEqual(decision.engine, .unsupported)
        XCTAssertEqual(decision.reasons, ["DTS audio"])
    }

    func testDTSPlusAC3PlaysWithANote() {
        let file = MediaFileInfo(container: .mp4, videoCodec: .h264, audioCodecs: [.dts, .ac3])
        let decision = router.decide(for: file)
        XCTAssertEqual(decision.engine, .apple)
        XCTAssertTrue(decision.notes.contains { $0.contains("DTS") })
    }

    func testAV1NeedsHardwareSupport() {
        let file = MediaFileInfo(container: .mp4, videoCodec: .av1, audioCodecs: [.aac])
        XCTAssertEqual(router.decide(for: file).engine, .unsupported)

        var caps = DeviceCapabilities.appleTV4K
        caps.supportsAV1 = true
        let capable = PlaybackRouter(capabilities: caps)
        XCTAssertEqual(capable.decide(for: file).engine, .apple)
    }

    func testImageSubtitlesAddANote() {
        let file = MediaFileInfo(
            container: .mp4, videoCodec: .hevc,
            audioCodecs: [.eac3], subtitleFormats: [.pgs]
        )
        let decision = router.decide(for: file)
        XCTAssertEqual(decision.engine, .apple)
        XCTAssertTrue(decision.notes.contains { $0.contains("PGS") })
    }

    func testSampleLibraryHasBothKindsOfFile() {
        let decisions = SampleData.movies.map { router.decide(for: $0.file).engine }
        XCTAssertTrue(decisions.contains(.apple))
        XCTAssertTrue(decisions.contains(.unsupported))
    }
}
