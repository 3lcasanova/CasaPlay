// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Data for the News and Sports screens and the Home shelves. Loaded once and kept for a few minutes,
// so switching tabs never reloads. Settings (leagues, followed teams, spoiler-free) stay on this device.

import SwiftUI
import CasaPlayKit

@MainActor
@Observable
final class NewsCenter {
    static let shared = NewsCenter()

    private(set) var stories: [NewsStory] = []
    private(set) var isLoading = false
    private(set) var failed = false

    private var loadedAt: Date?
    private let client = NewsClient()

    private init() {}

    /// The few stories that matter most right now.
    var briefing: [NewsStory] { Array(stories.prefix(5)) }

    func refresh(force: Bool = false) async {
        if !force, let loadedAt, !stories.isEmpty, Date().timeIntervalSince(loadedAt) < 600 { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let result = await client.stories()
        failed = result.isEmpty
        if !result.isEmpty {
            stories = result
            loadedAt = Date()
        }
    }
}

@MainActor
@Observable
final class SportsCenter {
    static let shared = SportsCenter()

    private(set) var games: [SportsGame] = []
    private(set) var isLoading = false
    private(set) var failed = false

    /// -1 yesterday, 0 today, 1 tomorrow.
    var dayOffset = 0
    var enabledLeagueIDs: [String] {
        didSet { UserDefaults.standard.set(enabledLeagueIDs, forKey: Keys.leagues) }
    }
    /// Followed teams: team id → name.
    var followedTeams: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(followedTeams) {
                UserDefaults.standard.set(data, forKey: Keys.teams)
            }
        }
    }
    var spoilerFree: Bool {
        didSet { UserDefaults.standard.set(spoilerFree, forKey: Keys.spoilerFree) }
    }

    private enum Keys {
        static let leagues = "sports.leagues"
        static let teams = "sports.followedTeams"
        static let spoilerFree = "sports.spoilerFree"
    }

    private let client = SportsClient()
    private var generation = 0
    private var loadedKey: String?
    private var loadedAt: Date?

    private init() {
        let defaults = UserDefaults.standard
        enabledLeagueIDs = defaults.stringArray(forKey: Keys.leagues) ?? SportsLeague.starter.map(\.id)
        spoilerFree = defaults.bool(forKey: Keys.spoilerFree)
        if let data = defaults.data(forKey: Keys.teams),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            followedTeams = saved
        } else {
            followedTeams = [:]
        }
    }

    // MARK: Settings

    var enabledLeagues: [SportsLeague] {
        SportsLeague.all.filter { enabledLeagueIDs.contains($0.id) }
    }

    var followedTeamIDs: Set<String> { Set(followedTeams.keys) }

    func isFollowed(_ team: SportsTeam) -> Bool { followedTeams[team.id] != nil }

    func toggleFollow(_ team: SportsTeam) {
        if followedTeams[team.id] != nil {
            followedTeams[team.id] = nil
        } else {
            followedTeams[team.id] = team.name
        }
    }

    func toggleLeague(_ league: SportsLeague) {
        if let index = enabledLeagueIDs.firstIndex(of: league.id) {
            enabledLeagueIDs.remove(at: index)
        } else {
            enabledLeagueIDs.append(league.id)
        }
    }

    // MARK: Loading

    func refresh(force: Bool = false) async {
        let leagues = enabledLeagues
        let key = leagues.map(\.id).sorted().joined(separator: ",") + "|\(dayOffset)"
        if !force, key == loadedKey, let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }

        generation += 1
        let mine = generation
        isLoading = true
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())
        let result = await client.games(in: leagues, day: day)
        guard mine == generation else { return }
        isLoading = false
        games = result
        failed = result.isEmpty && !leagues.isEmpty
        loadedKey = key
        loadedAt = Date()
    }

    // MARK: Groups for the screens

    private static func soonest(_ a: SportsGame, _ b: SportsGame) -> Bool { a.start < b.start }

    var live: [SportsGame] { games.filter { $0.state == .live }.sorted(by: Self.soonest) }
    var upcoming: [SportsGame] { games.filter { $0.state == .upcoming }.sorted(by: Self.soonest) }
    var finished: [SportsGame] { games.filter { $0.state == .final }.sorted { $0.start > $1.start } }

    /// Games involving a followed team, live first.
    var yours: [SportsGame] {
        let ids = followedTeamIDs
        guard !ids.isEmpty else { return [] }
        let mine = games.filter { $0.involves(ids) }
        return mine.sorted { a, b in
            if (a.state == .live) != (b.state == .live) { return a.state == .live }
            return a.start < b.start
        }
    }
}
