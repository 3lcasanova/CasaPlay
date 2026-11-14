// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The Stremio add-on protocol: an add-on is an HTTP server with
//   GET {base}/manifest.json
//   GET {base}/catalog/{type}/{id}[/{extra}].json
//   GET {base}/meta/{type}/{id}.json
//   GET {base}/stream/{type}/{id}.json        id: "tt0111161" or "tt0944947:1:2"
//   GET {base}/subtitles/{type}/{id}.json
// Responses are plain JSON; nothing is executed.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct StremioManifest: Codable, Equatable, Sendable {
    public struct Resource: Codable, Equatable, Sendable {
        public var name: String
        public var types: [String]?
        public var idPrefixes: [String]?

        public init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
            self.name = name
            self.types = types
            self.idPrefixes = idPrefixes
        }

        public init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer().decode(String.self) {
                self.init(name: single)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try c.decode(String.self, forKey: .name),
                types: try c.decodeIfPresent([String].self, forKey: .types),
                idPrefixes: try c.decodeIfPresent([String].self, forKey: .idPrefixes)
            )
        }
    }

    public struct Catalog: Codable, Equatable, Sendable, Identifiable {
        public struct Extra: Codable, Equatable, Sendable {
            public var name: String
            public var isRequired: Bool?
            /// Values the add-on accepts, for example the genres of a "genre" extra.
            public var options: [String]?

            public init(name: String, isRequired: Bool? = nil, options: [String]? = nil) {
                self.name = name
                self.isRequired = isRequired
                self.options = options
            }

            enum CodingKeys: String, CodingKey { case name, isRequired, options }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                isRequired = (try? c.decodeIfPresent(Bool.self, forKey: .isRequired)) ?? nil
                options = (try? c.decodeIfPresent([String].self, forKey: .options)) ?? nil
            }
        }
        public var id: String
        public var type: String
        public var name: String?
        public var extra: [Extra]?
        /// Older manifests list the extras as plain names instead of `extra` objects.
        public var extraSupported: [String]?
        public var extraRequired: [String]?

        public var requiresExtra: Bool {
            (extra?.contains { $0.isRequired == true } ?? false) || !(extraRequired ?? []).isEmpty
        }
        public var supportsSearch: Bool { supports("search") }
        public var supportsSkip: Bool { supports("skip") }
        public var supportsGenre: Bool { supports("genre") }

        func supports(_ extraName: String) -> Bool {
            (extra?.contains { $0.name == extraName } ?? false)
                || (extraSupported?.contains(extraName) ?? false)
                || (extraRequired?.contains(extraName) ?? false)
        }
    }

    public struct BehaviorHints: Codable, Equatable, Sendable {
        public var configurable: Bool?
        public var configurationRequired: Bool?
        public var adult: Bool?
        public var p2p: Bool?
    }

    public var id: String
    public var version: String
    public var name: String
    public var description: String?
    public var logo: String?
    public var resources: [Resource]
    public var types: [String]
    public var catalogs: [Catalog]
    public var idPrefixes: [String]?
    public var behaviorHints: BehaviorHints?

    public var capabilities: [ExtensionCapability] {
        ExtensionCapability.allCases.filter { cap in resources.contains { $0.name == cap.rawValue } }
    }

    /// Whether this add-on claims to answer `resource` for `type` and `id`.
    public func handles(_ resource: ExtensionCapability, type: String, id: String) -> Bool {
        guard let r = resources.first(where: { $0.name == resource.rawValue }) else { return false }
        let types = r.types ?? self.types
        guard types.contains(type) else { return false }
        guard let prefixes = r.idPrefixes ?? idPrefixes, !prefixes.isEmpty else { return true }
        return prefixes.contains { id.hasPrefix($0) }
    }

    static let maxBytes = 512 * 1024

    /// Decodes and validates. Rejects anything malformed instead of guessing.
    public static func validate(_ data: Data) throws -> StremioManifest {
        guard data.count <= maxBytes else { throw ExtensionError.tooLarge }
        let manifest: StremioManifest
        do {
            manifest = try JSONDecoder().decode(StremioManifest.self, from: data)
        } catch {
            throw ExtensionError.invalidManifest("missing id, version, name, resources, types or catalogs")
        }
        func check(_ ok: Bool, _ why: String) throws { if !ok { throw ExtensionError.invalidManifest(why) } }
        try check(!manifest.id.isEmpty && manifest.id.count <= 200, "bad id")
        try check(!manifest.name.trimmingCharacters(in: .whitespaces).isEmpty && manifest.name.count <= 200, "bad name")
        try check(manifest.version.count <= 50 && manifest.version.first?.isNumber == true, "bad version")
        try check(!manifest.resources.isEmpty, "no resources")
        try check(manifest.catalogs.count <= 200, "too many catalogs")
        let known = Set(ExtensionCapability.allCases.map(\.rawValue) + ["addon_catalog"])
        try check(manifest.resources.allSatisfy { known.contains($0.name) || $0.name.count < 40 }, "bad resource")
        return manifest
    }

    public var compatibility: Compatibility {
        if behaviorHints?.configurationRequired == true {
            return .limited("This add-on must be configured on its own website first. Install the configured manifest URL it gives you.")
        }
        if capabilities.isEmpty {
            return .unsupported("It offers nothing CasaPlay uses (catalogs, metadata, streams or subtitles).")
        }
        return .supported
    }
}

// MARK: - Responses

public struct StremioStream: Codable, Equatable, Sendable {
    public struct Hints: Codable, Equatable, Sendable {
        public struct ProxyHeaders: Codable, Equatable, Sendable {
            public var request: [String: String]?
        }
        public var notWebReady: Bool?
        public var bingeGroup: String?
        public var filename: String?
        public var videoSize: Int64?
        public var proxyHeaders: ProxyHeaders?
    }
    public var url: String?
    public var ytId: String?
    public var infoHash: String?
    public var fileIdx: Int?
    public var externalUrl: String?
    public var name: String?
    public var title: String?
    public var description: String?
    public var sources: [String]?
    public var behaviorHints: Hints?

    /// Title and description text, used for advertised quality and episode checks.
    public var label: String { [name, description ?? title].compactMap { $0 }.joined(separator: "\n") }
}

public struct StremioSubtitle: Codable, Equatable, Sendable {
    public var id: String?
    public var url: String
    public var lang: String
}

public struct StremioMetaPreview: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    /// Channel logos often come as `logo` instead of `poster`.
    public var logo: String?
    public var background: String?
    public var releaseInfo: String?
    public var description: String?
    public var imdbRating: String?
}

public struct StremioVideo: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String?
    public var name: String?
    public var season: Int?
    public var episode: Int?
    public var released: String?
}

public struct StremioMeta: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    public var background: String?
    public var description: String?
    public var releaseInfo: String?
    public var year: Int?
    public var imdbRating: String?
    public var genres: [String]?
    public var runtime: String?
    public var videos: [StremioVideo]?

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, background, description, releaseInfo, year, imdbRating, genres, runtime, videos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        name = try c.decode(String.self, forKey: .name)
        poster = try c.decodeIfPresent(String.self, forKey: .poster)
        background = try c.decodeIfPresent(String.self, forKey: .background)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        releaseInfo = try c.decodeIfPresent(String.self, forKey: .releaseInfo)
        year = (try? c.decodeIfPresent(Int.self, forKey: .year)) ?? nil
        imdbRating = (try? c.decodeIfPresent(String.self, forKey: .imdbRating)) ?? nil
        genres = (try? c.decodeIfPresent([String].self, forKey: .genres)) ?? nil
        runtime = (try? c.decodeIfPresent(String.self, forKey: .runtime)) ?? nil
        videos = (try? c.decodeIfPresent([StremioVideo].self, forKey: .videos)) ?? nil
    }

    /// First year in releaseInfo ("2011–2019" -> 2011).
    public var firstYear: Int? {
        if let year { return year }
        guard let info = releaseInfo, let r = info.range(of: #"\d{4}"#, options: .regularExpression) else { return nil }
        return Int(info[r])
    }
}

// MARK: - Client

public struct StremioClient: Sendable {
    /// The add-on base URL: the manifest URL without "/manifest.json".
    public let base: URL
    public let transport: HTTPTransport
    public var maxResponseBytes = 4 * 1024 * 1024

    public init(manifestURL: URL, transport: HTTPTransport) throws {
        try URLPolicy.check(manifestURL)
        var text = manifestURL.absoluteString
        if let q = text.firstIndex(of: "?") { text = String(text[..<q]) }
        guard text.hasSuffix("/manifest.json"), let base = URL(string: String(text.dropLast("/manifest.json".count))) else {
            throw ExtensionError.invalidManifest("the URL must end in /manifest.json")
        }
        self.base = base
        self.transport = transport
    }

    public func manifest(timeout: TimeInterval = 15) async throws -> StremioManifest {
        try StremioManifest.validate(try await get(base.absoluteString + "/manifest.json", timeout: timeout))
    }

    public func streams(type: String, id: String, timeout: TimeInterval = 15) async throws -> [StremioStream] {
        struct R: Decodable { let streams: [StremioStream] }
        return try decode(R.self, try await get(path("stream", type, id), timeout: timeout)).streams
    }

    public func subtitles(type: String, id: String, timeout: TimeInterval = 15) async throws -> [StremioSubtitle] {
        struct R: Decodable { let subtitles: [StremioSubtitle] }
        return try decode(R.self, try await get(path("subtitles", type, id), timeout: timeout)).subtitles
    }

    public func meta(type: String, id: String, timeout: TimeInterval = 15) async throws -> StremioMeta {
        struct R: Decodable { let meta: StremioMeta }
        return try decode(R.self, try await get(path("meta", type, id), timeout: timeout)).meta
    }

    public func catalog(type: String, id: String, search: String? = nil, genre: String? = nil, skip: Int = 0, timeout: TimeInterval = 15) async throws -> [StremioMetaPreview] {
        struct R: Decodable { let metas: [StremioMetaPreview] }
        var extras: [String] = []
        if let genre, !genre.isEmpty { extras.append("genre=\(Self.encode(genre))") }
        if let search, !search.isEmpty { extras.append("search=\(Self.encode(search))") }
        if skip > 0 { extras.append("skip=\(skip)") }
        var url = path("catalog", type, id)
        if !extras.isEmpty { url = String(url.dropLast(5)) + "/" + extras.joined(separator: "&") + ".json" }
        return try decode(R.self, try await get(url, timeout: timeout)).metas
    }

    private func path(_ resource: String, _ type: String, _ id: String) -> String {
        "\(base.absoluteString)/\(resource)/\(Self.encode(type))/\(Self.encode(id)).json"
    }

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~:"))) ?? s
    }

    private func get(_ text: String, timeout: TimeInterval) async throws -> Data {
        guard let url = URL(string: text) else { throw ExtensionError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let finalRequest = request
        let transport = self.transport
        let response = try await withTimeout(timeout) { try await transport.send(finalRequest) }
        guard response.status == 200 else {
            throw response.status == 404 ? ExtensionError.notFound : ExtensionError.requestFailed(response.status)
        }
        guard response.body.count <= maxResponseBytes else { throw ExtensionError.tooLarge }
        return response.body
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw ExtensionError.invalidManifest("unexpected response format")
        }
    }
}

/// Runs `body`, failing with `.timedOut` after `seconds`. Cancels the body when it times out.
public func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0.001) * 1_000_000_000))
            throw ExtensionError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw ExtensionError.timedOut }
        return first
    }
}
