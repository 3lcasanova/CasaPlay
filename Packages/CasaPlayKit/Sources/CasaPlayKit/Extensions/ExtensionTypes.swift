// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Terms used throughout:
//   Repository – a catalog of extensions at a URL. Installing nothing by itself.
//   Add-on     – an installed extension (today: Stremio-protocol HTTP add-ons).
//   Provider   – anything that supplies playable streams: stream-capable add-ons,
//                plus CasaPlay's built-in sources such as torrents.
// Extensions are data, never code: CasaPlay does not download and run scripts.

import Foundation

/// What an extension can do. Matches the Stremio resource names.
public enum ExtensionCapability: String, Codable, CaseIterable, Sendable {
    case catalog, meta, stream, subtitles

    public var label: String {
        switch self {
        case .catalog: return "Catalogs"
        case .meta: return "Metadata"
        case .stream: return "Streams"
        case .subtitles: return "Subtitles"
        }
    }
}

/// The extension formats CasaPlay recognises, supported or not.
public enum ExtensionFormat: String, Codable, Sendable {
    case stremioAddon
    case casaPlayRepository
    case nuvioPlugins
    case kodiRepository
    case unknown

    public var label: String {
        switch self {
        case .stremioAddon: return "Stremio add-on"
        case .casaPlayRepository: return "CasaPlay repository"
        case .nuvioPlugins: return "Nuvio plugins"
        case .kodiRepository: return "Kodi repository"
        case .unknown: return "Unknown format"
        }
    }
}

public enum Compatibility: Equatable, Codable, Sendable {
    case supported
    /// Usable, with a caveat the user should see (e.g. "needs configuration").
    case limited(String)
    case unsupported(String)

    public var isUsable: Bool {
        if case .unsupported = self { return false }
        return true
    }

    public var label: String {
        switch self {
        case .supported: return "Compatible"
        case .limited: return "Compatible with limits"
        case .unsupported: return "Not supported"
        }
    }

    public var reason: String? {
        switch self {
        case .supported: return nil
        case .limited(let r), .unsupported(let r): return r
        }
    }

    static let javascriptPlugins = Compatibility.unsupported(
        "These are JavaScript plugins. Running them means downloading and executing code, which CasaPlay doesn't do on iPhone, iPad or Apple TV (App Store guideline 2.5.2), and they need the host app's own runtime and APIs."
    )
    static let kodiAddons = Compatibility.unsupported(
        "Kodi add-ons are Python programs that use Kodi's own runtime and APIs. They can't run inside an Apple-native app."
    )
}

public enum HealthStatus: Equatable, Codable, Sendable {
    case unknown
    case ok(latencyMs: Int)
    case failing(String)

    public var label: String {
        switch self {
        case .unknown: return "Not checked yet"
        case .ok(let ms): return "Working · \(ms) ms"
        case .failing(let message): return message
        }
    }
}

public struct ExtensionHealth: Equatable, Codable, Sendable {
    public var status: HealthStatus = .unknown
    public var checkedAt: Date?
    public var consecutiveFailures = 0

    public init() {}

    /// The error message when status is `.failing`, otherwise nil.
    public var lastError: String? {
        if case .failing(let msg) = status { return msg }
        return nil
    }

    /// Alias for `checkedAt`.
    public var lastChecked: Date? { checkedAt }
}

/// Primary providers are always waited for; backups never hold up primary results.
public enum ProviderRole: String, Codable, CaseIterable, Sendable {
    case primary, backup

    public var label: String { self == .primary ? "Primary" : "Backup" }
}

/// One entry inside a repository, before installation.
public struct RepositoryEntry: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    public var version: String?
    public var summary: String?
    public var format: ExtensionFormat
    /// Where the entry's manifest lives. Nil for unsupported formats.
    public var manifestURL: URL?
    public var compatibility: Compatibility
}

public struct ExtensionRepository: Identifiable, Equatable, Codable, Sendable {
    public var id: String { url.absoluteString }
    public var url: URL
    public var name: String
    public var format: ExtensionFormat
    public var version: String?
    public var entries: [RepositoryEntry]
    public var lastRefreshed: Date?
    public var lastError: String?
}

/// An installed add-on.
public struct InstalledExtension: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var format: ExtensionFormat
    public var manifest: StremioManifest
    /// Key into the secret store for the transport URL (it may contain account tokens).
    public var secretKey: String
    /// Host only, safe to show.
    public var displaySource: String
    public var repositoryURL: URL?
    public var isEnabled: Bool
    public var role: ProviderRole
    public var priority: Int
    public var installedAt: Date
    public var updatedAt: Date
    public var availableVersion: String?
    public var health: ExtensionHealth
    public var compatibility: Compatibility

    public var name: String { manifest.name }
    public var version: String { manifest.version }
    public var capabilities: [ExtensionCapability] { manifest.capabilities }
    /// Forwards to `manifest.handles(_:type:id:)`.
    public func handles(_ resource: ExtensionCapability, type: String, id: String) -> Bool {
        manifest.handles(resource, type: type, id: id)
    }
    public var updateAvailable: Bool {
        guard let availableVersion else { return false }
        return SemanticVersion(availableVersion) > SemanticVersion(manifest.version)
    }
}

/// Lenient "1.2.10" comparison; non-numeric parts compare as 0.
public struct SemanticVersion: Comparable, Sendable {
    let parts: [Int]

    public init(_ text: String) {
        parts = text.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .prefix(4).map { Int($0) ?? 0 }
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: SemanticVersion, b: SemanticVersion) -> Bool { !(a < b) && !(b < a) }
}

/// Where transport URLs (which can carry tokens) are kept. Keychain in the app.
public protocol SecretStore: Sendable {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) -> String?
    func remove(_ key: String)
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func set(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    public func get(_ key: String) -> String? { lock.withLock { values[key] } }
    public func remove(_ key: String) { lock.withLock { _ = values.removeValue(forKey: key) } }
}

public enum ExtensionError: Error, Equatable, LocalizedError {
    case invalidURL
    case insecureURL
    case tooLarge
    case invalidManifest(String)
    case unsupported(String)
    case requestFailed(Int)
    case notFound
    case timedOut
    case duplicate

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "That address isn't a valid URL."
        case .insecureURL: return "Use an HTTPS address. Plain HTTP is only allowed for devices on your home network."
        case .tooLarge: return "The response was too large to be an extension manifest."
        case .invalidManifest(let why): return "The manifest isn't valid: \(why)."
        case .unsupported(let why): return why
        case .requestFailed(let code): return "The server answered with error \(code)."
        case .notFound: return "Nothing found."
        case .timedOut: return "No answer in time."
        case .duplicate: return "This is already installed."
        }
    }
}

enum URLPolicy {
    /// HTTPS anywhere; HTTP only for local-network hosts (a server on the user's own LAN).
    static func check(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else {
            throw ExtensionError.invalidURL
        }
        if scheme == "https" { return }
        guard scheme == "http", isLocal(host) else { throw ExtensionError.insecureURL }
    }

    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host == "127.0.0.1" { return true }
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
    }

    /// "https://host/secret-token/manifest.json" -> "host"
    static func redacted(_ url: URL) -> String { url.host ?? "unknown source" }
}
