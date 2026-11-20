// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Sports: scores, start times in your own timezone, and where each game is shown. Follow teams to see
// their games first. Spoiler-free hides the result of finished games until you choose to reveal one.

import SwiftUI
import CasaPlayKit

struct SportsView: View {
    @Environment(SportsCenter.self) private var center
    @State private var revealed: Set<String> = []
    @State private var showingLeagues = false
    @State private var showingTeams = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    ScreenTitle("Sports")
                    controls
                    content
                }
                .padding(.vertical, Metrics.s(16))
            }
            .tvFullWidth()
            .screenBackground()
            #if !os(tvOS)
            .refreshable { await center.refresh(force: true) }
            #endif
            .scrollingScreenTitle("Sports")
            .task(id: loadKey) { await center.refresh() }
            .adaptiveSheet(isPresented: $showingLeagues) { LeaguePicker() }
            .adaptiveSheet(isPresented: $showingTeams) { TeamPicker() }
        }
    }

    /// Changes when the day or the chosen leagues change, so the scores reload.
    private var loadKey: String {
        center.enabledLeagueIDs.joined(separator: ",") + "|\(center.dayOffset)"
    }

    // MARK: Controls

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.s(8)) {
                ForEach([-1, 0, 1], id: \.self) { offset in
                    ChipButton(title: Self.dayTitle(offset), isSelected: center.dayOffset == offset) {
                        center.dayOffset = offset
                    }
                }
                ChipButton(title: "Spoiler-free", isSelected: center.spoilerFree) {
                    center.spoilerFree.toggle()
                    revealed.removeAll()
                }
                ChipButton(title: "My teams", isSelected: false) { showingTeams = true }
                ChipButton(title: "Leagues", isSelected: false) { showingLeagues = true }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, Platform.isTV ? 14 : 0)
        }
        .tvFocusSection()
    }

    private static func dayTitle(_ offset: Int) -> String {
        switch offset {
        case -1: return "Yesterday"
        case 1: return "Tomorrow"
        default: return "Today"
        }
    }

    // MARK: Games

    @ViewBuilder
    private var content: some View {
        if center.games.isEmpty {
            if center.isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Metrics.sectionSpacing)
            } else {
                Text(center.failed
                     ? "Couldn't load scores. Check your connection."
                     : "No games on this day in your leagues. Try another day, or add leagues.")
                    .font(.casa(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.top, Metrics.sectionSpacing)
                    .focusableOnTV()
            }
        } else {
            let mine = center.yours
            let mineIDs = Set(mine.map(\.id))
            section("Your teams", mine)
            section("Live now", center.live.filter { !mineIDs.contains($0.id) })
            section("Coming up", center.upcoming.filter { !mineIDs.contains($0.id) })
            section("Finished", center.finished.filter { !mineIDs.contains($0.id) })
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ games: [SportsGame]) -> some View {
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s(10)) {
                Text(title)
                    .font(.casa(18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Metrics.screenPadding)

                LazyVStack(spacing: Metrics.s(10)) {
                    ForEach(games) { game in
                        Button { reveal(game) } label: {
                            GameRow(game: game,
                                    hideResult: center.spoilerFree && !revealed.contains(game.id),
                                    followed: center.followedTeamIDs)
                        }
                        .cardRowButtonStyle()
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .tvFocusSection()
            }
        }
    }

    private func reveal(_ game: SportsGame) {
        guard center.spoilerFree, game.state == .final else { return }
        if revealed.contains(game.id) { revealed.remove(game.id) } else { revealed.insert(game.id) }
    }
}

// MARK: - A game

struct GameRow: View {
    let game: SportsGame
    let hideResult: Bool
    let followed: Set<String>

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.s(14)) {
            VStack(alignment: .leading, spacing: Metrics.s(8)) {
                teamLine(game.away, score: game.score(spoilerFree: hideResult)?.away)
                teamLine(game.home, score: game.score(spoilerFree: hideResult)?.home)
            }
            Spacer(minLength: Metrics.s(8))
            VStack(alignment: .trailing, spacing: Metrics.s(4)) {
                GameStatusLabel(game: game, hideResult: hideResult)
                if !game.broadcasts.isEmpty {
                    Text("Watch: " + game.broadcasts.prefix(3).joined(separator: ", "))
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                Text(game.league.short)
                    .font(.casa(10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Metrics.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    private func teamLine(_ team: SportsTeam, score: Int?) -> some View {
        HStack(spacing: Metrics.s(10)) {
            TeamLogo(url: team.logoURL, fallback: team.abbreviation)
                .frame(width: Metrics.s(26), height: Metrics.s(26))
            Text(team.shortName)
                .font(.casa(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if followed.contains(team.id) {
                Image(systemName: "star.fill")
                    .font(.casa(11))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: Metrics.s(8))
            if let score {
                Text("\(score)")
                    .font(.casa(17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            } else if hideResult && game.state == .final {
                Text("–")
                    .font(.casa(17, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// The start in the viewer's own timezone: just the time today, the day and time otherwise.
    static func startText(_ start: Date) -> String {
        if Calendar.current.isDateInToday(start) {
            return start.formatted(date: .omitted, time: .shortened)
        }
        return start.formatted(date: .abbreviated, time: .shortened)
    }
}

/// "LIVE · 3:12 - 2nd", "Final", or the start time in the viewer's timezone.
struct GameStatusLabel: View {
    let game: SportsGame
    let hideResult: Bool

    var body: some View {
        switch game.state {
        case .live:
            HStack(spacing: Metrics.s(5)) {
                Circle().fill(Color.red).frame(width: Metrics.s(7), height: Metrics.s(7))
                Text(game.detail.isEmpty ? "LIVE" : "LIVE · " + game.detail)
                    .font(.casa(12, weight: .bold))
                    .foregroundStyle(Color.red)
            }
        case .final:
            Text(hideResult ? "Final · select to reveal" : (game.detail.isEmpty ? "Final" : game.detail))
                .font(.casa(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        case .upcoming:
            if !game.detail.isEmpty {
                Text(game.detail)
                    .font(.casa(12, weight: .semibold))
                    .foregroundStyle(Color.orange)
            } else {
                Text(GameRow.startText(game.start))
                    .font(.casa(12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

struct TeamLogo: View {
    let url: URL?
    let fallback: String

    var body: some View {
        if let url, url.scheme?.lowercased() == "https" {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    initials
                }
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Theme.surfaceStrong)
            Text(String(fallback.prefix(3)))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Choosing leagues and teams

private struct LeaguePicker: View {
    @Environment(SportsCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(10)) {
                    ScreenTitle("Leagues")
                    ForEach(SportsLeague.all) { league in
                        Button { center.toggleLeague(league) } label: {
                            HStack {
                                Text(league.name)
                                    .font(.casa(15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: center.enabledLeagueIDs.contains(league.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(Metrics.s(14))
                            .frame(maxWidth: .infinity)
                            .background(Theme.surface,
                                        in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                        }
                        .cardRowButtonStyle()
                    }
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            #if !os(tvOS)
            .navigationTitle("Leagues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
    }
}

private struct TeamPicker: View {
    @Environment(SportsCenter.self) private var center
    @Environment(\.dismiss) private var dismiss
    @State private var league: SportsLeague?
    @State private var teams: [SportsTeam] = []
    @State private var isLoading = false
    private let client = SportsClient()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(12)) {
                    ScreenTitle("My teams")

                    if center.enabledLeagues.isEmpty {
                        Text("Turn on a league first.")
                            .font(.casa(14))
                            .foregroundStyle(Theme.textSecondary)
                            .focusableOnTV()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Metrics.s(8)) {
                                ForEach(center.enabledLeagues) { option in
                                    ChipButton(title: option.short, isSelected: league == option) { league = option }
                                }
                            }
                            .padding(.vertical, Platform.isTV ? 14 : 0)
                        }
                        .tvFocusSection()
                    }

                    if isLoading {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                    }

                    LazyVStack(spacing: Metrics.s(8)) {
                        ForEach(teams) { team in
                            Button { center.toggleFollow(team) } label: {
                                HStack(spacing: Metrics.s(10)) {
                                    TeamLogo(url: team.logoURL, fallback: team.abbreviation)
                                        .frame(width: Metrics.s(26), height: Metrics.s(26))
                                    Text(team.name)
                                        .font(.casa(15, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Image(systemName: center.isFollowed(team) ? "star.fill" : "star")
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(Metrics.s(12))
                                .frame(maxWidth: .infinity)
                                .background(Theme.surface,
                                            in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                            }
                            .cardRowButtonStyle()
                        }
                    }
                    .tvFocusSection()
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            .task(id: league?.id) { await loadTeams() }
            .onAppear { if league == nil { league = center.enabledLeagues.first } }
            #if !os(tvOS)
            .navigationTitle("My teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
    }

    private func loadTeams() async {
        guard let league else { teams = []; return }
        isLoading = true
        defer { isLoading = false }
        teams = (try? await client.teams(in: league)) ?? []
    }
}
