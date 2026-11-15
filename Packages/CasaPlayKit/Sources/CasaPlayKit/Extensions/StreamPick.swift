// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The stream a title was last played from, so Resume can start the same one again without the stream list.
// The link itself is never kept (it can carry an account token): only a one-way fingerprint of it, plus the words
// the add-on used. When a title is resumed the add-ons are asked again, and the stream that matches is played.

import Foundation
import CryptoKit

public struct StreamPick: Codable, Equatable, Sendable {
    /// The title's (or the episode's) watch-history key.
    public var key: String
    public var providerID: String
    public var providerName: String
    /// A fingerprint of the link without its query, never the link.
    public var urlDigest: String?
    public var filename: String?
    /// The add-on's label with the changing seeder count taken out.
    public var labelKey: String
    public var savedAt: Date

    /// Only a web stream can be started again by itself. Torrents need their file chosen, so they return nil.
    public init?(key: String, candidate: StreamCandidate, savedAt: Date = Date()) {
        guard case .http(let url, _) = candidate.location else { return nil }
        self.key = key
        self.providerID = candidate.providerID
        self.providerName = candidate.providerName
        self.urlDigest = Self.digest(of: url)
        self.filename = candidate.filename.flatMap { $0.isEmpty ? nil : $0 }
        self.labelKey = Self.labelKey(candidate.label)
        self.savedAt = savedAt
    }

    /// 0 when this is not the same stream; higher is a surer match.
    public func score(_ candidate: StreamCandidate) -> Int {
        guard candidate.providerID == providerID, case .http(let url, _) = candidate.location else { return 0 }
        if let urlDigest, Self.digest(of: url) == urlDigest { return 3 }
        if let filename, candidate.filename == filename { return 2 }
        if !labelKey.isEmpty, Self.labelKey(candidate.label) == labelKey { return 1 }
        return 0
    }

    /// The surest match; the first one listed wins a tie, so the best-ranked stream is used.
    public func bestMatch(in candidates: [StreamCandidate]) -> StreamCandidate? {
        var best: (score: Int, candidate: StreamCandidate)?
        for candidate in candidates {
            let value = score(candidate)
            if value > (best?.score ?? 0) { best = (value, candidate) }
        }
        return best?.candidate
    }

    // MARK: Fingerprints

    static func digest(of url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.query = nil
        parts?.fragment = nil
        let text = (parts?.string ?? url.absoluteString).lowercased()
        return SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func labelKey(_ label: String) -> String {
        let peers = #"(?:👥|👤|🌱|\b(?:seeders?|seeds?|peers?)\b)\s*[:=]?\s*\d+(?:[.,]\d+)*(?:[kK]\b)?"#
        let stripped = label.replacingOccurrences(of: peers, with: "", options: [.regularExpression, .caseInsensitive])
        return stripped.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
