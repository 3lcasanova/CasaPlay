// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// App-level Observable wrapper for self-hosted server providers (Plex, Jellyfin).
// Lives as a @MainActor singleton; inject via `.environment(ServerCenter.shared)`.

import SwiftUI
import CasaPlayKit

@MainActor
@Observable
final class ServerCenter {

    // MARK: - Singleton

    static let shared = ServerCenter()

    // MARK: - State

    private(set) var servers: [ServerConfig] = []
    private(set) var isBusy = false
    private(set) var lastError: String?

    // MARK: - Private

    private let secrets: KeychainSecretStore
    private let storeURL: URL

    private init() {
        self.secrets = KeychainSecretStore()
        self.storeURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CasaPlay/servers.json")
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let store = try? JSONDecoder().decode(ServerStore.self, from: data) else { return }
        servers = store.servers
    }

    private func save() {
        let store = ServerStore(servers: servers)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Add / remove

    /// Validates reachability, stores the token, then saves.
    func addServer(kind: ServerKind, name: String, urlString: String, token: String) async throws {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            throw ServerError.invalidURL
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        // Reachability check
        try await verifyConnection(kind: kind, baseURL: url, token: token)

        var config = ServerConfig(kind: kind, name: name, baseURL: url)
        // Assign priority after existing servers
        config.priority = (servers.map(\.priority).max() ?? 90) + 10
        try secrets.set(token, for: config.secretKey)
        servers.append(config)
        save()
    }

    func remove(_ id: UUID) {
        guard let idx = servers.firstIndex(where: { $0.id == id }) else { return }
        secrets.remove(servers[idx].secretKey)
        servers.remove(at: idx)
        save()
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let idx = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[idx].isEnabled = enabled
        save()
    }

    func move(_ id: UUID, by delta: Int) {
        guard let idx = servers.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = (idx + delta).clamped(to: 0..<servers.count)
        guard newIdx != idx else { return }
        let item = servers.remove(at: idx)
        servers.insert(item, at: newIdx)
        for i in servers.indices { servers[i].priority = i * 10 }
        save()
    }

    // MARK: - Providers for SourceAggregator

    /// Returns `StreamProvider` instances for all enabled servers.
    func providers() -> [any StreamProvider] {
        servers.compactMap { config in
            guard config.isEnabled, let token = secrets.get(config.secretKey) else { return nil }
            switch config.kind {
            case .plex:
                return PlexProvider(config: config, token: token)
            case .jellyfin:
                return JellyfinProvider(config: config, apiKey: token)
            }
        }
    }

    // MARK: - Verification

    private func verifyConnection(kind: ServerKind, baseURL: URL, token: String) async throws {
        // A lightweight probe: Plex → /identity, Jellyfin → /System/Info/Public
        let path: String
        var headers: [String: String]
        switch kind {
        case .plex:
            path = "/identity"
            headers = ["X-Plex-Token": token, "Accept": "application/json"]
        case .jellyfin:
            path = "/System/Info/Public"
            headers = ["Authorization": "MediaBrowser Token=\"\(token)\"",
                       "Accept": "application/json"]
        }
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url, timeoutInterval: 10)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServerError.unreachable
        }
    }
}

// MARK: - Errors

enum ServerError: LocalizedError {
    case invalidURL
    case unreachable
    case authFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid URL."
        case .unreachable: return "Couldn't reach the server. Check the address and token."
        case .authFailed: return "Authentication failed. Check your token."
        }
    }
}

// MARK: - Int clamped helper

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound - 1))
    }
}
