// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

final class PersonalXtreamTests: XCTestCase {
    func testAddressWithoutSchemeGetsHTTPS() throws {
        let p = try XCTUnwrap(PersonalXtream(server: "iptv.example.org", username: "user1", password: "pass1"))
        XCTAssertEqual(p.server.absoluteString, "https://iptv.example.org")
        XCTAssertEqual(p.login, XtreamLogin(username: "user1", password: "pass1"))
    }

    func testFullHTTPSAddressAndTrailingSlash() throws {
        let p = try XCTUnwrap(PersonalXtream(server: " https://iptv.example.org/ ", username: "u", password: "p"))
        XCTAssertEqual(p.server.absoluteString, "https://iptv.example.org")
    }

    func testUnsetBuildSettingsAreIgnored() {
        XCTAssertNil(PersonalXtream(server: "$(XTREAM_SERVER)", username: "u", password: "p"))
        XCTAssertNil(PersonalXtream(server: "iptv.example.org", username: "$(XTREAM_USERNAME)", password: "p"))
        XCTAssertNil(PersonalXtream(server: "iptv.example.org", username: "u", password: "$(XTREAM_PASSWORD)"))
        XCTAssertNil(PersonalXtream(server: "", username: "", password: ""))
    }

    func testRejectsPlainHTTPAndLoginsInTheAddress() {
        XCTAssertNil(PersonalXtream(server: "http://iptv.example.org", username: "u", password: "p"))
        XCTAssertNil(PersonalXtream(server: "https://a:b@iptv.example.org", username: "u", password: "p"))
        XCTAssertNil(PersonalXtream(server: "https://iptv.example.org/player_api.php?x=1", username: "u", password: "p"))
    }
}
