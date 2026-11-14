// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

final class ReleaseBadgeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-14 12:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
    }

    private func show(status: String? = "Returning Series", last: (Int, Int, String)? = nil,
                      next: (Int, Int, String)? = nil) -> TMDBShowAirInfo {
        TMDBShowAirInfo(
            id: 1, status: status,
            last_episode_to_air: last.map { TMDBEpisodeStub(season_number: $0.0, episode_number: $0.1, air_date: $0.2) },
            next_episode_to_air: next.map { TMDBEpisodeStub(season_number: $0.0, episode_number: $0.1, air_date: $0.2) })
    }

    func testDaysUntilCountsWholeCalendarDays() {
        XCTAssertEqual(ReleaseDates.days(until: "2026-11-14", now: now, calendar: calendar), 0)
        XCTAssertEqual(ReleaseDates.days(until: "2026-11-22", now: now, calendar: calendar), 8)
        XCTAssertEqual(ReleaseDates.days(until: "2026-11-10", now: now, calendar: calendar), -4)
        XCTAssertNil(ReleaseDates.days(until: "soon", now: now, calendar: calendar))
        XCTAssertNil(ReleaseDates.days(until: nil, now: now, calendar: calendar))
        XCTAssertNil(ReleaseDates.days(until: "", now: now, calendar: calendar))
    }

    func testEpisodeLabelIsPaddedAndNeedsBothNumbers() {
        XCTAssertEqual(TMDBEpisodeStub(season_number: 1, episode_number: 4, air_date: nil).label, "S01 E04")
        XCTAssertEqual(TMDBEpisodeStub(season_number: 12, episode_number: 103, air_date: nil).label, "S12 E103")
        XCTAssertNil(TMDBEpisodeStub(season_number: 1, episode_number: nil, air_date: nil).label)
    }

    func testAnEpisodeAiringTodayGetsTheTodayRibbon() {
        let badge = show(last: (1, 3, "2026-11-07"), next: (1, 4, "2026-11-14")).badge(now: now, calendar: calendar)
        XCTAssertEqual(badge, EpisodeBadge(label: "S01 E04", ribbon: "TODAY"))
        let justAired = show(last: (2, 9, "2026-11-14")).badge(now: now, calendar: calendar)
        XCTAssertEqual(justAired, EpisodeBadge(label: "S02 E09", ribbon: "TODAY"))
    }

    func testTheNextEpisodeCountsDown() {
        let soon = show(last: (1, 3, "2026-11-07"), next: (1, 4, "2026-11-22")).badge(now: now, calendar: calendar)
        XCTAssertEqual(soon, EpisodeBadge(label: "S01 E04", ribbon: "IN 8 DAYS"))
        let tomorrow = show(next: (3, 1, "2026-11-15")).badge(now: now, calendar: calendar)
        XCTAssertEqual(tomorrow?.ribbon, "TOMORROW")
    }

    func testARunningShowThatAiredThisFortnightIsWeekly() {
        let badge = show(last: (4, 6, "2026-11-08")).badge(now: now, calendar: calendar)
        XCTAssertEqual(badge, EpisodeBadge(label: "S04 E06", ribbon: "WEEKLY"))
        let finished = show(status: "Ended", last: (4, 6, "2026-11-08")).badge(now: now, calendar: calendar)
        XCTAssertEqual(finished?.ribbon, "NEW")
    }

    func testOldOrFarOffEpisodesGetNoBadge() {
        XCTAssertNil(show(last: (1, 8, "2025-01-01")).badge(now: now, calendar: calendar))
        XCTAssertNil(show(next: (2, 1, "2027-06-01")).badge(now: now, calendar: calendar))
        XCTAssertNil(show().badge(now: now, calendar: calendar))
    }

    func testMovieRibbons() {
        XCTAssertEqual(ReleaseDates.movieRibbon(releaseDate: "2026-11-14", now: now, calendar: calendar), "TODAY")
        XCTAssertEqual(ReleaseDates.movieRibbon(releaseDate: "2026-11-15", now: now, calendar: calendar), "TOMORROW")
        XCTAssertEqual(ReleaseDates.movieRibbon(releaseDate: "2026-12-04", now: now, calendar: calendar), "IN 20 DAYS")
        XCTAssertEqual(ReleaseDates.movieRibbon(releaseDate: "2026-11-05", now: now, calendar: calendar), "NEW")
        XCTAssertNil(ReleaseDates.movieRibbon(releaseDate: "2026-09-01", now: now, calendar: calendar))
        XCTAssertNil(ReleaseDates.movieRibbon(releaseDate: "2027-09-01", now: now, calendar: calendar))
        XCTAssertNil(ReleaseDates.movieRibbon(releaseDate: nil, now: now, calendar: calendar))
    }

    func testScorePercent() {
        XCTAssertEqual(TMDBScore.percent(7.84), 78)
        XCTAssertEqual(TMDBScore.percent(10), 100)
        XCTAssertNil(TMDBScore.percent(0))
        XCTAssertNil(TMDBScore.percent(nil))
    }
}
