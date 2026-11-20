// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Home: what's live and coming up tonight, and a short news briefing. A shelf stays hidden until it has
// something to show, so Home never has an empty row.

import SwiftUI
import CasaPlayKit

struct TodayShelves: View {
    @Environment(AppState.self) private var app
    @Environment(SportsCenter.self) private var sports
    @Environment(NewsCenter.self) private var news

    var body: some View {
        let games = sports.homeGames
        let stories = news.briefing

        VStack(alignment: .leading, spacing: 0) {
            if !games.isEmpty {
                shelf(title: "Live & tonight", destination: .sports) {
                    ForEach(games) { game in
                        Button { app.selectedSection = .sports } label: {
                            HomeGameCard(game: game,
                                         hideResult: sports.spoilerFree,
                                         followed: sports.followedTeamIDs)
                        }
                        .posterButtonStyle()
                    }
                }
            }
            if !stories.isEmpty {
                shelf(title: "News briefing", destination: .news) {
                    ForEach(stories) { story in
                        Button { app.selectedSection = .news } label: {
                            HomeNewsCard(story: story)
                        }
                        .posterButtonStyle()
                    }
                }
            }
        }
        .task { await sports.refreshToday() }
        .task { await news.refresh() }
    }

    @ViewBuilder
    private func shelf<C: View>(title: String, destination: AppSection,
                                @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(tvOS)
        TVShelf(title: title, content: content)
        #else
        Shelf(title: title, destination: destination, content: content)
        #endif
    }
}

struct HomeGameCard: View {
    let game: SportsGame
    let hideResult: Bool
    let followed: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            HStack {
                Text(game.league.short)
                    .font(.casa(10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: Metrics.s(6))
                GameStatusLabel(game: game, hideResult: hideResult)
            }
            teamLine(game.away, score: game.score(spoilerFree: hideResult)?.away)
            teamLine(game.home, score: game.score(spoilerFree: hideResult)?.home)
            Text(game.broadcasts.isEmpty ? " " : "Watch: " + game.broadcasts.prefix(2).joined(separator: ", "))
                .font(.casa(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(Metrics.s(14))
        .frame(width: Metrics.landscapeWidth, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    private func teamLine(_ team: SportsTeam, score: Int?) -> some View {
        HStack(spacing: Metrics.s(8)) {
            TeamLogo(url: team.logoURL, fallback: team.abbreviation)
                .frame(width: Metrics.s(24), height: Metrics.s(24))
            Text(team.shortName)
                .font(.casa(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if followed.contains(team.id) {
                Image(systemName: "star.fill")
                    .font(.casa(10))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: Metrics.s(6))
            if let score {
                Text("\(score)")
                    .font(.casa(16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}

struct HomeNewsCard: View {
    let story: NewsStory

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            NewsThumbnail(url: story.imageURL)
                .frame(width: Metrics.landscapeWidth, height: Metrics.landscapeWidth * 0.5)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            Text(story.headline)
                .font(.casa(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(width: Metrics.landscapeWidth, alignment: .leading)
            Text(NewsFormat.outlets(story.sources))
                .font(.casa(11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
        }
    }
}
