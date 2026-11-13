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
        self.apiKey = apiKey
        self.transport = transport
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

    // MARK: - Image URLs

    /// Full URL for a poster path (e.g. "/abc123.jpg"). Width: 500px.
    public static func posterURL(_ path: String) -> URL? {
        URL(string: "\(imageBase)/w500\(path)")
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
            CastMember(name: $0.name, role: $0.character)
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
        return item
    }

    public func toMediaItem(_ detail: TMDBShowDetail) -> MediaItem {
        let imdbID = detail.external_ids?.imdb_id
        let cast = (detail.credits?.cast ?? []).prefix(10).map {
            CastMember(name: $0.name, role: $0.character)
        }
        var item = MediaItem(
            title: detail.name,
            year: detail.firstAirYear,
            kind: .movie,  // top-level show card shown as movie; episodes fetched separately
            runtimeSeconds: 0,
            overview: detail.overview ?? "",
            genres: detail.genres?.map(\.name) ?? [],
            file: MediaFileInfo(container: .mp4, videoCodec: .h264),
            tmdbRating: detail.vote_average,
            imdbID: imdbID,
            cast: Array(cast)
        )
        item.posterPath = detail.poster_path
        item.backdropPath = detail.backdrop_path
        return item
    }

    // MARK: - HTTP

    private func get<T: Decodable>(path: String, params: [String: String], as _: T.Type) async throws -> T {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw TMDBError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        case .unauthorized: return "Invalid TMDB API key. Check Settings → Online Services."
        case .httpError(let code): return "TMDB returned HTTP \(code)."
        }
    }
}

// MARK: - JSON models

public struct TMDBMovie: Decodable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let release_date: String?
    public let poster_path: String?
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

    public var firstAirYear: Int? {
        guard let d = first_air_date, d.count >= 4 else { return nil }
        return Int(d.prefix(4))
    }
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
}
