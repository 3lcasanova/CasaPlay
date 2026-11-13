// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// magnet:?xt=urn:btih:<hash>&dn=<name>&tr=<tracker>&ws=<web seed>&xs=<.torrent URL>

import Foundation

public struct MagnetLink: Equatable, Sendable {
    public var infoHash: InfoHash
    public var displayName: String?
    public var trackers: [URL]
    public var webSeeds: [URL]
    /// "Exact source": URLs of the .torrent file itself. Its info-hash is checked before use.
    public var exactSources: [URL]

    public enum ParseError: Error, Equatable, LocalizedError {
        case notAMagnet
        case missingInfoHash
        case unsupportedHash

        public var errorDescription: String? {
            switch self {
            case .notAMagnet: return "That isn't a magnet link. It should start with \"magnet:?\"."
            case .missingInfoHash: return "The magnet link has no BitTorrent info-hash (xt=urn:btih:…)."
            case .unsupportedHash: return "Only BitTorrent v1 magnet links are supported for now."
            }
        }
    }

    public init(infoHash: InfoHash, displayName: String? = nil, trackers: [URL] = [], webSeeds: [URL] = [], exactSources: [URL] = []) {
        self.infoHash = infoHash
        self.displayName = displayName
        self.trackers = trackers
        self.webSeeds = webSeeds
        self.exactSources = exactSources
    }

    public init(parsing text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 16_384,
              trimmed.lowercased().hasPrefix("magnet:?"),
              let components = URLComponents(string: trimmed) else {
            throw ParseError.notAMagnet
        }
        var hash: InfoHash?
        var sawV2 = false
        var name: String?
        var trackers: [URL] = []
        var seeds: [URL] = []
        var sources: [URL] = []
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            switch item.name.lowercased() {
            case "xt":
                let lowered = value.lowercased()
                if lowered.hasPrefix("urn:btih:") {
                    hash = Self.decodeHash(String(value.dropFirst(9))) ?? hash
                } else if lowered.hasPrefix("urn:btmh:") {
                    sawV2 = true
                }
            case "dn": name = TorrentPaths.cleanComponent(value)
            case "tr": if let url = URL(string: value), Self.allowed(url, ["http", "https", "udp"]) { trackers.append(url) }
            case "ws": if let url = URL(string: value), Self.allowed(url, ["http", "https"]) { seeds.append(url) }
            case "xs", "as": if let url = URL(string: value), Self.allowed(url, ["https"]) { sources.append(url) }
            default: break
            }
        }
        guard let hash else { throw sawV2 ? ParseError.unsupportedHash : ParseError.missingInfoHash }
        self.init(infoHash: hash, displayName: name, trackers: trackers, webSeeds: seeds, exactSources: sources)
    }

    public var uri: String {
        var parts = ["xt=urn:btih:\(infoHash.hex)"]
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?"))
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        if let displayName { parts.append("dn=\(enc(displayName))") }
        parts += trackers.map { "tr=\(enc($0.absoluteString))" }
        parts += webSeeds.map { "ws=\(enc($0.absoluteString))" }
        parts += exactSources.map { "xs=\(enc($0.absoluteString))" }
        return "magnet:?" + parts.joined(separator: "&")
    }

    private static func allowed(_ url: URL, _ schemes: [String]) -> Bool {
        schemes.contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }

    /// 40 hex characters or 32 base32 characters.
    static func decodeHash(_ text: String) -> InfoHash? {
        if text.count == 40 { return InfoHash(hex: text) }
        guard text.count == 32 else { return nil }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0, value = 0
        var out = Data()
        for ch in text.uppercased() {
            guard let index = alphabet.firstIndex(of: ch) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return InfoHash(bytes: out)
    }
}
