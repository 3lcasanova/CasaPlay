// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

final class FilenameParserTests: XCTestCase {
    func testDottedReleaseName() {
        let parsed = FilenameParser.parse("Night.Ferry.2025.2160p.WEB-DL.HEVC.mkv")
        XCTAssertEqual(parsed.title, "Night Ferry")
        XCTAssertEqual(parsed.year, 2025)
        XCTAssertEqual(parsed.resolution, "2160p")
        XCTAssertFalse(parsed.isEpisode)
    }

    func testParenthesisYear() {
        let parsed = FilenameParser.parse("Night Ferry (2025).mp4")
        XCTAssertEqual(parsed.title, "Night Ferry")
        XCTAssertEqual(parsed.year, 2025)
    }

    func testTitleThatContainsAYear() {
        let parsed = FilenameParser.parse("Blade Runner 2049 (2017).mkv")
        XCTAssertEqual(parsed.title, "Blade Runner 2049")
        XCTAssertEqual(parsed.year, 2017)
    }

    func testEpisode() {
        let parsed = FilenameParser.parse("Tidewater.S01E04.1080p.WEB.mkv")
        XCTAssertEqual(parsed.title, "Tidewater")
        XCTAssertEqual(parsed.season, 1)
        XCTAssertEqual(parsed.episode, 4)
        XCTAssertTrue(parsed.isEpisode)
    }

    func testPathAndUnderscores() {
        let parsed = FilenameParser.parse("Movies/Sub/Harbor_Lights_2024_1080p_BluRay_x264.mkv")
        XCTAssertEqual(parsed.title, "Harbor Lights")
        XCTAssertEqual(parsed.year, 2024)
        XCTAssertEqual(parsed.resolution, "1080p")
    }

    func testPlainName() {
        let parsed = FilenameParser.parse("Fieldwork.mkv")
        XCTAssertEqual(parsed.title, "Fieldwork")
        XCTAssertNil(parsed.year)
    }

    func testNumericTitleKeepsItsName() {
        let parsed = FilenameParser.parse("2012.mkv")
        XCTAssertEqual(parsed.title, "2012")
    }
}
