// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Configuration for self-hosted media servers (Plex, Jellyfin).
// Auth tokens are kept in the SecretStore (Keychain); only the host is persisted here.

import Foundation

/// Which server software is running at a given address.
public enum ServerKind: String, Codable, CaseIterable, Sendable {
    case plex
    case jellyfin

    public var label: String {
        switch self {
        case .plex: return "Plex"
        case .jellyfin: return "Jellyfin"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .plex: return 32400
        case .jellyfin: return 8096
        }
    }
}

/// A saved server entry. The auth token lives in `secrets` under `secretKey`.
public struct ServerConfig: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var kind: ServerKind
    /// User-visible name, e.g. "Living Room Plex".
    public var name: String
    /// Base URL including scheme and port, e.g. "http://192.168.1.10:32400".
    public var baseURL: URL
    /// Key into the SecretStore for the auth token.
    public var secretKey: String
    /// Safe to display (host only, no token).
    public var displaySource: String { baseURL.host ?? baseURL.absoluteString }
    public var isEnabled: Bool
    /// Lower = higher priority among server providers.
    public var priority: Int
    public var addedAt: Date

    public init(id: UUID = UUID(), kind: ServerKind, name: String, baseURL: URL,
                isEnabled: Bool = true, priority: Int = 100) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.secretKey = "server.\(id.uuidString)"
        self.isEnabled = isEnabled
        self.priority = priority
        self.addedAt = Date()
    }
}

/// Persisted list of server configs.
public struct ServerStore: Codable, Sendable {
    public var servers: [ServerConfig] = []
    public init() {}
}
