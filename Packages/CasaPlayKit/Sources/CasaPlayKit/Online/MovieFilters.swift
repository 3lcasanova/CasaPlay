// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Ways to pick a film by how you feel and how long you have: moods are sets of TMDB genres,
// lengths are runtime ranges. Both feed TMDB's discover search.

import Foundation

public enum MovieMood: String, CaseIterable, Sendable, Identifiable {
    case feelGood, edgeOfSeat, mindBending, epic, dateNight, darkGritty, cozyFamily, trueStories

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .feelGood: return "Feel-Good"
        case .edgeOfSeat: return "Edge of Your Seat"
        case .mindBending: return "Mind-Bending"
        case .epic: return "Epic Adventures"
        case .dateNight: return "Date Night"
        case .darkGritty: return "Dark & Gritty"
        case .cozyFamily: return "Cozy Family Night"
        case .trueStories: return "True Stories"
        }
    }

    /// TMDB genre IDs. A "|" between them means any of these; a "," means all of them.
    public var genreExpression: String {
        switch self {
        case .feelGood: return "35|10751|10749|10402"
        case .edgeOfSeat: return "53|27|9648"
        case .mindBending: return "878|9648|14"
        case .epic: return "12|28|10752|14"
        case .dateNight: return "10749,35"
        case .darkGritty: return "80,18"
        case .cozyFamily: return "10751|16"
        case .trueStories: return "99|36"
        }
    }
}

public enum MovieLength: String, CaseIterable, Sendable, Identifiable {
    case quick, standard, long

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quick: return "Under 90 Minutes"
        case .standard: return "90 to 120 Minutes"
        case .long: return "Over 2 Hours"
        }
    }

    public var atLeast: Int? {
        switch self {
        case .quick: return 40
        case .standard: return 90
        case .long: return 121
        }
    }

    public var atMost: Int? {
        switch self {
        case .quick: return 89
        case .standard: return 120
        case .long: return nil
        }
    }
}
