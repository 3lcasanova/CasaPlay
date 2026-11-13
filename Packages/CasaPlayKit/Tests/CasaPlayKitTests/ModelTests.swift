// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

final class ModelTests: XCTestCase {
    func testClockFormatting() {
        XCTAssertEqual(TimeFormat.clock(4328), "1:12:08")
        XCTAssertEqual(TimeFormat.clock(65), "1:05")
        XCTAssertEqual(TimeFormat.clock(-5), "0:00")
    }

    func testRuntimeFormatting() {
        XCTAssertEqual(TimeFormat.runtime(7440), "2h 04m")
        XCTAssertEqual(TimeFormat.runtime(2700), "45m")
    }

    func testTimeLeftFormatting() {
        XCTAssertEqual(TimeFormat.timeLeft(3112), "52 min left")
        XCTAssertEqual(TimeFormat.timeLeft(3900), "1h 05m left")
    }

    func testVTTTimestamp() {
        XCTAssertEqual(TimeFormat.vtt(3723.5), "01:02:03.500")
    }

    func testResumeRules() {
        let file = MediaFileInfo(container: .mp4, videoCodec: .h264)
        var item = MediaItem(title: "Test", runtimeSeconds: 6000, file: file)
        XCTAssertFalse(item.canResume)

        item.progressSeconds = 10
        XCTAssertFalse(item.canResume, "Under 30 seconds is not worth resuming")

        item.progressSeconds = 3000
        XCTAssertTrue(item.canResume)
        XCTAssertEqual(item.progressFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(item.remainingSeconds, 3000, accuracy: 0.0001)

        item.progressSeconds = 5800
        XCTAssertFalse(item.canResume, "Over 95% counts as finished")
    }

    func testMetaLineAndBadges() {
        let night = SampleData.movies[0]
        XCTAssertEqual(night.metaLine, "2025 · 2h 04m · PG-13")
        XCTAssertEqual(night.file.badges, ["4K", "DOLBY VISION", "ATMOS"])
    }

    func testCastInitials() {
        XCTAssertEqual(CastMember(name: "Mara Linden", role: "Capt. Hale").initials, "ML")
    }

    func testContainerFromExtension() {
        XCTAssertEqual(MediaContainer(fileExtension: "MKV"), .mkv)
        XCTAssertEqual(MediaContainer(fileExtension: "m3u8"), .hls)
        XCTAssertEqual(MediaContainer(fileExtension: "xyz"), .other)
    }
}
