// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation

public enum MediaKind: String, Codable, Sendable {
    case movie, episode
}

public struct CastMember: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var role: String

    public var profilePath: String?

    public init(name: String, role: String, profilePath: String? = nil) {
        self.name = name
        self.role = role
        self.profilePath = profilePath
    }

    public var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
    }
}

public struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var year: Int?
    public var kind: MediaKind
    public var runtimeSeconds: TimeInterval
    public var rating: String?
    public var overview: String
    public var genres: [String]
    public var file: MediaFileInfo
    public var sourceName: String
    public var collection: String?
    public var tmdbRating: Double?
    /// "tt1234567". Links to the IMDb page and is the most reliable key for subtitles.
    public var imdbID: String?
    public var imdbRating: Double?
    public var imdbVotes: Int?
    public var cast: [CastMember]
    /// Placeholder artwork colour (0...360) until real posters arrive from TMDB.
    public var artHue: Double
    /// TMDB poster path, e.g. "/abc123.jpg" — build a full URL with TMDBClient.posterURL(_:).
    public var posterPath: String?
    /// TMDB backdrop path.
    public var backdropPath: String?
    /// TMDB numeric show ID — present on TV show cards; enables episode browsing.
    public var tmdbShowID: Int?
    /// Number of seasons reported by TMDB — used to build the season picker.
    public var numberOfSeasons: Int?
    public var streamURL: URL?
    /// HTTP headers to inject when playing this item (e.g. Referer from a Stremio proxyHeaders manifest).
    public var streamHeaders: [String: String]?
    public var progressSeconds: TimeInterval
    public var isWatched: Bool
    public var isFavorite: Bool
    public var addedAt: Date
    public var lastPlayedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        year: Int? = nil,
        kind: MediaKind = .movie,
        runtimeSeconds: TimeInterval,
        rating: String? = nil,
        overview: String = "",
        genres: [String] = [],
        file: MediaFileInfo,
        sourceName: String = "",
        collection: String? = nil,
        tmdbRating: Double? = nil,
        imdbID: String? = nil,
        imdbRating: Double? = nil,
        imdbVotes: Int? = nil,
        cast: [CastMember] = [],
        artHue: Double = 30,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        tmdbShowID: Int? = nil,
        numberOfSeasons: Int? = nil,
        streamURL: URL? = nil,
        streamHeaders: [String: String]? = nil,
        progressSeconds: TimeInterval = 0,
        isWatched: Bool = false,
        isFavorite: Bool = false,
        addedAt: Date = Date(),
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.kind = kind
        self.runtimeSeconds = runtimeSeconds
        self.rating = rating
        self.overview = overview
        self.genres = genres
        self.file = file
        self.sourceName = sourceName
        self.collection = collection
        self.tmdbRating = tmdbRating
        self.imdbID = imdbID
        self.imdbRating = imdbRating
        self.imdbVotes = imdbVotes
        self.cast = cast
        self.artHue = artHue
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.tmdbShowID = tmdbShowID
        self.numberOfSeasons = numberOfSeasons
        self.streamURL = streamURL
        self.streamHeaders = streamHeaders
        self.progressSeconds = progressSeconds
        self.isWatched = isWatched
        self.isFavorite = isFavorite
        self.addedAt = addedAt
        self.lastPlayedAt = lastPlayedAt
    }

    public var progressFraction: Double {
        guard runtimeSeconds > 0 else { return 0 }
        return min(max(progressSeconds / runtimeSeconds, 0), 1)
    }

    public var remainingSeconds: TimeInterval {
        max(runtimeSeconds - progressSeconds, 0)
    }

    /// True when there is something worth resuming (more than 30 seconds in, less than 95% done).
    public var canResume: Bool {
        progressSeconds >= 30 && progressFraction < 0.95
    }

    public var imdbURL: URL? {
        imdbID.flatMap { IMDb.titleURL($0) }
    }

    public var yearText: String {
        guard let year else { return "" }
        return String(year)
    }

    /// "2025 · 2h 04m · PG-13"
    public var metaLine: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        parts.append(TimeFormat.runtime(runtimeSeconds))
        if let rating { parts.append(rating) }
        return parts.joined(separator: " · ")
    }
}
