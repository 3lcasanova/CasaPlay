// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// IMDb IDs, links and ratings. IMDb has no free public API, so ratings come from
// OMDb (omdbapi.com), which serves IMDb's rating and vote count with a free key.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum IMDb {
    private static let idRegex = try! NSRegularExpression(pattern: #"\btt\d{7,9}\b"#, options: [])

    /// "tt1234567" with 7 to 9 digits.
    public static func isValidID(_ id: String) -> Bool {
        let range = NSRange(id.startIndex..., in: id)
        guard let match = idRegex.firstMatch(in: id, options: [], range: range) else { return false }
        return match.range == range
    }

    /// Finds an IMDb ID in a file name, folder name or .nfo text,
    /// e.g. "Night Ferry (2025) {imdb-tt1234567}" or "imdb.com/title/tt1234567/".
    public static func extractID(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = idRegex.firstMatch(in: text, options: [], range: range),
              let found = Range(match.range, in: text) else { return nil }
        return String(text[found])
    }

    public static func titleURL(_ id: String) -> URL? {
        guard isValidID(id) else { return nil }
        return URL(string: "https://www.imdb.com/title/\(id)/")
    }

    /// 7.4 -> "7.4"
    public static func ratingText(_ rating: Double) -> String {
        String(format: "%.1f", rating)
    }

    /// 1_284_000 -> "1.3M", 128_456 -> "128K", 950 -> "950"
    public static func votesText(_ votes: Int) -> String {
        switch votes {
        case 1_000_000...:
            return String(format: "%.1fM", Double(votes) / 1_000_000)
        case 1_000...:
            return "\(Int((Double(votes) / 1_000).rounded()))K"
        default:
            return "\(votes)"
        }
    }
}

public struct IMDbRating: Equatable, Sendable {
    public var imdbID: String
    public var rating: Double?
    public var votes: Int?

    public init(imdbID: String, rating: Double?, votes: Int?) {
        self.imdbID = imdbID
        self.rating = rating
        self.votes = votes
    }
}

/// Looks up IMDb ratings through OMDb. Get a free key at omdbapi.com/apikey.aspx.
public struct OMDbClient: Sendable {
    public var apiKey: String
    public var transport: HTTPTransport
    public var baseURL = URL(string: "https://www.omdbapi.com/")!

    public init(apiKey: String, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public func rating(imdbID: String) async throws -> IMDbRating {
        try await lookup([URLQueryItem(name: "i", value: imdbID)])
    }

    /// Finds a movie by title and year when no IMDb ID is known yet.
    public func rating(title: String, year: Int?) async throws -> IMDbRating {
        var items = [URLQueryItem(name: "t", value: title), URLQueryItem(name: "type", value: "movie")]
        if let year { items.append(URLQueryItem(name: "y", value: String(year))) }
        return try await lookup(items)
    }

    func request(_ items: [URLQueryItem]) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OnlineServiceError.missingAPIKey(service: "OMDb") }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = items + [URLQueryItem(name: "apikey", value: key)]
        return URLRequest(url: components.url!)
    }

    private func lookup(_ items: [URLQueryItem]) async throws -> IMDbRating {
        let response = try await transport.send(try request(items))
        if response.status == 401 { throw OnlineServiceError.missingAPIKey(service: "OMDb") }
        guard response.status == 200 else { throw OnlineServiceError.badStatus(response.status) }
        return try Self.parse(response.body)
    }

    static func parse(_ data: Data) throws -> IMDbRating {
        struct Payload: Decodable {
            let Response: String?
            let imdbID: String?
            let imdbRating: String?
            let imdbVotes: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw OnlineServiceError.invalidResponse
        }
        guard payload.Response != "False", let id = payload.imdbID else {
            throw OnlineServiceError.notFound
        }
        let rating = payload.imdbRating.flatMap { Double($0) }
        let votes = payload.imdbVotes.flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
        return IMDbRating(imdbID: id, rating: rating, votes: votes)
    }
}
