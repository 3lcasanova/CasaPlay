// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// StreamProvider for a Jellyfin Media Server.
//
// Match path:
//   Movie  — GET /Items?IncludeItemTypes=Movie&Recursive=true&AnyProviderIdEquals=imdb.{id}
//   Episode— GET /Items?IncludeItemTypes=Episode&Recursive=true&AnyProviderIdEquals=imdb.{seriesID}
//              then filter by ParentIndexNumber (season) + IndexNumber (episode)
//
// Stream URL: {baseURL}/Videos/{itemID}/stream?api_key={token}&static=true
// Subtitles:  {baseURL}/Videos/{itemID}/{itemID}/Subtitles/{index}/Stream.{format}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct JellyfinProvider: StreamProvider {
    public let providerID: String
    public let name: String
    public let role: ProviderRole
    public let priority: Int

    private let baseURL: URL
    private let apiKey: String
    private let timeout: TimeInterval
    private let transport: HTTPTransport

    // Authorization header value: "MediaBrowser Token={apiKey}"
    private var authHeader: String { "MediaBrowser Token=\"\(apiKey)\"" }

    public init(config: ServerConfig, apiKey: String,
                role: ProviderRole = .primary, timeout: TimeInterval = 15,
                transport: HTTPTransport = URLSessionTransport()) {
        self.providerID = "jellyfin:\(config.id)"
        self.name = config.name
        self.role = role
        self.priority = config.priority
        self.baseURL = config.baseURL
        self.apiKey = apiKey
        self.timeout = timeout
        self.transport = transport
    }

    // MARK: - StreamProvider

    public func streams(for request: ContentRequest) async throws -> [StreamCandidate] {
        let items: [JellyfinItem]
        switch request.kind {
        case .movie:
            items = try await search(imdbID: request.id, type: "Movie")
        case .episode:
            guard let season = request.season, let ep = request.episode else { return [] }
            let all = try await search(imdbID: request.id, type: "Episode")
            items = all.filter { $0.ParentIndexNumber == season && $0.IndexNumber == ep }
        }

        return items.compactMap { item -> StreamCandidate? in
            guard let url = streamURL(itemID: item.Id) else { return nil }
            var adv = AdvertisedQuality()
            if let w = item.Width, let h = item.Height {
                adv.resolution = ResolutionClass(width: w, height: h)
            }
            adv.sizeBytes = item.MediaSources?.first?.Size
            return StreamCandidate(
                id: "jellyfin:\(item.Id)",
                providerID: providerID,
                providerName: name,
                providerRole: role,
                providerPriority: priority,
                location: .http(url, headers: ["Authorization": authHeader]),
                label: "",
                filename: item.MediaSources?.first?.Path.map {
                    ($0 as NSString).lastPathComponent
                },
                advertised: adv,
                fetchedAt: Date()
            )
        }
    }

    // MARK: - Jellyfin API

    private func search(imdbID: String, type: String) async throws -> [JellyfinItem] {
        let path = "/Items"
        let params: [String: String] = [
            "IncludeItemTypes": type,
            "Recursive": "true",
            "AnyProviderIdEquals": "imdb.\(imdbID)",
            "Fields": "MediaSources,Width,Height",
            "Limit": "20",
        ]
        return try await jellyfinGet(path: path, params: params)
    }

    private func jellyfinGet(path: String, params: [String: String]) async throws -> [JellyfinItem] {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw JellyfinError.badURL }

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await transport.send(req)
        guard (200..<300).contains(response.status) else {
            throw JellyfinError.httpError(response.status)
        }

        let root = try JSONDecoder().decode(JellyfinItemsResponse.self, from: response.body)
        return root.Items
    }

    private func streamURL(itemID: String) -> URL? {
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(itemID)/stream"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "static", value: "true"),
        ]
        return comps.url
    }
}

// MARK: - Jellyfin JSON types

private struct JellyfinItemsResponse: Decodable {
    var Items: [JellyfinItem]
    var TotalRecordCount: Int?
}

private struct JellyfinItem: Decodable {
    var Id: String
    var Name: String?
    var IndexNumber: Int?           // episode number
    var ParentIndexNumber: Int?     // season number
    var Width: Int?
    var Height: Int?
    var MediaSources: [JellyfinMediaSource]?
}

private struct JellyfinMediaSource: Decodable {
    var Id: String?
    var Path: String?
    var Bitrate: Int?
    var Size: Int64?
}

// MARK: - JellyfinError

enum JellyfinError: Error {
    case badURL
    case badResponse
    case httpError(Int)
    case notFound
}
