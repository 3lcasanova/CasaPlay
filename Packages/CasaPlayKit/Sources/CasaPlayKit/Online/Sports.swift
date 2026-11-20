// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Sports: scores, start times and where each game is shown, from ESPN's public scoreboard feed.
// Start times are real moments in time; the screen shows them in the viewer's own timezone.
// The feed is unofficial and needs no key. It is read as plain data only.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SportsLeague: Identifiable, Hashable, Sendable {
    /// The feed's path for the league, for example "basketball/nba".
    public let id: String
    public let name: String
    public let short: String

    public init(id: String, name: String, short: String) {
        self.id = id
        self.name = name
        self.short = short
    }

    public static let all: [SportsLeague] = [
        SportsLeague(id: "football/nfl", name: "NFL", short: "NFL"),
        SportsLeague(id: "basketball/nba", name: "NBA", short: "NBA"),
        SportsLeague(id: "baseball/mlb", name: "MLB", short: "MLB"),
        SportsLeague(id: "hockey/nhl", name: "NHL", short: "NHL"),
        SportsLeague(id: "soccer/eng.1", name: "Premier League", short: "EPL"),
        SportsLeague(id: "soccer/esp.1", name: "La Liga", short: "La Liga"),
        SportsLeague(id: "soccer/uefa.champions", name: "Champions League", short: "UCL"),
        SportsLeague(id: "soccer/usa.1", name: "MLS", short: "MLS"),
        SportsLeague(id: "soccer/ger.1", name: "Bundesliga", short: "Bundesliga"),
        SportsLeague(id: "soccer/ita.1", name: "Serie A", short: "Serie A"),
        SportsLeague(id: "soccer/fra.1", name: "Ligue 1", short: "Ligue 1"),
        SportsLeague(id: "soccer/mex.1", name: "Liga MX", short: "Liga MX"),
        SportsLeague(id: "football/college-football", name: "College Football", short: "NCAAF"),
        SportsLeague(id: "basketball/mens-college-basketball", name: "College Basketball", short: "NCAAM")
    ]

    /// What is switched on until the viewer chooses otherwise.
    public static let starter: [SportsLeague] = all.filter {
        ["football/nfl", "basketball/nba", "baseball/mlb", "hockey/nhl", "soccer/eng.1",
         "soccer/uefa.champions", "soccer/usa.1"].contains($0.id)
    }
}

public enum GameState: String, Sendable {
    case upcoming, live, final
}

public struct SportsTeam: Hashable, Sendable, Identifiable {
    /// Unique across leagues: "<league path>:<team id>".
    public let id: String
    public let name: String
    public let shortName: String
    public let abbreviation: String
    public let logoURL: URL?

    public init(id: String, name: String, shortName: String, abbreviation: String, logoURL: URL?) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.abbreviation = abbreviation
        self.logoURL = logoURL
    }
}

public struct SportsGame: Identifiable, Hashable, Sendable {
    public let id: String
    public let league: SportsLeague
    public let start: Date
    public let state: GameState
    /// "Final", "Q3 4:21", "Halftime", "Postponed". Empty for a game that hasn't started.
    public let detail: String
    public let home: SportsTeam
    public let away: SportsTeam
    public let homeScore: Int?
    public let awayScore: Int?
    /// Channels and services showing the game.
    public let broadcasts: [String]
    public let venue: String?

    public init(id: String, league: SportsLeague, start: Date, state: GameState, detail: String,
                home: SportsTeam, away: SportsTeam, homeScore: Int?, awayScore: Int?,
                broadcasts: [String], venue: String?) {
        self.id = id
        self.league = league
        self.start = start
        self.state = state
        self.detail = detail
        self.home = home
        self.away = away
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.broadcasts = broadcasts
        self.venue = venue
    }

    public func involves(_ teamIDs: Set<String>) -> Bool {
        teamIDs.contains(home.id) || teamIDs.contains(away.id)
    }

    /// The score to show. With spoiler-free on, the result of a finished game is hidden (for replays).
    public func score(spoilerFree: Bool) -> (home: Int, away: Int)? {
        guard state != .upcoming, let h = homeScore, let a = awayScore else { return nil }
        if spoilerFree && state == .final { return nil }
        return (h, a)
    }
}

// MARK: - Reading the feed

public enum SportsParser {
    public static func games(from data: Data, league: SportsLeague) -> [SportsGame] {
        guard let board = try? JSONDecoder().decode(Board.self, from: data) else { return [] }
        let dates = DateReader()
        return (board.events ?? []).compactMap { $0.value }.compactMap { event in
            game(from: event, league: league, dates: dates)
        }
    }

    public static func teams(from data: Data, league: SportsLeague) -> [SportsTeam] {
        guard let list = try? JSONDecoder().decode(TeamList.self, from: data) else { return [] }
        let entries = (list.sports ?? []).flatMap { $0.leagues ?? [] }.flatMap { $0.teams ?? [] }
        return entries.compactMap { entry -> SportsTeam? in
            guard let team = entry.team, let id = team.id?.text, let name = team.displayName else { return nil }
            let logo = team.logo ?? team.logos?.first?.href
            return SportsTeam(id: "\(league.id):\(id)", name: name, shortName: team.shortDisplayName ?? name,
                              abbreviation: team.abbreviation ?? "", logoURL: logo.flatMap { URL(string: $0) })
        }
    }

    private static func game(from event: Event, league: SportsLeague, dates: DateReader) -> SportsGame? {
        guard let id = event.id?.text, let competition = event.competitions?.first,
              let competitors = competition.competitors, competitors.count >= 2 else { return nil }
        guard let start = (event.date ?? competition.date).flatMap(dates.read) else { return nil }

        func team(_ c: Competitor) -> SportsTeam? {
            guard let t = c.team, let tid = t.id?.text, let name = t.displayName else { return nil }
            return SportsTeam(id: "\(league.id):\(tid)", name: name, shortName: t.shortDisplayName ?? name,
                              abbreviation: t.abbreviation ?? "", logoURL: (t.logo).flatMap { URL(string: $0) })
        }
        let homeEntry = competitors.first { $0.homeAway == "home" } ?? competitors[0]
        let awayEntry = competitors.first { $0.homeAway == "away" } ?? competitors[1]
        guard let home = team(homeEntry), let away = team(awayEntry) else { return nil }

        let status = event.status ?? competition.status
        let type = status?.type
        let state: GameState
        switch type?.state {
        case "in": state = .live
        case "post": state = .final
        default: state = .upcoming
        }
        var detail = ""
        if state != .upcoming {
            detail = type?.shortDetail ?? type?.detail ?? ""
        } else {
            let name = (type?.name ?? "").uppercased()
            if ["POSTPONED", "CANCELED", "CANCELLED", "DELAYED", "SUSPENDED"].contains(where: { name.contains($0) }) {
                detail = type?.description ?? type?.shortDetail ?? ""
            }
        }

        var channels: [String] = []
        for broadcast in competition.broadcasts ?? [] { channels += broadcast.names ?? [] }
        if channels.isEmpty {
            channels = (competition.geoBroadcasts ?? []).compactMap { $0.media?.shortName }
        }
        var seen = Set<String>()
        channels = channels.filter { !$0.isEmpty && seen.insert($0).inserted }

        return SportsGame(
            id: "\(league.id):\(id)", league: league, start: start, state: state, detail: detail,
            home: home, away: away,
            homeScore: homeEntry.score?.text.flatMap { Int($0) }, awayScore: awayEntry.score?.text.flatMap { Int($0) },
            broadcasts: channels, venue: competition.venue?.fullName)
    }

    // MARK: Feed shapes (every field optional: a game missing a piece is skipped, never the whole day)

    private struct Board: Decodable { let events: [Failable<Event>]? }

    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// A value the feed sends as text in some leagues and as a number in others.
    private struct Flexible: Decodable {
        let text: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { text = s }
            else if let i = try? c.decode(Int.self) { text = String(i) }
            else if let d = try? c.decode(Double.self) { text = String(Int(d)) }
            else { text = nil }
        }
    }

    private struct Event: Decodable {
        let id: Flexible?
        let date: String?
        let status: Status?
        let competitions: [Competition]?
    }

    private struct Status: Decodable {
        let type: StatusType?
    }

    private struct StatusType: Decodable {
        let name: String?
        let state: String?
        let description: String?
        let detail: String?
        let shortDetail: String?
    }

    private struct Competition: Decodable {
        let date: String?
        let status: Status?
        let venue: Venue?
        let competitors: [Competitor]?
        let broadcasts: [Broadcast]?
        let geoBroadcasts: [GeoBroadcast]?
    }

    private struct Venue: Decodable { let fullName: String? }

    private struct Competitor: Decodable {
        let homeAway: String?
        let score: Flexible?
        let team: TeamInfo?
    }

    private struct TeamInfo: Decodable {
        let id: Flexible?
        let displayName: String?
        let shortDisplayName: String?
        let abbreviation: String?
        let logo: String?
        let logos: [Logo]?
    }

    private struct Logo: Decodable { let href: String? }
    private struct Broadcast: Decodable { let names: [String]? }
    private struct GeoBroadcast: Decodable { let media: Media? }
    private struct Media: Decodable { let shortName: String? }

    private struct TeamList: Decodable { let sports: [SportEntry]? }
    private struct SportEntry: Decodable { let leagues: [LeagueEntry]? }
    private struct LeagueEntry: Decodable { let teams: [TeamEntry]? }
    private struct TeamEntry: Decodable { let team: TeamInfo? }

    /// The feed writes times like 2026-11-20T01:00Z (no seconds), which the standard reader refuses.
    private final class DateReader {
        private let short: DateFormatter
        private let iso = ISO8601DateFormatter()

        init() {
            short = DateFormatter()
            short.locale = Locale(identifier: "en_US_POSIX")
            short.timeZone = TimeZone(identifier: "UTC")
            short.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        }

        func read(_ text: String) -> Date? {
            short.date(from: text) ?? iso.date(from: text)
        }
    }
}

// MARK: - Loading

public struct SportsClient: Sendable {
    private let transport: HTTPTransport
    static let base = "https://site.api.espn.com/apis/site/v2/sports"

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    static func scoreboardURL(_ league: SportsLeague, day: Date?) -> URL? {
        var text = "\(base)/\(league.id)/scoreboard"
        if let day {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd"
            text += "?dates=\(f.string(from: day))"
        }
        return URL(string: text)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("CasaPlay/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else { throw OnlineServiceError.badStatus(response.status) }
        return response.body
    }

    public func scoreboard(_ league: SportsLeague, day: Date? = nil) async throws -> [SportsGame] {
        guard let url = Self.scoreboardURL(league, day: day) else { throw OnlineServiceError.invalidResponse }
        return SportsParser.games(from: try await fetch(url), league: league)
    }

    /// Every league at once. A league that fails is skipped, so one slow feed never blanks the screen.
    public func games(in leagues: [SportsLeague], day: Date? = nil) async -> [SportsGame] {
        await withTaskGroup(of: [SportsGame].self) { group -> [SportsGame] in
            for league in leagues {
                group.addTask { (try? await self.scoreboard(league, day: day)) ?? [] }
            }
            var out: [SportsGame] = []
            for await part in group { out += part }
            return out
        }
    }

    public func teams(in league: SportsLeague) async throws -> [SportsTeam] {
        guard let url = URL(string: "\(Self.base)/\(league.id)/teams") else { throw OnlineServiceError.invalidResponse }
        let teams = SportsParser.teams(from: try await fetch(url), league: league)
        return teams.sorted { $0.name < $1.name }
    }
}
