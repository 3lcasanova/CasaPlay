// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

private func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private func article(_ title: String, _ source: String, _ date: String?, id: String? = nil) -> NewsArticle {
    NewsArticle(id: id ?? "\(source)-\(title)", title: title, summary: "", link: nil, source: source,
                published: date.map(utc), imageURL: nil)
}

// MARK: - News

final class NewsTests: XCTestCase {
    private let rss = """
    <?xml version="1.0"?>
    <rss xmlns:media="http://search.yahoo.com/mrss/"><channel><title>Feed</title>
    <item>
      <title><![CDATA[Brussels summit could reshape the Brexit deal]]></title>
      <description><![CDATA[<p>Leaders meet &amp; talk.</p>]]></description>
      <link>https://a.example/1</link>
      <pubDate>Fri, 20 Nov 2026 10:00:00 GMT</pubDate>
      <media:thumbnail width="240" url="https://img.example/1.jpg"/>
    </item>
    <item>
      <title>Tom &amp; Jerry&#8217;s big day</title>
      <link>https://a.example/2</link>
      <pubDate>Fri, 20 Nov 2026 09:00:00 +0000</pubDate>
      <enclosure url="https://img.example/2.png" type="image/png"/>
    </item>
    <item><description>an item with no title is skipped</description></item>
    </channel></rss>
    """

    func testRSSItemsAreReadWithEntitiesDatesAndImages() {
        let items = NewsParser.parse(Data(rss.utf8), source: "Example")
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].title, "Brussels summit could reshape the Brexit deal")
        XCTAssertEqual(items[0].summary, "Leaders meet & talk.")
        XCTAssertEqual(items[0].link?.absoluteString, "https://a.example/1")
        XCTAssertEqual(items[0].published, utc("2026-11-20T10:00:00Z"))
        XCTAssertEqual(items[0].imageURL?.absoluteString, "https://img.example/1.jpg")
        XCTAssertEqual(items[0].source, "Example")

        XCTAssertEqual(items[1].title, "Tom & Jerry\u{2019}s big day")
        XCTAssertEqual(items[1].published, utc("2026-11-20T09:00:00Z"))
        XCTAssertEqual(items[1].imageURL?.absoluteString, "https://img.example/2.png")
    }

    func testAtomEntriesUseTheirLinkAttributeAndISODates() {
        let atom = """
        <feed><entry><title>Atom story</title><link href="https://a.example/atom"/>
        <updated>2026-11-20T08:00:00Z</updated><summary>Short</summary></entry></feed>
        """
        let items = NewsParser.parse(Data(atom.utf8), source: "Atom")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].link?.absoluteString, "https://a.example/atom")
        XCTAssertEqual(items[0].published, utc("2026-11-20T08:00:00Z"))
        XCTAssertEqual(items[0].summary, "Short")
    }

    func testGarbageReadsAsNoArticles() {
        XCTAssertTrue(NewsParser.parse(Data("not a feed".utf8), source: "x").isEmpty)
        XCTAssertTrue(NewsParser.parse(Data(), source: "x").isEmpty)
    }

    func testSameStoryFromSeveralOutletsIsGroupedAndComesFirst() {
        let now = utc("2026-11-20T12:00:00Z")
        let stories = StoryGrouper.group([
            article("Storm hits coast of Florida", "NPR", "2026-11-20T11:30:00Z"),
            article("Brussels summit could shape Brexit deal", "BBC News", "2026-11-20T10:00:00Z"),
            article("UK and EU leaders meet in Brussels for Brexit summit", "NPR", "2026-11-20T09:00:00Z"),
            article("Brexit deal: what the Brussels summit could mean", "The Guardian", "2026-11-20T08:00:00Z"),
            article("Markets rally as inflation cools", "BBC News", "2026-11-20T11:00:00Z")
        ], now: now)

        XCTAssertEqual(stories.count, 3, "three Brexit headlines become one story")
        XCTAssertEqual(Set(stories[0].sources), ["BBC News", "NPR", "The Guardian"])
        XCTAssertEqual(stories[0].articles.count, 3)
        XCTAssertEqual(stories[0].headline, "Brussels summit could shape Brexit deal", "the newest article leads")
        XCTAssertEqual(stories[1].headline, "Storm hits coast of Florida", "single-outlet stories follow, newest first")
    }

    func testOldArticlesAreLeftOutAndUndatedOnesKept() {
        let now = utc("2026-11-20T12:00:00Z")
        let stories = StoryGrouper.group([
            article("Fresh headline about something", "A", "2026-11-20T11:00:00Z"),
            article("Old headline about another thing", "B", "2026-11-16T11:00:00Z"),
            article("Undated headline about a third matter", "C", nil)
        ], now: now)
        XCTAssertEqual(Set(stories.map(\.headline)),
                       ["Fresh headline about something", "Undated headline about a third matter"])
    }

    func testClientSkipsAFeedThatFails() async {
        let transport = FakeTransport()
        transport.routes["/news/rss.xml"] = HTTPResponse(status: 200, body: Data("""
        <rss><channel><item><title>Only story here today</title><link>https://a.example/only</link></item></channel></rss>
        """.utf8))
        let sources = [
            NewsFeedSource(name: "Good", url: URL(string: "https://a.example/news/rss.xml")!),
            NewsFeedSource(name: "Bad", url: URL(string: "https://b.example/missing.xml")!)
        ]
        let stories = await NewsClient(transport: transport).stories(from: sources)
        XCTAssertEqual(stories.map(\.headline), ["Only story here today"])
        XCTAssertEqual(stories.first?.sources, ["Good"])
    }
}

// MARK: - Sports

final class SportsTests: XCTestCase {
    private let nba = SportsLeague(id: "basketball/nba", name: "NBA", short: "NBA")

    private let board = """
    {"events":[
     {"id":"1","date":"2026-11-20T01:00Z",
      "status":{"type":{"name":"STATUS_FINAL","state":"post","description":"Final","detail":"Final","shortDetail":"Final"}},
      "competitions":[{"venue":{"fullName":"FedExForum"},
        "competitors":[
          {"homeAway":"home","score":"126","team":{"id":"29","displayName":"Memphis Grizzlies","shortDisplayName":"Grizzlies","abbreviation":"MEM","logo":"https://a.example/mem.png"}},
          {"homeAway":"away","score":"98","team":{"id":"9","displayName":"Golden State Warriors","shortDisplayName":"Warriors","abbreviation":"GS"}}],
        "broadcasts":[{"market":"home","names":["DAZN MEM"]}]}]},
     {"id":"2","date":"2026-11-20T03:30Z",
      "status":{"type":{"name":"STATUS_IN_PROGRESS","state":"in","shortDetail":"3:12 - 2nd"}},
      "competitions":[{"competitors":[
          {"homeAway":"home","score":45,"team":{"id":"13","displayName":"Los Angeles Lakers","abbreviation":"LAL"}},
          {"homeAway":"away","score":"40","team":{"id":"25","displayName":"Portland Trail Blazers","abbreviation":"POR"}}],
        "geoBroadcasts":[{"media":{"shortName":"ESPN"}},{"media":{"shortName":"ESPN"}}]}]},
     {"id":"3","date":"2026-11-21T00:00Z",
      "status":{"type":{"name":"STATUS_SCHEDULED","state":"pre","shortDetail":"11/20 - 7:00 PM EST"}},
      "competitions":[{"competitors":[
          {"homeAway":"home","team":{"id":"2","displayName":"Boston Celtics","abbreviation":"BOS"}},
          {"homeAway":"away","team":{"id":"18","displayName":"New York Knicks","abbreviation":"NYK"}}],
        "broadcasts":[{"names":["ESPN","NBA TV"]}]}]},
     {"id":"4","date":"2026-11-21T00:00Z","competitions":"broken"}
    ]}
    """

    private func games() -> [SportsGame] {
        SportsParser.games(from: Data(board.utf8), league: nba)
    }

    func testGamesAreReadAndABrokenOneIsSkipped() {
        let games = games()
        XCTAssertEqual(games.map(\.id), ["basketball/nba:1", "basketball/nba:2", "basketball/nba:3"])
    }

    func testFinishedGame() throws {
        let g = try XCTUnwrap(games().first)
        XCTAssertEqual(g.state, .final)
        XCTAssertEqual(g.detail, "Final")
        XCTAssertEqual(g.homeScore, 126)
        XCTAssertEqual(g.awayScore, 98)
        XCTAssertEqual(g.home.id, "basketball/nba:29")
        XCTAssertEqual(g.home.shortName, "Grizzlies")
        XCTAssertEqual(g.home.logoURL?.absoluteString, "https://a.example/mem.png")
        XCTAssertNil(g.away.logoURL)
        XCTAssertEqual(g.broadcasts, ["DAZN MEM"])
        XCTAssertEqual(g.venue, "FedExForum")
        XCTAssertEqual(g.start, utc("2026-11-20T01:00:00Z"), "times without seconds are read as UTC")
    }

    func testLiveGameReadsANumericScoreAndRemovesDuplicateChannels() throws {
        let g = games()[1]
        XCTAssertEqual(g.state, .live)
        XCTAssertEqual(g.detail, "3:12 - 2nd")
        XCTAssertEqual(g.homeScore, 45)
        XCTAssertEqual(g.awayScore, 40)
        XCTAssertEqual(g.broadcasts, ["ESPN"])
    }

    func testUpcomingGameHasNoScoreAndKeepsItsChannels() {
        let g = games()[2]
        XCTAssertEqual(g.state, .upcoming)
        XCTAssertEqual(g.detail, "")
        XCTAssertNil(g.score(spoilerFree: false))
        XCTAssertEqual(g.broadcasts, ["ESPN", "NBA TV"])
        XCTAssertEqual(g.start, utc("2026-11-21T00:00:00Z"))
    }

    func testSpoilerFreeHidesFinishedResultsOnly() {
        let all = games()
        XCTAssertEqual(all[0].score(spoilerFree: false)?.home, 126)
        XCTAssertNil(all[0].score(spoilerFree: true), "a finished game hides its result")
        XCTAssertEqual(all[1].score(spoilerFree: true)?.home, 45, "a live score stays")
    }

    func testFollowedTeams() {
        let all = games()
        XCTAssertTrue(all[0].involves(["basketball/nba:9"]))
        XCTAssertFalse(all[0].involves(["basketball/nba:13"]))
        XCTAssertTrue(all[1].involves(["basketball/nba:13", "x:1"]))
    }

    func testPostponedGameShowsWhy() throws {
        let json = """
        {"events":[{"id":"9","date":"2026-11-22T00:00Z",
         "status":{"type":{"name":"STATUS_POSTPONED","state":"pre","description":"Postponed","shortDetail":"Postponed"}},
         "competitions":[{"competitors":[
           {"homeAway":"home","team":{"id":"1","displayName":"A"}},
           {"homeAway":"away","team":{"id":"2","displayName":"B"}}]}]}]}
        """
        let g = try XCTUnwrap(SportsParser.games(from: Data(json.utf8), league: nba).first)
        XCTAssertEqual(g.state, .upcoming)
        XCTAssertEqual(g.detail, "Postponed")
    }

    func testScoreboardURLCarriesTheLocalDay() throws {
        let noon = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12)))
        XCTAssertEqual(SportsClient.scoreboardURL(nba, day: noon)?.absoluteString,
                       "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=20261120")
        XCTAssertEqual(SportsClient.scoreboardURL(nba, day: nil)?.absoluteString,
                       "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard")
    }

    func testClientMergesLeaguesAndSkipsOneThatFails() async {
        let transport = FakeTransport()
        transport.routes["/apis/site/v2/sports/basketball/nba/scoreboard"] = HTTPResponse(status: 200, body: Data(board.utf8))
        let nhl = SportsLeague(id: "hockey/nhl", name: "NHL", short: "NHL")
        let games = await SportsClient(transport: transport).games(in: [nba, nhl])
        XCTAssertEqual(games.count, 3, "the failing league adds nothing and doesn't stop the others")
    }

    func testTeamListIsReadAndSorted() async throws {
        let transport = FakeTransport()
        transport.routes["/apis/site/v2/sports/basketball/nba/teams"] = HTTPResponse(status: 200, body: Data("""
        {"sports":[{"leagues":[{"teams":[
          {"team":{"id":"2","displayName":"Boston Celtics","shortDisplayName":"Celtics","abbreviation":"BOS","logos":[{"href":"https://a.example/bos.png"}]}},
          {"team":{"id":"1","displayName":"Atlanta Hawks","shortDisplayName":"Hawks","abbreviation":"ATL"}}
        ]}]}]}
        """.utf8))
        let teams = try await SportsClient(transport: transport).teams(in: nba)
        XCTAssertEqual(teams.map(\.name), ["Atlanta Hawks", "Boston Celtics"])
        XCTAssertEqual(teams[1].id, "basketball/nba:2")
        XCTAssertEqual(teams[1].logoURL?.absoluteString, "https://a.example/bos.png")
    }
}

// MARK: - Followed shows

final class ShowTrackingTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let now = utc("2026-11-20T12:00:00Z")

    private func tracking(last: String?, next: String?, status: String? = "Returning Series") -> ShowTracking {
        TMDBShowAirInfo(
            id: 1, status: status,
            last_episode_to_air: last.map { TMDBEpisodeStub(season_number: 2, episode_number: 5, air_date: $0) },
            next_episode_to_air: next.map { TMDBEpisodeStub(season_number: 2, episode_number: 6, air_date: $0) }
        ).tracking(now: now, calendar: calendar)
    }

    func testNewEpisodeAndTheNextOne() {
        let t = tracking(last: "2026-11-18", next: "2026-11-27")
        XCTAssertTrue(t.hasNewEpisode)
        XCTAssertEqual(t.latestText, "S02 E05 · 2 days ago")
        XCTAssertEqual(t.nextDays, 7)
        XCTAssertTrue(t.nextText?.hasPrefix("S02 E06 · ") == true)
        XCTAssertNotNil(t.nextDate)
    }

    func testNextEpisodeWording() {
        XCTAssertEqual(tracking(last: nil, next: "2026-11-20").nextText, "S02 E06 · today")
        XCTAssertEqual(tracking(last: nil, next: "2026-11-21").nextText, "S02 E06 · tomorrow")
        XCTAssertEqual(tracking(last: nil, next: "2026-11-23").nextText, "S02 E06 · in 3 days")
    }

    func testLatestEpisodeWording() {
        XCTAssertEqual(tracking(last: "2026-11-20", next: nil).latestText, "S02 E05 · today")
        XCTAssertEqual(tracking(last: "2026-11-19", next: nil).latestText, "S02 E05 · yesterday")
    }

    func testOldOrMissingEpisodesSayNothing() {
        let finished = tracking(last: "2026-03-01", next: nil, status: "Ended")
        XCTAssertFalse(finished.hasNewEpisode)
        XCTAssertNil(finished.latestText)
        XCTAssertNil(finished.nextText)
        XCTAssertNil(tracking(last: nil, next: nil).nextText)
    }

    func testFollowListOrdersNewEpisodesThenSoonest() {
        let fresh = tracking(last: "2026-11-19", next: "2026-11-26")
        let soon = tracking(last: "2026-10-01", next: "2026-11-22")
        let later = tracking(last: "2026-10-01", next: "2026-12-10")
        let none = tracking(last: nil, next: nil)
        let ordered = [none, later, soon, fresh].sorted { $0.sortKey < $1.sortKey }
        XCTAssertEqual(ordered, [fresh, soon, later, none])
    }
}

// MARK: - Program guide

final class XtreamEPGTests: XCTestCase {
    private let t0: TimeInterval = 1_700_000_000

    private func guide() throws -> [EPGProgram] {
        let sample = """
        {"epg_listings":[
          {"id":"1","title":"VGhlIE5ld3M=","description":"RGFpbHkgbmV3cyBhdCB0ZW4=",
           "start_timestamp":"\(Int(t0))","stop_timestamp":"\(Int(t0) + 3600)"},
          {"id":"2","title":"RGFpbHkgbmV3cyBhdCB0ZW4=","description":"",
           "start_timestamp":\(Int(t0) + 3600),"stop_timestamp":"\(Int(t0) + 7200)"},
          {"id":"3","title":"Late Movie","start":"2026-11-20 12:00:00","end":"2026-11-20 14:00:00"},
          {"id":"4","title":"","start_timestamp":"\(Int(t0))","stop_timestamp":"\(Int(t0) + 60)"},
          {"id":"5","title":"VGhlIE5ld3M=","start_timestamp":"\(Int(t0))","stop_timestamp":"\(Int(t0))"}
        ]}
        """
        return XtreamEPG.parse(try JSONSerialization.jsonObject(with: Data(sample.utf8)))
    }

    func testTitlesAreDecodedAndBadEntriesSkipped() throws {
        let programs = try guide()
        XCTAssertEqual(programs.map(\.title), ["The News", "Daily news at ten", "Late Movie"])
        XCTAssertEqual(programs[0].detail, "Daily news at ten")
        XCTAssertEqual(programs[0].start, Date(timeIntervalSince1970: t0))
        XCTAssertEqual(programs[1].start, Date(timeIntervalSince1970: t0 + 3600), "numeric timestamps work too")
    }

    func testPlainTextTitleAndStringTimesAreAccepted() throws {
        let late = try XCTUnwrap(guide().first { $0.title == "Late Movie" })
        XCTAssertEqual(late.start, utc("2026-11-20T12:00:00Z"))
        XCTAssertEqual(late.end, utc("2026-11-20T14:00:00Z"))
    }

    func testNowAndNext() throws {
        let programs = try guide()
        let during = XtreamEPG.nowNext(programs, at: Date(timeIntervalSince1970: t0 + 5400))
        XCTAssertEqual(during.now?.title, "Daily news at ten")
        XCTAssertEqual(during.next?.title, "Late Movie")

        let before = XtreamEPG.nowNext(programs, at: Date(timeIntervalSince1970: t0 - 600))
        XCTAssertNil(before.now)
        XCTAssertEqual(before.next?.title, "The News")

        let after = XtreamEPG.nowNext(programs, at: utc("2027-01-01T00:00:00Z"))
        XCTAssertNil(after.now)
        XCTAssertNil(after.next)
    }

    func testProgress() throws {
        let news = try XCTUnwrap(guide().first { $0.title == "The News" })
        XCTAssertEqual(news.progress(at: Date(timeIntervalSince1970: t0 + 1800)), 0.5, accuracy: 0.001)
        XCTAssertEqual(news.progress(at: Date(timeIntervalSince1970: t0 - 10)), 0)
        XCTAssertEqual(news.progress(at: Date(timeIntervalSince1970: t0 + 9999)), 1)
    }

    func testGarbageReadsAsNoPrograms() {
        XCTAssertTrue(XtreamEPG.parse("nope").isEmpty)
        XCTAssertTrue(XtreamEPG.parse(["epg_listings": "x"]).isEmpty)
    }
}
