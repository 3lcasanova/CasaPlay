// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// TheTVDB v4 API. Used next to TMDB for TV episodes: it backs up TMDB when TMDB has no
// episode list and fills in titles, summaries and pictures TMDB is missing.
//
// Sign-in: the project API key from thetvdb.com is exchanged for a bearer token at
// POST /login. The token lasts about a month and is kept in memory for this launch only.
// The key is only ever sent to api4.thetvdb.com.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One episode as TheTVDB describes it (aired order).
public struct TVDBEpisode: Identifiable, Hashable, Sendable {
    public var id: Int
    public var season: Int
    public var number: Int
    public var name: String
    public var overview: String?
    /// "2008-01-20"
    public var airDate: String?
    public var runtimeMinutes: Int?
    public var imageURL: URL?

    public init(
        id: Int,
        season: Int,
        number: Int,
        name: String,
        overview: String? = nil,
        airDate: String? = nil,
        runtimeMinutes: Int? = nil,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.season = season
        self.number = number
        self.name = name
        self.overview = overview
        self.airDate = airDate
        self.runtimeMinutes = runtimeMinutes
        self.imageURL = imageURL
    }
}

public struct TVDBClient: Sendable {
    public var apiKey: String
    public var transport: HTTPTransport
    public var baseURL = URL(string: "https://api4.thetvdb.com/v4/")!

    public init(apiKey: String, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }

    // MARK: Public

    /// Signs in with the key. Throws if TheTVDB refuses it.
    public func verify() async throws {
        let fresh = try await login()
        TVDBTokenCache.shared.store(fresh, for: apiKey)
    }

    /// TheTVDB's number for a show, found through its IMDb ID ("tt0903747").
    public func seriesID(imdbID: String) async throws -> Int? {
        let id = imdbID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        let data = try await get("search/remoteid/\(id)")
        return Self.parseSeriesID(data)
    }

    /// The episodes of one season, in aired order.
    public func episodes(seriesID: Int, season: Int) async throws -> [TVDBEpisode] {
        let data = try await get(
            "series/\(seriesID)/episodes/official",
            query: [URLQueryItem(name: "page", value: "0"), URLQueryItem(name: "season", value: String(season))]
        )
        return Self.parseEpisodes(data, season: season)
    }

    // MARK: Parsing

    static func parseSeriesID(_ data: Data) -> Int? {
        struct Payload: Decodable {
            struct Hit: Decodable {
                struct Series: Decodable { let id: FlexibleInt? }
                let series: Series?
            }
            let data: [Lossy<Hit>]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        for hit in payload.data ?? [] {
            if let id = hit.value?.series?.id?.value { return id }
        }
        return nil
    }

    static func parseEpisodes(_ data: Data, season: Int) -> [TVDBEpisode] {
        struct Payload: Decodable {
            struct Body: Decodable { let episodes: [Lossy<Item>]? }
            struct Item: Decodable {
                let id: Int?
                let name: String?
                let overview: String?
                let aired: String?
                let runtime: Int?
                let image: String?
                let number: Int?
                let seasonNumber: Int?
            }
            let data: Body?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        var seen = Set<Int>()
        var episodes: [TVDBEpisode] = []
        for entry in payload.data?.episodes ?? [] {
            guard let item = entry.value, let number = item.number,
                  (item.seasonNumber ?? season) == season, seen.insert(number).inserted else { continue }
            let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            episodes.append(TVDBEpisode(
                id: item.id ?? (season * 1000 + number),
                season: season,
                number: number,
                name: name.isEmpty ? "Episode \(number)" : name,
                overview: item.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
                airDate: item.aired,
                runtimeMinutes: item.runtime,
                imageURL: Self.imageURL(item.image)
            ))
        }
        return episodes.sorted { $0.number < $1.number }
    }

    /// TheTVDB sends full links; older records can send a path. Always https.
    static func imageURL(_ raw: String?) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("http://") { text = "https://" + String(text.dropFirst("http://".count)) }
        if !text.hasPrefix("https://") {
            text = "https://artworks.thetvdb.com" + (text.hasPrefix("/") ? text : "/" + text)
        }
        return URL(string: text)
    }

    // MARK: HTTP

    private func login() async throws -> String {
        guard !apiKey.isEmpty else { throw OnlineServiceError.missingAPIKey(service: "TheTVDB") }
        var request = URLRequest(url: baseURL.appendingPathComponent("login"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["apikey": apiKey])
        let response = try await transport.send(request)
        switch response.status {
        case 200: break
        case 400, 401, 403: throw OnlineServiceError.missingAPIKey(service: "TheTVDB")
        default: throw OnlineServiceError.badStatus(response.status)
        }
        struct Payload: Decodable {
            struct Body: Decodable { let token: String? }
            let data: Body?
        }
        guard let token = (try? JSONDecoder().decode(Payload.self, from: response.body))?.data?.token,
              !token.isEmpty else {
            throw OnlineServiceError.invalidResponse
        }
        return token
    }

    private func accessToken(refresh: Bool) async throws -> String {
        if !refresh, let cached = TVDBTokenCache.shared.token(for: apiKey) { return cached }
        let fresh = try await login()
        TVDBTokenCache.shared.store(fresh, for: apiKey)
        return fresh
    }

    /// GET with the bearer token. If the token was refused (expired), signs in once more and retries.
    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        for attempt in 0..<2 {
            let bearer = try await accessToken(refresh: attempt > 0)
            var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            if !query.isEmpty { components.queryItems = query }
            guard let url = components.url else { throw OnlineServiceError.invalidResponse }
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response = try await transport.send(request)
            switch response.status {
            case 200..<300: return response.body
            case 401 where attempt == 0: continue
            case 401, 403: throw OnlineServiceError.missingAPIKey(service: "TheTVDB")
            case 404: throw OnlineServiceError.notFound
            default: throw OnlineServiceError.badStatus(response.status)
            }
        }
        throw OnlineServiceError.missingAPIKey(service: "TheTVDB")
    }
}

// MARK: - Helpers

/// Keeps the sign-in token for this launch, so each screen doesn't sign in again.
final class TVDBTokenCache: @unchecked Sendable {
    static let shared = TVDBTokenCache()
    private let lock = NSLock()
    private var tokens: [String: String] = [:]

    func token(for key: String) -> String? {
        lock.withLock { tokens[key] }
    }

    func store(_ token: String, for key: String) {
        lock.withLock { tokens[key] = token }
    }
}

/// Decodes one list item and turns an unexpected shape into nil instead of failing the whole list.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// A number that TheTVDB sometimes sends as text.
struct FlexibleInt: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Int(text)
        } else {
            value = nil
        }
    }
}
