// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Live channels from an Xtream Codes login, shaped like an add-on channel list so the
// Live TV screen can show them next to add-on channels. Categories become the genre chips.

import Foundation

public enum XtreamLive {
    /// Prefix of the source id the Live TV screen uses for an Xtream server.
    public static let sourcePrefix = "xtream:"

    /// A channel-list "manifest" for one Xtream server. The categories are the genre choices
    /// (one must be picked, so the screen never loads every channel at once).
    public static func manifest(serverID: UUID, name: String, categories: [String]) -> StremioManifest? {
        var extra: [String: Any] = ["name": "genre", "isRequired": true]
        if !categories.isEmpty { extra["options"] = categories }
        let json: [String: Any] = [
            "id": "\(sourcePrefix)\(serverID.uuidString)",
            "version": "1.0.0",
            "name": name,
            "resources": ["catalog"],
            "types": ["tv"],
            "catalogs": [["type": "tv", "id": "xtream-live", "name": "Live TV", "extra": [extra]]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(StremioManifest.self, from: data)
    }
}

extension XtreamProvider {
    /// Live category names, in the provider's order.
    public func liveCategoryNames() async throws -> [String] {
        try await cachedList("get_live_categories").compactMap { Self.text($0["category_name"]) }
    }

    /// The channels of one category (by name). Ids are "xtream:<stream_id>".
    public func liveChannels(category: String?) async throws -> [StremioMetaPreview] {
        var extra: [String: String] = [:]
        if let category {
            let cats = try await cachedList("get_live_categories")
            if let match = cats.first(where: { Self.text($0["category_name"]) == category }),
               let id = Self.text(match["category_id"]) {
                extra["category_id"] = id
            }
        }
        guard let list = try await api(action: "get_live_streams", extra: extra) as? [[String: Any]] else {
            throw XtreamError.badResponse
        }
        let items: [[String: Any]] = list.compactMap { item in
            guard let id = Self.text(item["stream_id"]), let name = Self.text(item["name"]) else { return nil }
            var out: [String: Any] = ["id": "\(XtreamLive.sourcePrefix)\(id)", "type": "tv", "name": name]
            if let icon = Self.text(item["stream_icon"]) { out["logo"] = icon }
            return out
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items) else { return [] }
        return (try? JSONDecoder().decode([StremioMetaPreview].self, from: data)) ?? []
    }

    /// The playable link of a channel listed by `liveChannels`.
    public func liveOption(for channelID: String, title: String) -> LiveStreamOption? {
        guard channelID.hasPrefix(XtreamLive.sourcePrefix) else { return nil }
        let id = String(channelID.dropFirst(XtreamLive.sourcePrefix.count))
        let base = Self.normalize(server).absoluteString
        guard let url = URL(string: "\(base)/live/\(Self.escape(login.username))/\(Self.escape(login.password))/\(id).m3u8")
        else { return nil }
        return LiveStreamOption(id: channelID, title: title, url: url, headers: [:], container: .hls)
    }
}
