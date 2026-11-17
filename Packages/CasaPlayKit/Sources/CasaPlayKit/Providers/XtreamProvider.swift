// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Xtream Codes login (server + username + password). Movies and series come from the provider's
// player_api.php and are matched to CasaPlay titles by name and year. The login is kept in the
// Keychain; the saved server list holds only the server address.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Xtream username and password, stored together in the Keychain.
public struct XtreamLogin: Equatable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    public init(stored: String) {
        if let data = stored.data(using: .utf8),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            username = saved.u
            password = saved.p
        } else {
            username = ""
            password = ""
        }
    }

    public var stored: String {
        guard let data = try? JSONEncoder().encode(Saved(u: username, p: password)),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private struct Saved: Codable { let u: String; let p: String }
}

public enum XtreamError: LocalizedError, Equatable {
    case badServerURL, missingLogin, authFailed, badResponse
    public var errorDescription: String? {
        switch self {
        case .badServerURL: return "Enter only the server address, like https://example.com. Put the username and password in their own fields."
        case .missingLogin: return "Enter your Xtream username and password."
        case .authFailed: return "The server refused this username and password."
        case .badResponse: return "The server did not answer like an Xtream Codes server."
        }
    }
}

public struct XtreamProvider: StreamProvider {
    public let providerID: String
    public let name: String
    public let role: ProviderRole = .primary
    public let priority: Int
    let server: URL
    let login: XtreamLogin
    private let transport: HTTPTransport

    public init(config: ServerConfig, login stored: String,
                transport: HTTPTransport = URLSessionTransport()) {
        providerID = "xtream:\(config.id)"
        name = config.name
        priority = config.priority
        server = config.baseURL
        login = XtreamLogin(stored: stored)
        self.transport = transport
    }

    /// Only a plain server address: no user:password@, no query, no player_api.php path.
    public static func validateURL(_ url: URL) throws {
        try URLPolicy.check(url)
        guard url.user == nil, url.password == nil, url.query == nil,
              !url.path.lowercased().hasSuffix(".php") else { throw XtreamError.badServerURL }
    }

    /// Strips a trailing slash so paths can be appended.
    public static func normalize(_ url: URL) -> URL {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text) ?? url
    }

    /// Checks the login. Throws `authFailed` when the server says no.
    public func verify() async throws {
        guard !login.username.isEmpty, !login.password.isEmpty else { throw XtreamError.missingLogin }
        let json = try await api(action: nil)
        guard let dict = json as? [String: Any], let info = dict["user_info"] as? [String: Any] else {
            throw XtreamError.badResponse
        }
        guard Self.text(info["auth"]) == "1" else { throw XtreamError.authFailed }
    }

    /// How many movies and shows the provider offers, to show the login works.
    public func libraryCount() async throws -> (movies: Int, shows: Int) {
        let movies = try await cachedList("get_vod_streams").count
        let shows = try await cachedList("get_series").count
        return (movies, shows)
    }

    public func streams(for request: ContentRequest) async throws -> [StreamCandidate] {
        switch request.kind {
        case .movie:
            let list = try await cachedList("get_vod_streams")
            return list.filter { Self.matches($0, title: request.title, year: request.year) }
                .compactMap { item -> StreamCandidate? in
                    guard let id = Self.text(item["stream_id"]) else { return nil }
                    let ext = Self.text(item["container_extension"]) ?? "mp4"
                    let label = Self.text(item["name"]) ?? request.title
                    return candidate(path: "movie", id: id, ext: ext, label: label)
                }
        case .episode:
            guard let season = request.season, let episode = request.episode else { return [] }
            let shows = try await cachedList("get_series")
                .filter { Self.matches($0, title: request.title, year: request.year) }
            var out: [StreamCandidate] = []
            for show in shows.prefix(3) {
                guard let seriesID = Self.text(show["series_id"]) else { continue }
                let json = try await api(action: "get_series_info", extra: ["series_id": seriesID])
                guard let dict = json as? [String: Any],
                      let episodes = dict["episodes"] as? [String: Any],
                      let inSeason = episodes[String(season)] as? [[String: Any]] else { continue }
                for ep in inSeason where Int(Self.text(ep["episode_num"]) ?? "") == episode {
                    guard let id = Self.text(ep["id"]) else { continue }
                    let ext = Self.text(ep["container_extension"]) ?? "mp4"
                    let label = Self.text(ep["title"]) ?? "\(request.title) S\(season)E\(episode)"
                    if let c = candidate(path: "series", id: id, ext: ext, label: label) { out.append(c) }
                }
            }
            return out
        }
    }

    // MARK: - Helpers

    private func candidate(path: String, id: String, ext: String, label: String) -> StreamCandidate? {
        let base = Self.normalize(server).absoluteString
        guard let url = URL(string: "\(base)/\(path)/\(Self.escape(login.username))/\(Self.escape(login.password))/\(id).\(ext)")
        else { return nil }
        return StreamCandidate(
            id: "\(providerID):\(path):\(id)", providerID: providerID,
            providerName: name, providerRole: role, providerPriority: priority,
            location: .http(url, headers: [:]), label: label,
            filename: nil, advertised: AdvertisedQuality.parse(label, size: nil),
            fetchedAt: Date())
    }

    func cachedList(_ action: String) async throws -> [[String: Any]] {
        let key = "\(providerID)|\(action)"
        if let hit = XtreamCache.shared.get(key) { return hit }
        guard let list = try await api(action: action) as? [[String: Any]] else { throw XtreamError.badResponse }
        XtreamCache.shared.set(key, list)
        return list
    }

    func api(action: String?, extra: [String: String] = [:]) async throws -> Any {
        try Self.validateURL(server)
        guard var parts = URLComponents(url: Self.normalize(server).appendingPathComponent("player_api.php"),
                                        resolvingAgainstBaseURL: false) else { throw XtreamError.badServerURL }
        var items = [URLQueryItem(name: "username", value: login.username),
                     URLQueryItem(name: "password", value: login.password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { items.append(URLQueryItem(name: k, value: v)) }
        parts.queryItems = items
        guard let url = parts.url else { throw XtreamError.badServerURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        if response.status == 401 || response.status == 403 { throw XtreamError.authFailed }
        guard (200..<300).contains(response.status) else { throw OnlineServiceError.badStatus(response.status) }
        guard let json = try? JSONSerialization.jsonObject(with: response.body) else { throw XtreamError.badResponse }
        return json
    }

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? s
    }

    static func text(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        if let n = value as? Int { return String(n) }
        if let n = value as? Double { return String(Int(n)) }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    // MARK: - Title matching

    static func matches(_ item: [String: Any], title: String, year: Int?) -> Bool {
        guard let raw = text(item["name"]) else { return false }
        let (name, nameYear) = clean(raw)
        guard !name.isEmpty, name == clean(title).0 else { return false }
        guard let year else { return true }
        let itemYear = nameYear
            ?? text(item["year"]).flatMap { Int($0.prefix(4)) }
            ?? text(item["releaseDate"]).flatMap { Int($0.prefix(4)) }
        guard let itemYear else { return true }
        return abs(itemYear - year) <= 1
    }

    /// "EN - The Matrix (1999) [4K]" → ("the matrix", 1999)
    static func clean(_ raw: String) -> (String, Int?) {
        var s = raw.lowercased()
        // Drop a short language/country prefix like "EN - ", "|FR| ", "4K-".
        if let r = s.range(of: #"^\s*[\|\[]?[a-z0-9]{1,4}[\|\]]?\s*[-:|]\s*"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        if let r = s.range(of: #"^\s*\|[a-z0-9 ]{1,6}\|\s*"#, options: .regularExpression) { s.removeSubrange(r) }
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        var year: Int?
        if let r = s.range(of: #"\(?\b(19|20)\d{2}\b\)?\s*$"#, options: .regularExpression) {
            year = Int(s[r].filter(\.isNumber))
            s.removeSubrange(r)
        }
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = s.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        let words = s.split(separator: " ").filter { !["4k", "uhd", "fhd", "hd", "sd", "multi", "vostfr"].contains($0) }
        return (words.joined(separator: " "), year)
    }
}

/// Short-lived cache so big VOD lists are not downloaded for every title.
final class XtreamCache: @unchecked Sendable {
    static let shared = XtreamCache()
    private let lock = NSLock()
    private var store: [String: (Date, [[String: Any]])] = [:]
    func get(_ key: String) -> [[String: Any]]? {
        lock.lock(); defer { lock.unlock() }
        guard let (at, list) = store[key], Date().timeIntervalSince(at) < 600 else { return nil }
        return list
    }
    func set(_ key: String, _ list: [[String: Any]]) {
        lock.lock(); defer { lock.unlock() }
        store[key] = (Date(), list)
    }
}
