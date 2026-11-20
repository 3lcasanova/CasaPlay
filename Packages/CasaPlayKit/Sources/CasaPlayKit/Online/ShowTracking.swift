// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// What to say about a show you follow: the episode that just came out, and the next one with its date.
// All the date maths is here so it can be tested without a screen.

import Foundation

public struct ShowTracking: Equatable, Sendable {
    public let status: String?
    public let next: TMDBEpisodeStub?
    public let nextDate: Date?
    public let nextDays: Int?
    public let last: TMDBEpisodeStub?
    public let lastDays: Int?

    public init(status: String?, next: TMDBEpisodeStub?, nextDate: Date?, nextDays: Int?,
                last: TMDBEpisodeStub?, lastDays: Int?) {
        self.status = status
        self.next = next
        self.nextDate = nextDate
        self.nextDays = nextDays
        self.last = last
        self.lastDays = lastDays
    }

    /// An episode came out today or in the last two weeks.
    public var hasNewEpisode: Bool {
        guard let lastDays else { return false }
        return lastDays <= 0 && lastDays >= -14
    }

    /// "S02 E06 · in 3 days". Nil when no next episode is known.
    public var nextText: String? {
        guard let next, let nextDays, nextDays >= 0 else { return nil }
        let label = next.label ?? "Next episode"
        switch nextDays {
        case 0: return "\(label) · today"
        case 1: return "\(label) · tomorrow"
        case 2...6: return "\(label) · in \(nextDays) days"
        default:
            guard let nextDate else { return label }
            return "\(label) · \(Self.dateText(nextDate))"
        }
    }

    /// "S02 E05 · 2 days ago". Nil when the latest episode is older than two weeks or unknown.
    public var latestText: String? {
        guard hasNewEpisode, let last, let lastDays else { return nil }
        let label = last.label ?? "New episode"
        switch lastDays {
        case 0: return "\(label) · today"
        case -1: return "\(label) · yesterday"
        default: return "\(label) · \(-lastDays) days ago"
        }
    }

    /// Soonest first for sorting a follow list: a new episode, then the next air date, then the rest.
    public var sortKey: Int {
        if hasNewEpisode { return -1000 + (lastDays ?? 0) }
        if let nextDays, nextDays >= 0 { return nextDays }
        return Int.max
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: date)
    }
}

extension ReleaseDates {
    /// The start of the day for a "yyyy-MM-dd" date, or nil when the text isn't a date.
    public static func date(from dateString: String?, calendar: Calendar = .current) -> Date? {
        guard let dateString, dateString.count >= 10 else { return nil }
        let parts = dateString.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}

extension TMDBShowAirInfo {
    public func tracking(now: Date = Date(), calendar: Calendar = .current) -> ShowTracking {
        ShowTracking(
            status: status,
            next: next_episode_to_air,
            nextDate: ReleaseDates.date(from: next_episode_to_air?.air_date, calendar: calendar),
            nextDays: ReleaseDates.days(until: next_episode_to_air?.air_date, now: now, calendar: calendar),
            last: last_episode_to_air,
            lastDays: ReleaseDates.days(until: last_episode_to_air?.air_date, now: now, calendar: calendar))
    }
}
