// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Reads a URL the user pasted and works out what it is. Formats are told apart by
// their structure, never assumed to be interchangeable:
//   • Stremio add-on manifest   {id, version, name, resources, types, catalogs}
//   • CasaPlay repository       {name, addons: [{manifest: URL}]}  or a JSON array of manifest URLs
//   • Nuvio plugin repository   {name, version, scrapers: [{filename: "*.js", ...}]}  → unsupported
//   • Kodi repository           addons.xml                                           → unsupported

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RepositoryReader {
    public static let maxBytes = 1024 * 1024

    public static func fetch(_ url: URL, transport: HTTPTransport, timeout: TimeInterval = 20) async throws -> Data {
        try URLPolicy.check(url)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let finalRequest = request
        let response = try await withTimeout(timeout) { try await transport.send(finalRequest) }
        guard response.status == 200 else { throw ExtensionError.requestFailed(response.status) }
        guard response.body.count <= maxBytes else { throw ExtensionError.tooLarge }
        return response.body
    }

    /// Identifies the content at `url`. For a single add-on manifest the repository has one entry.
    public static func read(_ data: Data, from url: URL) -> ExtensionRepository {
        let now = Date()
        // Kodi: XML with <addons>.
        if let text = String(data: data.prefix(2048), encoding: .utf8),
           text.contains("<addons") || text.contains("<addon ") {
            return ExtensionRepository(url: url, name: url.host ?? "Kodi repository", format: .kodiRepository,
                                       entries: kodiEntries(data), lastRefreshed: now,
                                       lastError: Compatibility.kodiAddons.reason)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return ExtensionRepository(url: url, name: url.host ?? "Unknown", format: .unknown, entries: [],
                                       lastRefreshed: now, lastError: "This isn't a manifest or repository CasaPlay recognises.")
        }
        // Array of manifest URLs.
        if let list = json as? [Any] {
            let urls = list.compactMap { ($0 as? String) ?? (($0 as? [String: Any])?["manifest"] as? String) }
            return ExtensionRepository(url: url, name: url.host ?? "Repository", format: .casaPlayRepository,
                                       entries: urls.compactMap { stremioEntry($0, name: nil, relativeTo: url) },
                                       lastRefreshed: now, lastError: nil)
        }
        guard let dict = json as? [String: Any] else {
            return ExtensionRepository(url: url, name: "Unknown", format: .unknown, entries: [], lastRefreshed: now,
                                       lastError: "This isn't a manifest or repository CasaPlay recognises.")
        }
        let name = (dict["name"] as? String).map { String($0.prefix(120)) } ?? url.host ?? "Repository"
        let version = dict["version"] as? String

        // Nuvio: scraper list pointing at JavaScript files.
        if let scrapers = dict["scrapers"] as? [[String: Any]] {
            let entries = scrapers.prefix(500).map { s -> RepositoryEntry in
                RepositoryEntry(
                    id: "nuvio:" + String(((s["id"] as? String) ?? UUID().uuidString).prefix(100)),
                    name: String(((s["name"] as? String) ?? "Plugin").prefix(120)),
                    version: s["version"] as? String,
                    summary: (s["description"] as? String).map { String($0.prefix(300)) },
                    format: .nuvioPlugins,
                    manifestURL: nil,
                    compatibility: Compatibility.javascriptPlugins
                )
            }
            return ExtensionRepository(url: url, name: name, format: .nuvioPlugins, version: version,
                                       entries: Array(entries), lastRefreshed: now,
                                       lastError: Compatibility.javascriptPlugins.reason)
        }
        // CasaPlay repository.
        if let addons = dict["addons"] as? [Any] {
            let entries = addons.prefix(500).compactMap { item -> RepositoryEntry? in
                if let s = item as? String { return stremioEntry(s, name: nil, relativeTo: url) }
                guard let d = item as? [String: Any], let m = (d["manifest"] ?? d["transportUrl"]) as? String else { return nil }
                return stremioEntry(m, name: d["name"] as? String, relativeTo: url)
            }
            return ExtensionRepository(url: url, name: name, format: .casaPlayRepository, version: version,
                                       entries: entries, lastRefreshed: now, lastError: nil)
        }
        // A single Stremio manifest.
        if let manifest = try? StremioManifest.validate(data) {
            let entry = RepositoryEntry(id: manifest.id, name: manifest.name, version: manifest.version,
                                        summary: manifest.description.map { String($0.prefix(300)) },
                                        format: .stremioAddon, manifestURL: url, compatibility: manifest.compatibility)
            return ExtensionRepository(url: url, name: manifest.name, format: .stremioAddon, version: manifest.version,
                                       entries: [entry], lastRefreshed: now, lastError: nil)
        }
        return ExtensionRepository(url: url, name: name, format: .unknown, entries: [], lastRefreshed: now,
                                   lastError: "This JSON isn't a Stremio manifest or a repository CasaPlay recognises.")
    }

    private static func stremioEntry(_ text: String, name: String?, relativeTo base: URL) -> RepositoryEntry? {
        guard let url = URL(string: text, relativeTo: base)?.absoluteURL else { return nil }
        let allowed = (try? URLPolicy.check(url)) != nil
        return RepositoryEntry(
            id: url.absoluteString,
            name: name.map { String($0.prefix(120)) } ?? url.host ?? "Add-on",
            version: nil,
            summary: nil,
            format: .stremioAddon,
            manifestURL: url,
            compatibility: allowed ? .supported : .unsupported(ExtensionError.insecureURL.errorDescription ?? "")
        )
    }

    private static func kodiEntries(_ data: Data) -> [RepositoryEntry] {
        let text = String(decoding: data.prefix(maxBytes), as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: #"<addon\s[^>]*id="([^"]{1,120})"[^>]*name="([^"]{0,120})"[^>]*version="([^"]{0,40})""#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).prefix(500).compactMap { m in
            guard let id = Range(m.range(at: 1), in: text), let name = Range(m.range(at: 2), in: text),
                  let version = Range(m.range(at: 3), in: text) else { return nil }
            return RepositoryEntry(id: "kodi:" + text[id], name: String(text[name]), version: String(text[version]),
                                   summary: nil, format: .kodiRepository, manifestURL: nil, compatibility: Compatibility.kodiAddons)
        }
    }
}
