// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Live TV (IPTV) through Stremio add-ons. An add-on offers channel lists as catalogs of type
// "tv" (or "channel") and answers /stream/tv/{channel id}.json with the live link. This file
// decides which catalogs are channel lists, pages and filters them, and picks the links that
// CasaPlay can open. No add-on code runs here; it is all plain data.

import Foundation

public enum LiveTV {
    /// Catalog types Stremio add-ons use for live channels.
    static let liveTypes: Set<String> = ["tv", "channel", "channels", "live", "iptv", "livetv", "live_tv", "live-tv"]
    /// Types that are never channels, whatever the catalog calls itself.
    static let videoTypes: Set<String> = ["movie", "series", "anime"]
    /// Words that mark a custom-typed catalog as live TV.
    static let liveWords: Set<String> = ["tv", "live", "iptv", "channel", "channels", "livetv"]

    public static func isLiveType(_ type: String) -> Bool {
        liveTypes.contains(type.lowercased())
    }

    /// True for channel lists. Custom type names are judged by what the catalog calls itself.
    public static func isLive(_ catalog: StremioManifest.Catalog) -> Bool {
        let type = catalog.type.lowercased()
        if liveTypes.contains(type) { return true }
        if videoTypes.contains(type) { return false }
        let text = [type, catalog.id, catalog.name ?? ""].joined(separator: " ").lowercased()
        let tokens = text.split(whereSeparator: { !$0.isLetter })
        return tokens.contains { liveWords.contains(String($0)) }
    }

    /// The best picture for a channel: poster, then logo, then background. Only web addresses are
    /// used. Logos on plain HTTP are tried over HTTPS, because apps can't load plain-HTTP pictures
    /// from the internet; a home-network address stays as it is.
    public static func artworkURL(for channel: StremioMetaPreview) -> URL? {
        for text in [channel.poster, channel.logo, channel.background] {
            guard let text,
                  var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  let host = parts.host, !host.isEmpty else { continue }
            if scheme == "http" && !URLPolicy.isLocal(host) { parts.scheme = "https" }
            if let url = parts.url { return url }
        }
        return nil
    }

    /// Adds `page` to `existing`, skipping channels already listed. A page with nothing new
    /// means the add-on ignores `skip` or has run out, so the caller stops asking for more.
    public static func merge(_ existing: [StremioMetaPreview], with page: [StremioMetaPreview])
        -> (channels: [StremioMetaPreview], added: Int) {
        var seen = Set(existing.map(\.id))
        var merged = existing
        var added = 0
        for channel in page where !channel.id.isEmpty && seen.insert(channel.id).inserted {
            merged.append(channel)
            added += 1
        }
        return (merged, added)
    }

    /// Local filter for add-ons whose catalog has no server-side search.
    public static func filter(_ channels: [StremioMetaPreview], matching query: String) -> [StremioMetaPreview] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return channels }
        return channels.filter { channel in
            let haystack = [channel.name, channel.description ?? "", channel.releaseInfo ?? ""].joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    /// Playable links among `streams`, best first, without duplicates.
    public static func options(from streams: [StremioStream]) -> [LiveStreamOption] {
        var seen = Set<String>()
        var result: [LiveStreamOption] = []
        for (index, stream) in streams.prefix(50).enumerated() {
            guard let url = stream.directURL, seen.insert(url.absoluteString).inserted else { continue }
            let title = stream.liveTitle ?? "Stream \(index + 1)"
            result.append(LiveStreamOption(
                id: "\(index)", title: title, url: url,
                headers: stream.requestHeaders,
                container: MediaContainer(fileExtension: url.pathExtension)
            ))
        }
        // Adaptive (HLS) links first: Apple's player opens them without conversion.
        return result.enumerated().sorted { a, b in
            let ra = a.element.container == .hls ? 0 : 1
            let rb = b.element.container == .hls ? 0 : 1
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// True when every link is something CasaPlay can't open: YouTube, a web page or a torrent.
    public static func hasOnlyUnplayableLinks(_ streams: [StremioStream]) -> Bool {
        !streams.isEmpty && streams.allSatisfy { $0.directURL == nil }
    }
}

public struct LiveStreamOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let headers: [String: String]
    public let container: MediaContainer
}

extension StremioStream {
    /// The link, only when it is an ordinary http or https address. Plain HTTP is allowed here
    /// because most live channels are served that way; the app lets media loads use it.
    public var directURL: URL? {
        guard let text = url?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let link = URL(string: text), let scheme = link.scheme?.lowercased(),
              scheme == "http" || scheme == "https", link.host?.isEmpty == false else { return nil }
        return link
    }

    /// Request headers the add-on asks for, without hop-by-hop headers.
    public var requestHeaders: [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in behaviorHints?.proxyHeaders?.request ?? [:] where StremioStreamProvider.allowedHeader(key) {
            headers[key] = String(value.prefix(2000))
        }
        return headers
    }

    /// A short label for choosing between links: the add-on's own name or first line of its text.
    var liveTitle: String? {
        let candidates = [name, title, description].compactMap { $0 }
        for text in candidates {
            let line = text.split(whereSeparator: { $0.isNewline }).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !line.isEmpty { return String(line.prefix(80)) }
        }
        return nil
    }
}

extension StremioManifest.Catalog {
    /// What to show for this catalog: its name, or its id when it has none.
    public var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? id : trimmed
    }

    public var genreOptions: [String] {
        extra?.first { $0.name == "genre" }?.options?.filter { !$0.isEmpty } ?? []
    }

    /// A genre must be sent with every request (the catalog answers nothing without one).
    public var genreRequired: Bool {
        (extra?.contains { $0.name == "genre" && $0.isRequired == true } ?? false)
            || (extraRequired?.contains("genre") ?? false)
    }

    /// Needs an extra other than genre, such as a search term, so it can't be listed on its own.
    public var needsUnsupportedExtra: Bool {
        let required = (extra ?? []).filter { $0.isRequired == true }.map(\.name) + (extraRequired ?? [])
        return required.contains { $0 != "genre" && $0 != "skip" }
    }
}

extension StremioManifest {
    /// Channel lists this add-on offers that can be listed without typing a search.
    public var liveCatalogs: [Catalog] {
        catalogs.filter { LiveTV.isLive($0) && !$0.needsUnsupportedExtra }
    }

    /// Every catalog that can be listed on its own, for add-ons that file channels under a movie type.
    public var browsableCatalogs: [Catalog] {
        catalogs.filter { !$0.needsUnsupportedExtra }
    }

    public var hasCatalogResource: Bool {
        resources.contains { $0.name == "catalog" }
    }
}
