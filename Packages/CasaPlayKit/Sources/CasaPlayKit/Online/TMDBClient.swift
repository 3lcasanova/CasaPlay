// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// TMDB v3 client — search movies and TV, fetch full details, build image URLs.
//
// API key is a read-access token (Bearer) stored in Secrets.xcconfig and never
// committed to git. It is injected at build time via Info.plist (key TMDBAPIKey)
// and read at runtime through ServiceKeys.tmdb.
//
// Security: responses are decoded into typed structs; no downloaded code is
// executed. The API key is only sent to api.themoviedb.org.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - TMDBClient

public struct TMDBClient {
    private static let base = URL(string: "https://api.themoviedb.org/3")!
    private static let imageBase = "https://image.tmdb.org/t/p"

    private let apiKey: String
    private let transport: HTTPTransport

    public init(apiKey: String, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }


    // MARK: - Key check

    /// TMDB hands out two credentials. The long "read access token" goes in a Bearer header.
    /// The short 32-character "API key" goes in the URL as `api_key`. Either one works here.
    static func usesBearer(_ key: String) -> Bool {
        !(key.count == 32 && key.allSatisfy(\.isHexDigit))
    }

    /// Asks TMDB for its configuration, which only succeeds with a valid key.
    public func verify() async throws {
        _ = try await get(path: "/configuration", params: [:], as: TMDBConfiguration.self)
    }

    // MARK: - Search

    public func searchMovies(query: String, year: Int? = nil) async throws -> [TMDBMovie] {
        var params: [String: String] = ["query": query, "include_adult": "false"]
        if let year { params["primary_release_year"] = "\(year)" }
        let root = try await get(path: "/search/movie", params: params, as: TMDBMoviePage.self)
        return root.results
    }

    public func searchTV(query: String) async throws -> [TMDBShow] {
        let root = try await get(path: "/search/tv",
                                 params: ["query": query, "include_adult": "false"],
                                 as: TMDBShowPage.self)
        return root.results
    }

    // MARK: - Discover

    public func trendingMovies(page: Int = 1) async throws -> [TMDBMovie] {
        try await get(path: "/trending/movie/week", params: Self.pageParams(page), as: TMDBMoviePage.self).results
    }

    public func trendingTV(page: Int = 1) async throws -> [TMDBShow] {
        try await get(path: "/trending/tv/week", params: Self.pageParams(page), as: TMDBShowPage.self).results
    }

    public func popularMovies(page: Int = 1) async throws -> [TMDBMovie] {
        try await get(path: "/movie/popular", params: Self.pageParams(page), as: TMDBMoviePage.self).results
    }

    public func topRatedMovies(page: Int = 1) async throws -> [TMDBMovie] {
        try await get(path: "/movie/top_rated", params: Self.pageParams(page), as: TMDBMoviePage.self).results
    }

    public func popularTV(page: Int = 1) async throws -> [TMDBShow] {
        try await get(path: "/tv/popular", params: Self.pageParams(page), as: TMDBShowPage.self).results
    }

    public func topRatedTV(page: Int = 1) async throws -> [TMDBShow] {
        try await get(path: "/tv/top_rated", params: Self.pageParams(page), as: TMDBShowPage.self).results
    }

    /// In cinemas now. `region` is a country code such as "CA" and picks that country's release dates.
    public func nowPlayingMovies(region: String? = nil, page: Int = 1) async throws -> [TMDBMovie] {
        try await get(path: "/movie/now_playing",
                      params: Self.regionParams(region).merging(Self.pageParams(page)) { first, _ in first },
                      as: TMDBMoviePage.self).results
    }

    /// Films that open soon.
    public func upcomingMovies(region: String? = nil, page: Int = 1) async throws -> [TMDBMovie] {
        try await get(path: "/movie/upcoming",
                      params: Self.regionParams(region).merging(Self.pageParams(page)) { first, _ in first },
                      as: TMDBMoviePage.self).results
    }

    /// Shows with an episode today.
    public func airingTodayTV(page: Int = 1) async throws -> [TMDBShow] {
        try await get(path: "/tv/airing_today", params: Self.pageParams(page), as: TMDBShowPage.self).results
    }

    /// Shows with an episode in the next week.
    public func onTheAirTV(page: Int = 1) async throws -> [TMDBShow] {
        try await get(path: "/tv/on_the_air", params: Self.pageParams(page), as: TMDBShowPage.self).results
    }

    /// Films by genre, original language and first release year. Titles with very few votes are left out.
    /// Genre IDs: 28 action, 35 comedy, 16 animation, 27 horror, 878 sci-fi. Language "ja" gives Japanese films.
    ///
    /// `provider` is a TMDB watch-provider ID (Netflix is 8) and `watchRegion` the country whose catalogue it is,
    /// which together keep only titles that stream there on a subscription.
    public func discoverMovies(
        genre: Int? = nil, language: String? = nil, fromYear: Int? = nil,
        sort: TMDBDiscoverSort = .popularity, page: Int = 1,
        provider: Int? = nil, watchRegion: String? = nil
    ) async throws -> [TMDBMovie] {
        try await get(path: "/discover/movie",
                      params: Self.discoverParams(genre: genre, language: language, fromYear: fromYear,
                                                  sort: sort, page: page, minVotes: 100,
                                                  dateKey: "primary_release_date.gte",
                                                  provider: provider, watchRegion: watchRegion),
                      as: TMDBMoviePage.self).results
    }

    /// Shows by genre, original language and first air year.
    /// Genre IDs: 10759 action and adventure, 16 animation, 35 comedy, 80 crime, 18 drama, 10765 sci-fi and fantasy.
    public func discoverTV(
        genre: Int? = nil, language: String? = nil, fromYear: Int? = nil,
        sort: TMDBDiscoverSort = .popularity, page: Int = 1,
        provider: Int? = nil, watchRegion: String? = nil
    ) async throws -> [TMDBShow] {
        try await get(path: "/discover/tv",
                      params: Self.discoverParams(genre: genre, language: language, fromYear: fromYear,
                                                  sort: sort, page: page, minVotes: 50,
                                                  dateKey: "first_air_date.gte",
                                                  provider: provider, watchRegion: watchRegion),
                      as: TMDBShowPage.self).results
    }

    static func regionParams(_ region: String?) -> [String: String] {
        guard let region = region?.trimmingCharacters(in: .whitespaces), region.count == 2 else { return [:] }
        return ["region": region.uppercased()]
    }

    static func pageParams(_ page: Int) -> [String: String] {
        ["page": "\(max(page, 1))"]
    }

    static func discoverParams(
        genre: Int?, language: String?, fromYear: Int?, sort: TMDBDiscoverSort,
        page: Int, minVotes: Int, dateKey: String,
        provider: Int? = nil, watchRegion: String? = nil
    ) -> [String: String] {
        var params: [String: String] = [
            "sort_by": sort.queryValue,
            "include_adult": "false",
            // The best rated list needs many more votes, or obscure titles with a few 10s fill it.
            "vote_count.gte": "\(sort == .rating ? minVotes * 5 : minVotes)",
            "page": "\(max(page, 1))"
        ]
        if let genre { params["with_genres"] = "\(genre)" }
        if let language, !language.isEmpty { params["with_original_language"] = language }
        if let fromYear { params[dateKey] = "\(fromYear)-01-01" }
        if let provider {
            params["with_watch_providers"] = "\(provider)"
            // Subscription catalogue only, so "Trending on Netflix" doesn't list titles that are merely for rent.
            params["with_watch_monetization_types"] = "flatrate"
            let region = watchRegion?.trimmingCharacters(in: .whitespaces) ?? ""
            params["watch_region"] = region.count == 2 ? region.uppercased() : "US"
        }
        return params
    }

    // MARK: - Detail

    public func movieDetail(id: Int) async throws -> TMDBMovieDetail {
        try await get(path: "/movie/\(id)",
                      params: ["append_to_response": "external_ids,credits"],
                      as: TMDBMovieDetail.self)
    }

    public func showDetail(id: Int) async throws -> TMDBShowDetail {
        try await get(path: "/tv/\(id)",
                      params: ["append_to_response": "external_ids,credits"],
                      as: TMDBShowDetail.self)
    }

    /// Titles viewers of this film also watch, for the "Related" shelf.
    public func recommendedMovies(id: Int, page: Int = 1) async throws -> [TMDBMovie] {
        try await get(path: "/movie/\(id)/recommendations", params: Self.pageParams(page), as: TMDBMoviePage.self).results
    }

    /// Shows viewers of this show also watch, for the "Related" shelf.
    public func recommendedTV(id: Int, page: Int = 1) async throws -> [TMDBShow] {
        try await get(path: "/tv/\(id)/recommendations", params: Self.pageParams(page), as: TMDBShowPage.self).results
    }

    // MARK: - Title logos

    /// The title of a film drawn as its logo, for the big billboard. English first, then logos with no language.
    public func titleLogoPath(movieID: Int) async throws -> String? {
        try await logoPath(at: "/movie/\(movieID)/images")
    }

    /// The title of a show drawn as its logo.
    public func titleLogoPath(showID: Int) async throws -> String? {
        try await logoPath(at: "/tv/\(showID)/images")
    }

    private func logoPath(at path: String) async throws -> String? {
        let images = try await get(path: path, params: ["include_image_language": "en,null"], as: TMDBImages.self)
        return Self.bestLogo(images.logos ?? [])
    }

    /// The best English logo, or the best one with no language when there is no English one. SVG files are skipped
    /// because the image view can't draw them.
    static func bestLogo(_ logos: [TMDBLogo]) -> String? {
        let drawable = logos.filter { !$0.file_path.lowercased().hasSuffix(".svg") }
        let english = drawable.filter { $0.iso_639_1 == "en" }
        let pool = english.isEmpty ? drawable.filter { $0.iso_639_1 == nil } : english
        return pool.max { ($0.vote_average ?? 0) < ($1.vote_average ?? 0) }?.file_path
    }

    /// A logo picture. Width: 500px.
    public static func logoURL(_ path: String) -> URL? {
        URL(string: "\(imageBase)/w500\(path)")
    }

    /// The latest and next episode of a show, for the "S01 E04" badge and the release ribbon on its poster.
    public func showAirInfo(id: Int) async throws -> TMDBShowAirInfo {
        try await get(path: "/tv/\(id)", params: [:], as: TMDBShowAirInfo.self)
    }

    public func seasonDetail(showID: Int, season: Int) async throws -> TMDBSeason {
        try await get(path: "/tv/\(showID)/season/\(season)",
                      params: [:],
                      as: TMDBSeason.self)
    }

    // MARK: - Image URLs

    /// Full URL for a poster path (e.g. "/abc123.jpg"). Width: 500px.
    public static func posterURL(_ path: String) -> URL? {
        URL(string: "\(imageBase)/w500\(path)")
    }

    /// Poster URL at a chosen width: TMDB offers 92, 154, 185, 342, 500 and 780 pixels. A big picture
    /// across a phone screen uses 780.
    public static func posterURL(_ path: String, width: Int) -> URL? {
        URL(string: "\(imageBase)/w\(width)\(path)")
    }

    /// The backdrop at its full size, usually 1920 pixels wide or more. For the big billboard on Apple TV.
    public static func originalBackdropURL(_ path: String) -> URL? {
        URL(string: "\(imageBase)/original\(path)")
    }

    /// A small backdrop, 300 pixels wide, for the soft glow behind Home on Apple TV.
    public static func smallBackdropURL(_ path: String) -> URL? {
        URL(string: "\(imageBase)/w300\(path)")
    }

    /// Full URL for a backdrop path. Width: 1280px.
    public static func backdropURL(_ path: String) -> URL? {
        URL(string: "\(imageBase)/w1280\(path)")
    }

    // MARK: - MediaItem mapping

    /// Convert a TMDB movie + its detail into a `MediaItem` ready for the library.
    public func toMediaItem(_ detail: TMDBMovieDetail) -> MediaItem {
        let imdbID = detail.external_ids?.imdb_id
        let cast = (detail.credits?.cast ?? []).prefix(10).map {
            CastMember(name: $0.name, role: $0.character, profilePath: $0.profilePath)
        }
        var item = MediaItem(
            title: detail.title,
            year: detail.releaseYear,
            kind: .movie,
            runtimeSeconds: TimeInterval((detail.runtime ?? 0) * 60),
            rating: detail.certification,
            overview: detail.overview ?? "",
            genres: detail.genres?.map(\.name) ?? [],
            file: MediaFileInfo(container: .mp4, videoCodec: .h264),
            tmdbRating: detail.vote_average,
            imdbID: imdbID,
            cast: Array(cast)
        )
        item.posterPath = detail.poster_path
        item.backdropPath = detail.backdrop_path
        item.tmdbMovieID = detail.id
        return item
    }

    public func toMediaItem(_ detail: TMDBShowDetail) -> MediaItem {
        let imdbID = detail.external_ids?.imdb_id
        let cast = (detail.credits?.cast ?? []).prefix(10).map {
            CastMember(name: $0.name, role: $0.character, profilePath: $0.profilePath)
        }
        var item = MediaItem(
            title: detail.name,
            year: detail.firstAirYear,
            kind: .movie,  // top-level show card; episodes fetched via tmdbShowID
            runtimeSeconds: 0,
            overview: detail.overview ?? "",
            genres: detail.genres?.map(\.name) ?? [],
            file: MediaFileInfo(container: .mp4, videoCodec: .h264),
            tmdbRating: detail.vote_average,
            imdbID: imdbID,
            cast: Array(cast),
            tmdbShowID: detail.id,
            numberOfSeasons: detail.number_of_seasons
        )
        item.posterPath = detail.poster_path
        item.backdropPath = detail.backdrop_path
        return item
    }

    // MARK: - HTTP

    private func get<T: Decodable>(path: String, params: [String: String], as _: T.Type) async throws -> T {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        var items = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        let bearer = Self.usesBearer(apiKey)
        if !bearer { items.append(URLQueryItem(name: "api_key", value: apiKey)) }
        comps.queryItems = items
        guard let url = comps.url else { throw TMDBError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        if bearer { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(req)
        guard (200..<300).contains(response.status) else {
            if response.status == 401 { throw TMDBError.unauthorized }
            throw TMDBError.httpError(response.status)
        }
        return try JSONDecoder().decode(T.self, from: response.body)
    }
}

// MARK: - Errors

public enum TMDBError: Error, LocalizedError {
    case badURL
    case unauthorized
    case httpError(Int)

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid TMDB request URL."
        case .unauthorized: return "TMDB refused the key. Check it in Profile › Online services."
        case .httpError(let code): return "TMDB returned HTTP \(code)."
        }
    }
}

// MARK: - JSON models

/// Only used to check that a key works.
/// How a discover list is ordered.
public enum TMDBDiscoverSort: Sendable {
    case popularity, rating

    var queryValue: String { self == .rating ? "vote_average.desc" : "popularity.desc" }
}

public struct TMDBConfiguration: Decodable, Sendable {
    public let change_keys: [String]?
}

public struct TMDBMovie: Decodable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let release_date: String?
    public let poster_path: String?
    public let backdrop_path: String?
    public let overview: String?
    public let vote_average: Double?

    public var releaseYear: Int? {
        guard let d = release_date, d.count >= 4 else { return nil }
        return Int(d.prefix(4))
    }
}

public struct TMDBShow: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let first_air_date: String?
    public let poster_path: String?
    public let backdrop_path: String?
    public let overview: String?
    public let vote_average: Double?

    public var firstAirYear: Int? {
        guard let d = first_air_date, d.count >= 4 else { return nil }
        return Int(d.prefix(4))
    }
}

private struct TMDBMoviePage: Decodable {
    let results: [TMDBMovie]
}

private struct TMDBShowPage: Decodable {
    let results: [TMDBShow]
}

public struct TMDBMovieDetail: Decodable, Sendable {
    public let id: Int
    public let title: String
    public let overview: String?
    public let release_date: String?
    public let runtime: Int?
    public let vote_average: Double?
    public let poster_path: String?
    public let backdrop_path: String?
    public let genres: [TMDBGenre]?
    public let external_ids: TMDBExternalIDs?
    public let credits: TMDBCredits?

    public var releaseYear: Int? {
        guard let d = release_date, d.count >= 4 else { return nil }
        return Int(d.prefix(4))
    }

    // US certification is not in the basic response; callers may set this manually.
    public var certification: String? { nil }
}

public struct TMDBShowDetail: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let first_air_date: String?
    public let vote_average: Double?
    public let poster_path: String?
    public let backdrop_path: String?
    public let genres: [TMDBGenre]?
    public let external_ids: TMDBExternalIDs?
    public let credits: TMDBCredits?
    public let number_of_seasons: Int?

    public var firstAirYear: Int? {
        guard let d = first_air_date, d.count >= 4 else { return nil }
        return Int(d.prefix(4))
    }
}

public struct TMDBSeason: Decodable, Sendable {
    public let season_number: Int
    public let name: String?
    public let episodes: [TMDBEpisode]?
}

public struct TMDBEpisode: Decodable, Identifiable, Sendable {
    public let id: Int
    public let episode_number: Int
    public let season_number: Int
    public let name: String
    public let overview: String?
    public let still_path: String?
    public let runtime: Int?
    public let vote_average: Double?
    public let air_date: String?
}

public struct TMDBGenre: Decodable, Sendable {
    public let id: Int
    public let name: String
}

public struct TMDBExternalIDs: Decodable, Sendable {
    public let imdb_id: String?
}

public struct TMDBCredits: Decodable, Sendable {
    public let cast: [TMDBCastMember]?
}

public struct TMDBCastMember: Decodable, Sendable {
    public let name: String
    public let character: String
    public let profilePath: String?

    private enum CodingKeys: String, CodingKey {
        case name, character
        case profilePath = "profile_path"
    }
}

/// The pictures TMDB has for a title. Only the logos are used.
struct TMDBImages: Decodable {
    let logos: [TMDBLogo]?
}

struct TMDBLogo: Decodable {
    let file_path: String
    let iso_639_1: String?
    let vote_average: Double?
}
