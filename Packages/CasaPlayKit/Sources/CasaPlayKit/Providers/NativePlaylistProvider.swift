import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads a direct-media Extended M3U catalog in Swift. No add-on runtime or
/// Stremio endpoint is involved. A playlist is data, never executable code.
public struct NativePlaylistProvider: StreamProvider {
    public let providerID: String
    public let name: String
    public let role: ProviderRole = .primary
    public let priority: Int
    private let url: URL
    private let token: String
    private let transport: HTTPTransport

    public init(config: ServerConfig, token: String = "",
                transport: HTTPTransport = URLSessionTransport()) {
        providerID = "playlist:\(config.id)"
        name = config.name
        priority = config.priority
        // `token` is what the Keychain holds for this playlist: a plain bearer token, or the token
        // together with the query part of the link (see NativePlaylistAccess).
        let access = NativePlaylistAccess(stored: token)
        url = access.attach(to: config.baseURL)
        self.token = access.token
        self.transport = transport
    }

    /// A user name and password in front of the host are refused. A query ("?username=…&password=…")
    /// is allowed: providers hand out links like that, and the app keeps the query in the Keychain
    /// instead of the saved server list (see NativePlaylistAccess).
    public static func validateURL(_ url: URL) throws {
        try URLPolicy.check(url)
        guard url.user == nil, url.password == nil else {
            throw NativePlaylistError.credentialURL
        }
    }

    public func verify() async throws { _ = try await entries() }

    public func streams(for request: ContentRequest) async throws -> [StreamCandidate] {
        let items = try await entries()
        return items.filter { item in
            guard !request.id.isEmpty, item.contentID == request.id else { return false }
            switch request.kind {
            case .movie: return item.season == nil && item.episode == nil
            case .episode:
                guard let season = request.season, let episode = request.episode else { return false }
                return item.season == season && item.episode == episode
            }
        }.map { item in
            StreamCandidate(
                id: "\(providerID):\(item.index)", providerID: providerID,
                providerName: name, providerRole: role, providerPriority: priority,
                location: .http(item.url, headers: [:]), label: item.title,
                filename: nil, advertised: AdvertisedQuality.parse(item.title, size: nil),
                fetchedAt: Date())
        }
    }

    private func entries() async throws -> [Entry] {
        try Self.validateURL(url)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/x-mpegURL, audio/x-mpegurl, text/plain", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else { throw OnlineServiceError.badStatus(response.status) }
        return try Self.parse(response.body, relativeTo: url)
    }

    struct Entry {
        let index: Int
        let contentID: String
        let season: Int?
        let episode: Int?
        let title: String
        let url: URL
    }

    static func parse(_ data: Data, relativeTo base: URL) throws -> [Entry] {
        guard data.count <= 5 * 1024 * 1024,
              let text = String(data: data, encoding: .utf8) else { throw NativePlaylistError.invalidPlaylist }
        let lines = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first(where: { !$0.isEmpty }) == "#EXTM3U",
              !lines.contains(where: { $0.hasPrefix("#EXT-X-") }) else {
            // An HLS media/master manifest is a stream, not a catalog.
            throw NativePlaylistError.invalidPlaylist
        }
        let regex = try NSRegularExpression(pattern: #"([\w-]+)="([^"]*)""#)
        var pending: (attributes: [String: String], title: String)?
        var result: [Entry] = []
        for line in lines {
            if line.hasPrefix("#EXTINF:") {
                // A comma inside a quoted attribute is not the title separator.
                var quoted = false
                let separator = line.indices.first { index in
                    if line[index] == "\"" { quoted.toggle() }
                    return line[index] == "," && !quoted
                }
                guard let separator else { pending = nil; continue }
                let metadata = String(line[..<separator])
                var attributes: [String: String] = [:]
                for match in regex.matches(in: metadata, range: NSRange(metadata.startIndex..., in: metadata)) {
                    guard let key = Range(match.range(at: 1), in: metadata),
                          let value = Range(match.range(at: 2), in: metadata) else { continue }
                    attributes[String(metadata[key]).lowercased()] = String(metadata[value])
                }
                pending = (attributes, String(line[line.index(after: separator)...].prefix(300)))
            } else if !line.isEmpty && !line.hasPrefix("#") {
                defer { pending = nil }
                guard let item = pending, let id = item.attributes["tvg-id"], !id.isEmpty,
                      let url = URL(string: line, relativeTo: base)?.absoluteURL,
                      url.user == nil, url.password == nil, (try? URLPolicy.check(url)) != nil else { continue }
                let s = item.attributes["season"], e = item.attributes["episode"]
                // Never treat malformed episode metadata as a movie or guess absolute numbering.
                if s != nil || e != nil {
                    guard let s, let e, let season = Int(s), season >= 0,
                          let episode = Int(e), episode > 0 else { continue }
                }
                result.append(Entry(index: result.count, contentID: id,
                                    season: s.flatMap(Int.init), episode: e.flatMap(Int.init),
                                    title: item.title, url: url))
            }
        }
        guard !result.isEmpty else { throw NativePlaylistError.emptyPlaylist }
        return result
    }
}

/// What a playlist needs besides its address: an optional bearer token, and the query part of its link
/// ("username=…&password=…"), which many providers use as the login. Both are secrets, so they are kept
/// together in the Keychain, and the saved server list holds only the address without the query.
public struct NativePlaylistAccess: Equatable, Sendable {
    public var token: String
    /// Percent-encoded, without the leading "?".
    public var query: String

    public init(token: String = "", query: String = "") {
        self.token = token
        self.query = query
    }

    /// Splits the link the viewer entered into the address to save and the access to keep in the Keychain.
    public static func split(_ url: URL, token: String = "") -> (address: URL, access: NativePlaylistAccess) {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (url, NativePlaylistAccess(token: token))
        }
        let query = parts.percentEncodedQuery ?? ""
        parts.percentEncodedQuery = nil
        parts.fragment = nil
        return (parts.url ?? url, NativePlaylistAccess(token: token, query: query))
    }

    /// Reads what the Keychain holds. Anything that is not this type's own text is a plain bearer token.
    public init(stored: String) {
        if stored.hasPrefix("{"), let data = stored.data(using: .utf8),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            token = saved.t
            query = saved.q
        } else {
            token = stored
            query = ""
        }
    }

    /// The text to keep in the Keychain.
    public var stored: String {
        guard let data = try? JSONEncoder().encode(Saved(t: token, q: query)),
              let text = String(data: data, encoding: .utf8) else { return token }
        return text
    }

    /// The saved address with the query put back, ready to request.
    public func attach(to address: URL) -> URL {
        guard !query.isEmpty,
              var parts = URLComponents(url: address, resolvingAgainstBaseURL: false) else { return address }
        parts.percentEncodedQuery = query
        return parts.url ?? address
    }

    private struct Saved: Codable {
        let t: String
        let q: String
    }
}

public enum NativePlaylistError: LocalizedError {
    case credentialURL, invalidPlaylist, emptyPlaylist
    public var errorDescription: String? {
        switch self {
        case .credentialURL: return "Use a playlist link without a user name and password in front of the site name (user:password@site). A link that ends in ?username=… is fine."
        case .invalidPlaylist: return "This is not an Extended M3U catalog (maximum 5 MB). Enter the playlist URL, not an HLS video URL."
        case .emptyPlaylist: return "No usable entries found. Each entry needs a tvg-id matching the title ID and an HTTP video URL. Episodes also need season and episode attributes."
        }
    }
}
