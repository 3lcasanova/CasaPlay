// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// App-level Observable wrapper for self-hosted server providers (Plex, Jellyfin).
// Lives as a @MainActor singleton; inject via `.environment(ServerCenter.shared)`.

import SwiftUI
import CryptoKit
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
        var store = ServerStore()
        store.servers = servers
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        // .atomicWrite is the cross-platform name; fall back to plain write.
        let opts: Data.WritingOptions = [.atomicWrite]
        try? data.write(to: storeURL, options: opts)
    }

    // MARK: - Add / remove

    /// Validates reachability, stores the token, then saves.
    func addServer(kind: ServerKind, name: String, urlString: String, token: String) async throws {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ServerError.invalidURL
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        // A playlist link often ends in "?username=…&password=…". That part is the login, so it goes
        // into the Keychain with the token and only the address without it is saved in the server list.
        var address = url
        var secret = token
        if kind == .nativePlaylist {
            try NativePlaylistProvider.validateURL(url)
            let parts = NativePlaylistAccess.split(url, token: token)
            address = parts.address
            secret = parts.access.stored
        } else if kind == .xtream {
            try XtreamProvider.validateURL(url)
            address = XtreamProvider.normalize(url)
        }

        // Reachability check
        try await verifyConnection(kind: kind, baseURL: address, token: secret)

        var config = ServerConfig(kind: kind, name: name, baseURL: address)
        // Assign priority after existing servers
        config.priority = (servers.map(\.priority).max() ?? 90) + 10
        try secrets.set(secret, for: config.secretKey)
        servers.append(config)
        save()
    }

    /// Adds the IPTV login saved in Config/Secrets.xcconfig (Scripts/setup-xtream.sh) once, so nothing has
    /// to be typed on Apple TV. Removing it in the app keeps it removed; a failure (no network at launch) is
    /// retried on the next launch; changing the saved login swaps the server over to the new one.
    func installPersonalServers() async {
        func setting(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }
        guard let personal = PersonalXtream(server: setting("PersonalXtreamServer"),
                                            username: setting("PersonalXtreamUsername"),
                                            password: setting("PersonalXtreamPassword")) else { return }
        let fingerprint = [personal.server.absoluteString, personal.login.username, personal.login.password]
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(fingerprint.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        let doneKey = "personalXtream." + digest
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }

        let earlier = servers.first { $0.kind == .xtream && $0.baseURL == personal.server }?.id
        do {
            try await addServer(kind: .xtream, name: "IPTV", urlString: personal.server.absoluteString,
                                token: personal.login.stored)
            UserDefaults.standard.set(true, forKey: doneKey)
            if let earlier { remove(earlier) }
        } catch {
            // Left unmarked so the next launch tries again.
        }
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
            case .nativePlaylist:
                return NativePlaylistProvider(config: config, token: token)
            case .xtream:
                return XtreamProvider(config: config, login: token)
            }
        }
    }

    /// Enabled Xtream servers with their providers, for the Live TV screen.
    func xtreamServers() -> [(config: ServerConfig, provider: XtreamProvider)] {
        servers.compactMap { config in
            guard config.kind == .xtream, config.isEnabled, let login = secrets.get(config.secretKey) else { return nil }
            return (config, XtreamProvider(config: config, login: login))
        }
    }

    /// A short status line for an Xtream server, e.g. "Connected · 12,345 movies · 2,345 shows".
    func xtreamSummary(for config: ServerConfig) async -> String {
        guard config.kind == .xtream, let login = secrets.get(config.secretKey) else { return "" }
        do {
            let count = try await XtreamProvider(config: config, login: login).libraryCount()
            let f = NumberFormatter(); f.numberStyle = .decimal
            let m = f.string(from: NSNumber(value: count.movies)) ?? "\(count.movies)"
            let s = f.string(from: NSNumber(value: count.shows)) ?? "\(count.shows)"
            return "Connected · \(m) movies · \(s) shows"
        } catch {
            return "Not connected: \(error.localizedDescription)"
        }
    }

    // MARK: - Verification

    private func verifyConnection(kind: ServerKind, baseURL: URL, token: String) async throws {
        if kind == .nativePlaylist {
            let config = ServerConfig(kind: kind, name: "Playlist", baseURL: baseURL)
            try await NativePlaylistProvider(config: config, token: token).verify()
            return
        }
        if kind == .xtream {
            let config = ServerConfig(kind: kind, name: "Xtream", baseURL: baseURL)
            try await XtreamProvider(config: config, login: token).verify()
            return
        }
        // A lightweight probe: Plex → /identity, Jellyfin → /System/Info/Public
        let path: String
        var headers: [String: String]
        switch kind {
        case .nativePlaylist, .xtream:
            return
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
