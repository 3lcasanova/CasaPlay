// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

final class QualityModeTests: XCTestCase {
    private func verified(_ w: Int, _ h: Int) -> VerificationState {
        .verified(VerifiedQuality(source: .containerMetadata, width: w, height: h))
    }

    func testEveryModeIsOffered() {
        XCTAssertEqual(Set(QualityMode.menuOrder), Set(QualityMode.allCases))
    }

    func testSingleResolutionModesAdmitOnlyThatResolution() {
        let streams: [(ResolutionClass, VerificationState)] = [
            (.uhd2160, verified(3840, 2160)),
            (.fhd1080, verified(1920, 1080)),
            (.hd720, verified(1280, 720)),
            (.sd, verified(854, 480)),
        ]
        for mode in [QualityMode.fhdOnly, .hd720Only, .sdOnly] {
            for (resolution, state) in streams {
                XCTAssertEqual(
                    QualityRanking.admits(AdvertisedQuality(), state, mode: mode),
                    resolution == mode.onlyResolution,
                    "\(mode) with \(resolution)"
                )
            }
        }
    }

    func testCheckedResolutionBeatsTheClaim() {
        var claims4K = AdvertisedQuality()
        claims4K.resolution = .uhd2160
        // Claimed 4K but measured 720p: belongs to 720p only, not to 1080p only.
        XCTAssertTrue(QualityRanking.admits(claims4K, verified(1280, 720), mode: .hd720Only))
        XCTAssertFalse(QualityRanking.admits(claims4K, verified(1280, 720), mode: .fhdOnly))
    }

    func testAllResolutionsModeStillAdmitsEverythingPlayable() {
        for state in [verified(3840, 2160), verified(1280, 720), verified(854, 480)] {
            XCTAssertTrue(QualityRanking.admits(AdvertisedQuality(), state, mode: .preferUHD))
        }
    }
}
