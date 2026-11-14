// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The small labels on a poster: "S01 E04" for the episode, and a corner ribbon such as TODAY,
// IN 8 DAYS or WEEKLY. All the date maths lives here so it can be tested without a screen.

import Foundation

/// One episode as TMDB lists it on a show: only the fields the badge needs.
public struct TMDBEpisodeStub: Decodable, Sendable, Equatable {
    public let season_number: Int?
    public let episode_number: Int?
    public let air_date: String?

    public init(season_number: Int?, episode_number: Int?, air_date: String?) {
        self.season_number = season_number
        self.episode_number = episode_number
        self.air_date = air_date
    }

    /// "S01 E04", or nil when TMDB doesn't know the numbers.
    public var label: String? {
        guard let season = season_number, let episode = episode_number else { return nil }
        return String(format: "S%02d E%02d", season, episode)
    }
}

/// The part of a show's details that says when its episodes air.
public struct TMDBShowAirInfo: Decodable, Sendable {
    public let id: Int
    public let status: String?
    public let last_episode_to_air: TMDBEpisodeStub?
    public let next_episode_to_air: TMDBEpisodeStub?

    public init(id: Int, status: String? = nil,
                last_episode_to_air: TMDBEpisodeStub? = nil,
                next_episode_to_air: TMDBEpisodeStub? = nil) {
        self.id = id
        self.status = status
        self.last_episode_to_air = last_episode_to_air
        self.next_episode_to_air = next_episode_to_air
    }
}

/// What to print on a poster: an episode label (top left) and a ribbon (top right). Either may be missing.
public struct EpisodeBadge: Equatable, Sendable {
    public let label: String?
    public let ribbon: String?

    public init(label: String?, ribbon: String?) {
        self.label = label
        self.ribbon = ribbon
    }
}

public enum ReleaseDates {
    /// Whole days from today to a "yyyy-MM-dd" date. 0 is today, negative is in the past,
    /// nil when the text isn't a date.
    public static func days(until dateString: String?, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let dateString, dateString.count >= 10 else { return nil }
        let parts = dateString.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var parts3 = DateComponents()
        parts3.year = year
        parts3.month = month
        parts3.day = day
        guard let target = calendar.date(from: parts3) else { return nil }
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: target)).day
    }

    /// TODAY, TOMORROW or IN N DAYS for something coming up.
    static func countdown(_ days: Int) -> String {
        switch days {
        case 0: return "TODAY"
        case 1: return "TOMORROW"
        default: return "IN \(days) DAYS"
        }
    }

    /// Ribbon for a film: a countdown up to two months ahead, NEW for two weeks after it opened.
    public static func movieRibbon(releaseDate: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let days = days(until: releaseDate, now: now, calendar: calendar) else { return nil }
        switch days {
        case 0...60: return countdown(days)
        case -14 ... -1: return "NEW"
        default: return nil
        }
    }
}

extension TMDBShowAirInfo {
    /// Today's episode first, then the next one coming (within two months), then one that aired in
    /// the last two weeks, which is WEEKLY for a show that is still running. Nothing otherwise,
    /// so an old finished show shows no episode label.
    public func badge(now: Date = Date(), calendar: Calendar = .current) -> EpisodeBadge? {
        let next = ReleaseDates.days(until: next_episode_to_air?.air_date, now: now, calendar: calendar)
        let last = ReleaseDates.days(until: last_episode_to_air?.air_date, now: now, calendar: calendar)

        if next == 0, let episode = next_episode_to_air {
            return EpisodeBadge(label: episode.label, ribbon: "TODAY")
        }
        if last == 0, let episode = last_episode_to_air {
            return EpisodeBadge(label: episode.label, ribbon: "TODAY")
        }
        if let days = next, days > 0, days <= 60, let episode = next_episode_to_air {
            return EpisodeBadge(label: episode.label, ribbon: ReleaseDates.countdown(days))
        }
        if let days = last, days < 0, days >= -14, let episode = last_episode_to_air {
            let running = (status ?? "").lowercased().contains("returning")
            return EpisodeBadge(label: episode.label, ribbon: running ? "WEEKLY" : "NEW")
        }
        return nil
    }
}

/// TMDB's 0 to 10 vote as a whole-number percentage, for the score on a poster.
public enum TMDBScore {
    public static func percent(_ vote: Double?) -> Int? {
        guard let vote, vote > 0 else { return nil }
        return min(Int((vote * 10).rounded()), 100)
    }
}
