// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Wraps TorrentCenter's source providers as a StreamProvider for SourceAggregator.
//
// Search query:
//   Movie:   "{title} {year}"   e.g. "The Shawshank Redemption 1994"
//   Episode: "{title} S{SS}E{EE}"  e.g. "Breaking Bad S01E02"
//
// Each TorrentCandidate with a magnet link is parsed for its InfoHash and
// trackers, then returned as a StreamCandidate with a .torrent location.
// FilenameParser infers AdvertisedQuality from the torrent's title string.
//
// Security note: TorrentStreamProvider only searches sources the user has
// configured (TorrentCenter.providers). It does not add or access piracy
// indexers. Downloaded code is never executed.

import Foundation
import CasaPlayKit

struct TorrentStreamProvider: StreamProvider {
    let providerID = "builtin.torrent"
    let name = "Torrents"
    let role: ProviderRole = .backup      // Torrents fall back to direct HTTP streams
    let priority: Int

    private let sources: [any TorrentSourceProvider]

    @MainActor
    init(center: TorrentCenter, priority: Int = 500) {
        self.sources = center.providers
        self.priority = priority
    }

    // MARK: - StreamProvider

    func streams(for request: ContentRequest) async throws -> [StreamCandidate] {
        let query = searchQuery(for: request)
        // Run all torrent sources concurrently
        let results = await withTaskGroup(of: [TorrentCandidate].self) { group in
            for source in sources {
                group.addTask { (try? await source.search(query)) ?? [] }
            }
            var all: [TorrentCandidate] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }

        return results.compactMap { candidate in
            torrentCandidate(from: candidate)
        }
    }

    // MARK: - Helpers

    private func searchQuery(for request: ContentRequest) -> String {
        switch request.kind {
        case .movie:
            if let year = request.year { return "\(request.title) \(year)" }
            return request.title
        case .episode:
            guard let s = request.season, let e = request.episode else { return request.title }
            return String(format: "%@ S%02dE%02d", request.title, s, e)
        }
    }

    private func torrentCandidate(from tc: TorrentCandidate) -> StreamCandidate? {
        let location: StreamCandidate.Location
        let originalMagnet: String?
        if let magnet = tc.magnet, let (hash, trackers) = parseMagnet(magnet) {
            location = .torrent(hash, fileIndex: nil, trackers: trackers)
            originalMagnet = magnet
        } else if let torrentURL = tc.torrentURL, torrentURL.scheme?.lowercased() == "https" {
            // The info hash isn't known until the .torrent file is downloaded, which
            // happens when the user picks this stream.
            location = .torrentFile(torrentURL)
            originalMagnet = nil
        } else {
            return nil
        }

        let adv = AdvertisedQuality.parse(tc.title, size: nil)
        var candidate = StreamCandidate(
            id: "torrent:\(tc.id)",
            providerID: providerID,
            providerName: name,
            providerRole: role,
            providerPriority: priority,
            location: location,
            label: tc.title,
            filename: nil,
            advertised: adv,
            fetchedAt: Date()
        )
        candidate.originalMagnet = originalMagnet
        return candidate
    }

    // MARK: - Magnet parsing

    /// Extracts InfoHash and tracker URLs from a magnet link.
    /// Format: magnet:?xt=urn:btih:<40-char hex or 32-char base32>&tr=<url>&tr=<url>…
    private func parseMagnet(_ magnet: String) -> (InfoHash, [URL])? {
        guard let url = URL(string: magnet),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []

        // xt=urn:btih:<hash>
        guard let xt = items.first(where: { $0.name == "xt" })?.value,
              xt.lowercased().hasPrefix("urn:btih:") else { return nil }
        let hashStr = String(xt.dropFirst("urn:btih:".count))
        guard let hash = InfoHash(hex: hashStr) ?? InfoHash(base32: hashStr) else { return nil }

        // tr=<tracker url>
        let trackers = items.compactMap { item -> URL? in
            guard item.name == "tr", let v = item.value else { return nil }
            return URL(string: v)
        }
        return (hash, trackers)
    }
}

// MARK: - Base32 fallback for magnet links

private extension InfoHash {
    /// Magnet links sometimes use base32-encoded info hashes (32 chars).
    init?(base32 str: String) {
        let upper = str.uppercased()
        guard upper.count == 32, upper.allSatisfy({ "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains($0) }) else { return nil }
        var bytes = Data()
        var buffer = 0
        var bitsLeft = 0
        for c in upper {
            guard let val = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".firstIndex(of: c) else { return nil }
            let n = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".distance(from: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".startIndex, to: val)
            buffer = (buffer << 5) | n
            bitsLeft += 5
            if bitsLeft >= 8 {
                bytes.append(UInt8((buffer >> (bitsLeft - 8)) & 0xFF))
                bitsLeft -= 8
            }
        }
        self.init(bytes: bytes)
    }
}
