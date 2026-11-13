// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Keeps repositories and installed add-ons, saves them, and checks health and updates.
// Transport URLs go to the secret store (Keychain in the app) because configured
// add-ons often carry account tokens in the URL; only the host is ever displayed.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ExtensionState: Codable, Equatable, Sendable {
    public static let currentSchema = 1
    public var schema = ExtensionState.currentSchema
    public var repositories: [ExtensionRepository] = []
    public var installed: [InstalledExtension] = []

    public init() {}
}

public actor ExtensionManager {
    private let file: URL
    private let transport: HTTPTransport
    private let secrets: SecretStore
    public private(set) var state: ExtensionState

    public init(file: URL, transport: HTTPTransport = URLSessionTransport(), secrets: SecretStore) {
        self.file = file
        self.transport = transport
        self.secrets = secrets
        self.state = Self.load(file)
    }

    /// Reads saved state. Unknown future fields are ignored; a damaged file is kept aside, not overwritten.
    static func load(_ file: URL) -> ExtensionState {
        guard let data = try? Data(contentsOf: file) else { return ExtensionState() }
        if var state = try? JSONDecoder().decode(ExtensionState.self, from: data) {
            if state.schema < ExtensionState.currentSchema { state.schema = ExtensionState.currentSchema }
            return state
        }
        let backup = file.deletingLastPathComponent().appendingPathComponent("extensions.unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: file, to: backup)
        return ExtensionState()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = file.deletingLastPathComponent().appendingPathComponent(".extensions.tmp")
        do {
            try data.write(to: temp)
            if FileManager.default.fileExists(atPath: file.path) {
                _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: file)
            }
        } catch {}
    }

    // MARK: Repositories

    /// Adds a repository or a single add-on manifest URL and lists what it contains.
    @discardableResult
    public func addRepository(_ text: String) async throws -> ExtensionRepository {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ExtensionError.invalidURL }
        try URLPolicy.check(url)
        let data = try await RepositoryReader.fetch(url, transport: transport)
        let repo = RepositoryReader.read(data, from: url)
        if repo.format == .stremioAddon {
            // A single add-on URL can carry an account token, so it isn't kept as a repository.
            // The caller installs it, and the URL then lives only in the secret store.
            return repo
        }
        state.repositories.removeAll { $0.url == url }
        state.repositories.append(repo)
        save()
        return repo
    }

    public func refreshRepository(_ url: URL) async {
        guard let index = state.repositories.firstIndex(where: { $0.url == url }) else { return }
        do {
            let data = try await RepositoryReader.fetch(url, transport: transport)
            state.repositories[index] = RepositoryReader.read(data, from: url)
        } catch {
            state.repositories[index].lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            state.repositories[index].lastRefreshed = Date()
        }
        save()
    }

    public func removeRepository(_ url: URL) {
        state.repositories.removeAll { $0.url == url }
        save()
    }

    // MARK: Add-ons

    /// Installs a Stremio add-on from its manifest URL after validating the manifest.
    @discardableResult
    public func install(manifestURL: URL, from repository: URL? = nil, role: ProviderRole = .primary) async throws -> InstalledExtension {
        let client = try StremioClient(manifestURL: manifestURL, transport: transport)
        let started = Date()
        let manifest = try await client.manifest()
        let compatibility = manifest.compatibility
        if case .unsupported(let why) = compatibility { throw ExtensionError.unsupported(why) }
        if state.installed.contains(where: { $0.manifest.id == manifest.id }) { throw ExtensionError.duplicate }
        let key = "addon." + UUID().uuidString
        try secrets.set(manifestURL.absoluteString, for: key)
        var health = ExtensionHealth()
        health.status = .ok(latencyMs: Int(Date().timeIntervalSince(started) * 1000))
        health.checkedAt = Date()
        let item = InstalledExtension(
            id: manifest.id, format: .stremioAddon, manifest: manifest, secretKey: key,
            displaySource: URLPolicy.redacted(manifestURL), repositoryURL: repository,
            isEnabled: compatibility.isUsable, role: role,
            priority: (state.installed.map(\.priority).max() ?? -1) + 1,
            installedAt: Date(), updatedAt: Date(), availableVersion: nil, health: health,
            compatibility: compatibility
        )
        state.installed.append(item)
        save()
        return item
    }

    public func setEnabled(_ id: String, _ enabled: Bool) { mutate(id) { $0.isEnabled = enabled } }
    public func setRole(_ id: String, _ role: ProviderRole) { mutate(id) { $0.role = role } }

    /// Moves an add-on up (-1) or down (+1) in priority.
    public func move(_ id: String, by delta: Int) {
        var list = state.installed.sorted { $0.priority < $1.priority }
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = min(max(i + delta, 0), list.count - 1)
        list.swapAt(i, j)
        for k in list.indices { list[k].priority = k }
        state.installed = list
        save()
    }

    public func remove(_ id: String) {
        if let item = state.installed.first(where: { $0.id == id }) { secrets.remove(item.secretKey) }
        state.installed.removeAll { $0.id == id }
        save()
    }

    /// Re-reads each manifest: records health and whether a newer version exists. Nothing is changed automatically.
    public func checkForUpdates() async {
        for item in state.installed {
            guard let client = client(for: item) else { continue }
            let started = Date()
            do {
                let manifest = try await client.manifest()
                mutate(item.id) {
                    $0.availableVersion = manifest.version
                    $0.health.status = .ok(latencyMs: Int(Date().timeIntervalSince(started) * 1000))
                    $0.health.consecutiveFailures = 0
                    $0.health.checkedAt = Date()
                }
            } catch {
                record(failure: error, for: item.id)
            }
        }
    }

    /// Applies an available update after validating the new manifest.
    public func update(_ id: String) async throws {
        guard let item = state.installed.first(where: { $0.id == id }), let client = client(for: item) else { throw ExtensionError.notFound }
        let manifest = try await client.manifest()
        guard manifest.id == item.manifest.id else { throw ExtensionError.invalidManifest("the add-on's id changed") }
        if case .unsupported(let why) = manifest.compatibility { throw ExtensionError.unsupported(why) }
        mutate(id) {
            $0.manifest = manifest
            $0.compatibility = manifest.compatibility
            $0.availableVersion = nil
            $0.updatedAt = Date()
        }
    }

    public func client(for item: InstalledExtension) -> StremioClient? {
        guard let text = secrets.get(item.secretKey), let url = URL(string: text) else { return nil }
        return try? StremioClient(manifestURL: url, transport: transport)
    }

    public func record(success latency: TimeInterval, for id: String) {
        mutate(id) {
            $0.health.status = .ok(latencyMs: Int(latency * 1000))
            $0.health.consecutiveFailures = 0
            $0.health.checkedAt = Date()
        }
    }

    public func record(failure error: Error, for id: String) {
        mutate(id) {
            $0.health.status = .failing((error as? LocalizedError)?.errorDescription ?? "Request failed.")
            $0.health.consecutiveFailures += 1
            $0.health.checkedAt = Date()
        }
    }

    public var enabledAddons: [InstalledExtension] {
        state.installed.filter { $0.isEnabled && $0.compatibility.isUsable }.sorted { $0.priority < $1.priority }
    }

    private func mutate(_ id: String, _ change: (inout InstalledExtension) -> Void) {
        guard let i = state.installed.firstIndex(where: { $0.id == id }) else { return }
        change(&state.installed[i])
        save()
    }
}
