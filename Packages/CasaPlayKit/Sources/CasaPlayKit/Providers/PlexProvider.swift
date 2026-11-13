// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// StreamProvider for a Plex Media Server.
//
// Match path:
//   Movie  — /library/all?type=1&guid=imdb://{id}  (or fallback title search)
//   Episode— /library/all?type=4&grandparentGuid=imdb://{seriesID}
//              then filter by parentIndex (season) + index (episode)
//
// Stream URL: {baseURL}/library/parts/{partID}/file?X-Plex-Token={token}
// (direct-play; no transcoding, so quality is source quality)

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PlexProvider: StreamProvider {
    public let providerID: String
    public let name: String
    public let role: ProviderRole
    public let priority: Int

    private let baseURL: URL
    private let token: String
    private let timeout: TimeInterval
    private let transport: HTTPTransport

    public init(config: ServerConfig, token: String,
                role: ProviderRole = .primary, timeout: TimeInterval = 15,
                transport: HTTPTransport = URLSessionTransport()) {
        self.providerID = "plex:\(config.id)"
        self.name = config.name
        self.role = role
        self.priority = config.priority
        self.baseURL = config.baseURL
        self.token = token
        self.timeout = timeout
        self.transport = transport
    }

    // MARK: - StreamProvider

    public func streams(for request: ContentRequest) async throws -> [StreamCandidate] {
        let parts: [PlexPart]
        switch request.kind {
        case .movie:
            parts = try await movieParts(imdbID: request.id, title: request.title, year: request.year)
        case .episode:
            guard let season = request.season, let episode = request.episode else { return [] }
            parts = try await episodeParts(seriesIMDb: request.id, season: season, episode: episode)
        }

        return parts.map { part in
            let url = streamURL(partID: part.id)
            var adv = AdvertisedQuality()
            adv.resolution = AdvertisedQuality.resolution(fromWidth: part.width, height: part.height)
            adv.sizeBytes = part.size
            return StreamCandidate(
                id: "plex:\(part.id)",
                providerID: providerID,
                providerName: name,
                providerRole: role,
                providerPriority: priority,
                location: .http(url, headers: ["X-Plex-Token": token]),
                label: "",
                filename: part.file.isEmpty ? nil : (part.file as NSString).lastPathComponent,
                advertised: adv,
                fetchedAt: Date()
            )
        }
    }

    // MARK: - Plex API helpers

    private func movieParts(imdbID: String, title: String, year: Int?) async throws -> [PlexPart] {
        // Try GUID match first (exact)
        if let found = try? await searchByGUID("imdb://\(imdbID)", type: 1), !found.isEmpty {
            return found
        }
        // Fallback: title search, pick closest year match
        return try await searchByTitle(title, year: year, type: 1)
    }

    private func episodeParts(seriesIMDb: String, season: Int, episode: Int) async throws -> [PlexPart] {
        // Fetch episodes of the matching series
        let path = "/library/all"
        var items = try await plexGet(path: path, params: [
            "type": "4",
            "grandparentGuid": "imdb://\(seriesIMDb)",
        ])
        // Filter by season + episode
        items = items.filter { $0.parentIndex == season && $0.index == episode }
        return items.flatMap(\.parts)
    }

    private func searchByGUID(_ guid: String, type: Int) async throws -> [PlexPart] {
        let items = try await plexGet(path: "/library/all", params: [
            "type": "\(type)",
            "guid": guid,
        ])
        return items.flatMap(\.parts)
    }

    private func searchByTitle(_ title: String, year: Int?, type: Int) async throws -> [PlexPart] {
        let items = try await plexGet(path: "/library/all", params: [
            "type": "\(type)",
            "title": title,
        ])
        // Pick the best year match if year is known
        let scored = items.map { item -> (score: Int, item: PlexItem) in
            var s = 0
            if let y = year, item.year == y { s += 10 }
            s += levenshteinSimilarity(title.lowercased(), item.title.lowercased())
            return (s, item)
        }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return [] }
        return best.item.parts
    }

    // MARK: - HTTP

    private func plexGet(path: String, params: [String: String]) async throws -> [PlexItem] {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        var items = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        comps.queryItems = items

        guard let url = comps.url else { throw PlexError.badURL }

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await transport.send(req)
        guard (200..<300).contains(response.status) else {
            throw PlexError.httpError(response.status)
        }

        let root = try JSONDecoder().decode(PlexMediaContainer.self, from: response.body)
        return root.MediaContainer.Metadata ?? []
    }

    private func streamURL(partID: Int) -> URL {
        baseURL
            .appendingPathComponent("library/parts/\(partID)/file")
            .appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
    }
}

// MARK: - Plex JSON types

private struct PlexMediaContainer: Decodable {
    struct Container: Decodable {
        var Metadata: [PlexItem]?
    }
    var MediaContainer: Container
}

private struct PlexItem: Decodable {
    var title: String = ""
    var year: Int?
    var index: Int?         // episode number
    var parentIndex: Int?   // season number
    var Media: [PlexMedia]? = []

    var parts: [PlexPart] {
        (Media ?? []).flatMap { media -> [PlexPart] in
            (media.Part ?? []).map { part in
                var p = part
                if p.width == nil { p.width = media.width }
                if p.height == nil { p.height = media.height }
                return p
            }
        }
    }
}

private struct PlexMedia: Decodable {
    var videoResolution: String?
    var bitrate: Int?
    var width: Int?
    var height: Int?
    var Part: [PlexPart]?
}

private struct PlexPart: Decodable {
    var id: Int
    var file: String = ""
    var size: Int64?
    var videoResolution: String?
    var bitrate: Int?

    // These may come from the parent Media, populated at mapping time.
    var width: Int?
    var height: Int?
}

// MARK: - PlexError

enum PlexError: Error {
    case badURL
    case badResponse
    case httpError(Int)
    case notFound
}

// MARK: - Helpers

private extension AdvertisedQuality {
    static func resolution(fromWidth w: Int?, height h: Int?) -> ResolutionClass {
        guard let w, let h else { return .unknown }
        return ResolutionClass(width: w, height: h)
    }
}

// MARK: - URL helper (backport .appending(queryItems:))

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var c = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        c.queryItems = (c.queryItems ?? []) + queryItems
        return c.url ?? self
    }
}

// MARK: - Simple similarity score (0–10)

private func levenshteinSimilarity(_ a: String, _ b: String) -> Int {
    let maxLen = max(a.count, b.count)
    guard maxLen > 0 else { return 10 }
    let dist = levenshtein(a, b)
    return Int(10.0 * (1.0 - Double(dist) / Double(maxLen)))
}

private func levenshtein(_ s: String, _ t: String) -> Int {
    let s = Array(s), t = Array(t)
    let m = s.count, n = t.count
    if m == 0 { return n }; if n == 0 { return m }
    var d = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in 0...m { d[i][0] = i }
    for j in 0...n { d[0][j] = j }
    for i in 1...m {
        for j in 1...n {
            let cost = s[i-1] == t[j-1] ? 0 : 1
            d[i][j] = Swift.min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
        }
    }
    return d[m][n]
}
