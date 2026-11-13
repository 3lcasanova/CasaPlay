// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// App-level Observable wrapper around ExtensionManager.
// Lives as a @MainActor singleton injected via `.environment(ExtensionCenter.shared)`.

import SwiftUI
import CasaPlayKit

@MainActor
@Observable
final class ExtensionCenter {

    // MARK: - Singleton

    static let shared = ExtensionCenter()

    // MARK: - State (observed by the UI)

    private(set) var state: ExtensionState = ExtensionState()
    private(set) var isLoading = false
    private(set) var installError: String?
    private(set) var qualityMode: QualityMode = .preferUHD

    // MARK: - Private

    private let manager: ExtensionManager

    private init() {
        let file = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CasaPlay/extensions.json")
        manager = ExtensionManager(file: file, secrets: KeychainSecretStore())
        Task {
            await reload()
            await installStarterAddons()
        }
        // Persist quality mode across launches.
        if let raw = UserDefaults.standard.string(forKey: "qualityMode"),
           let mode = QualityMode(rawValue: raw) {
            qualityMode = mode
        }
    }

    // MARK: - Starter add-ons

    /// Add-ons that come installed. Each is installed once; removing one in the app keeps it removed.
    /// - WatchHub: Stremio's own add-on listing the legal services (Netflix, Prime Video,
    ///   Apple TV and others) a title can be watched on.
    /// - Public Domain Movies: torrents for about 500 films that are in the public domain.
    /// - OpenSubtitles v3: Stremio's subtitles add-on.
    private static let starterAddons: [(id: String, manifest: String, role: ProviderRole)] = [
        ("org.stremio.pubdomainmovies", "https://caching.stremio.net/publicdomainmovies.now.sh/manifest.json", .primary),
        ("org.stremio.watchhub", "https://watchhub.strem.io/manifest.json", .backup),
        ("org.stremio.opensubtitlesv3", "https://opensubtitles-v3.strem.io/manifest.json", .backup),
    ]

    private func installStarterAddons() async {
        let defaults = UserDefaults.standard
        for addon in Self.starterAddons {
            let doneKey = "starterAddon.installed." + addon.id
            guard !defaults.bool(forKey: doneKey) else { continue }
            if state.installed.contains(where: { $0.manifest.id == addon.id }) {
                defaults.set(true, forKey: doneKey)
                continue
            }
            guard let url = URL(string: addon.manifest) else { continue }
            // A failure (no network at first launch) is left unmarked so the next launch tries again.
            if (try? await manager.install(manifestURL: url, role: addon.role)) != nil {
                defaults.set(true, forKey: doneKey)
                await reload()
            }
        }
    }

    // MARK: - Reload

    func reload() async {
        state = await manager.state
    }

    // MARK: - Repositories

    @discardableResult
    func addRepository(_ urlString: String) async throws -> ExtensionRepository {
        let repo = try await manager.addRepository(urlString)
        await reload()
        return repo
    }

    func refreshRepository(_ url: URL) async {
        await manager.refreshRepository(url)
        await reload()
    }

    func removeRepository(_ url: URL) async {
        await manager.removeRepository(url)
        await reload()
    }

    // MARK: - Add-ons

    func install(manifestURL: URL, role: ProviderRole = .primary) async throws {
        isLoading = true
        installError = nil
        defer { isLoading = false }
        do {
            try await manager.install(manifestURL: manifestURL, role: role)
            await reload()
        } catch {
            installError = (error as? ExtensionError)?.userMessage ?? error.localizedDescription
            throw error
        }
    }

    func setEnabled(_ id: String, _ enabled: Bool) async {
        await manager.setEnabled(id, enabled)
        await reload()
    }

    func setRole(_ id: String, _ role: ProviderRole) async {
        await manager.setRole(id, role)
        await reload()
    }

    func move(_ id: String, by delta: Int) async {
        await manager.move(id, by: delta)
        await reload()
    }

    func remove(_ id: String) async {
        await manager.remove(id)
        await reload()
    }

    func checkForUpdates() async {
        await manager.checkForUpdates()
        await reload()
    }

    func update(_ id: String) async throws {
        try await manager.update(id)
        await reload()
    }

    // MARK: - Quality mode

    func setQualityMode(_ mode: QualityMode) {
        qualityMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "qualityMode")
    }

    // MARK: - Stremio client for a given add-on

    func client(for addon: InstalledExtension) async -> StremioClient? {
        await manager.client(for: addon)
    }

    // MARK: - Providers for SourceAggregator

    /// Returns providers from all enabled add-ons that handle the given type.
    func providers(for type: String, id: String) async -> [any StreamProvider] {
        let addons = await manager.enabledAddons
        var providers: [any StreamProvider] = []
        for addon in addons {
            guard addon.handles(.stream, type: type, id: id),
                  let c = await manager.client(for: addon) else { continue }
            providers.append(StremioStreamProvider(installed: addon, client: c))
        }
        return providers
    }

    // MARK: - Subtitles from add-ons

    func subtitles(type: String, id: String) async -> [StremioSubtitle] {
        let addons = await manager.enabledAddons
        var subs: [StremioSubtitle] = []
        for addon in addons where addon.handles(.subtitles, type: type, id: id) {
            guard let c = await manager.client(for: addon) else { continue }
            if let batch = try? await c.subtitles(type: type, id: id) {
                subs.append(contentsOf: batch)
            }
        }
        return subs
    }
}

// MARK: - User-readable error messages

private extension ExtensionError {
    var userMessage: String {
        switch self {
        case .invalidURL: return "The URL is not valid."
        case .insecureURL: return "Only HTTPS add-ons are accepted (HTTP is allowed on your home network)."
        case .tooLarge: return "The manifest file is too large."
        case .invalidManifest(let r): return "Invalid manifest: \(r)"
        case .unsupported(let r): return "Not supported: \(r)"
        case .requestFailed(let c): return "Network error (HTTP \(c))."
        case .notFound: return "The add-on could not be reached (404)."
        case .timedOut: return "The connection timed out. Try again."
        case .duplicate: return "This add-on is already installed."
        }
    }
}

// MARK: - QualityMode Codable key

private extension QualityMode {
    var rawValue: String {
        switch self {
        case .preferUHD: return "preferUHD"
        case .uhdOnly: return "uhdOnly"
        case .allowFHDFallback: return "allowFHDFallback"
        case .fhdOnly: return "fhdOnly"
        case .hd720Only: return "hd720Only"
        case .sdOnly: return "sdOnly"
        }
    }
    init?(rawValue: String) {
        switch rawValue {
        case "preferUHD": self = .preferUHD
        case "uhdOnly": self = .uhdOnly
        case "allowFHDFallback": self = .allowFHDFallback
        case "fhdOnly": self = .fhdOnly
        case "hd720Only": self = .hd720Only
        case "sdOnly": self = .sdOnly
        default: return nil
        }
    }
}
