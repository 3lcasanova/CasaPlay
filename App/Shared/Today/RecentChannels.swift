// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The live channels you watched most recently, with what is on each right now. Home shows them as
// "Recently watched" and can start one with a single press. Saved on this device only.

import SwiftUI
import CasaPlayKit

@MainActor
@Observable
final class RecentChannels {
    static let shared = RecentChannels()

    private(set) var channels: [FavoriteChannel] = []
    /// What is on each channel now and next, by channel id.
    private(set) var guide: [String: NowNext] = [:]

    private static let key = "iptv.recentChannels"
    private static let limit = 12

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([FavoriteChannel].self, from: data) {
            channels = saved
        }
    }

    /// Puts a channel at the front of the list.
    func record(_ channel: FavoriteChannel) {
        channels.removeAll { $0.id == channel.id }
        channels.insert(channel, at: 0)
        if channels.count > Self.limit { channels.removeLast(channels.count - Self.limit) }
        if let data = try? JSONEncoder().encode(channels) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func providers() -> [String: XtreamProvider] {
        var map: [String: XtreamProvider] = [:]
        for server in ServerCenter.shared.xtreamServers() {
            map["\(XtreamLive.sourcePrefix)\(server.config.id.uuidString)"] = server.provider
        }
        return map
    }

    /// Looks up what is on the recent channels, a few at a time.
    func refreshGuide() async {
        let map = providers()
        for channel in channels.prefix(8) {
            guard let provider = map[channel.addonID] else { continue }
            if let nowNext = try? await provider.nowNext(for: channel.id) {
                guide[channel.id] = nowNext
            }
        }
    }

    /// Returns the stream URL and headers for a channel without playing it. Nil when the server is gone.
    func streamOption(for channel: FavoriteChannel) -> (url: URL, headers: [String: String])? {
        guard let provider = providers()[channel.addonID],
              let option = provider.liveOption(for: channel.id, title: channel.name) else { return nil }
        return (option.url, option.headers)
    }

    /// Starts a channel. False when its server isn't available any more.
    @discardableResult
    func play(_ channel: FavoriteChannel, app: AppState) -> Bool {
        guard let provider = providers()[channel.addonID],
              let option = provider.liveOption(for: channel.id, title: channel.name) else { return false }
        let item = MediaItem(
            id: UUID(),
            title: channel.name,
            runtimeSeconds: 0,
            file: MediaFileInfo(container: option.container, videoCodec: .h264),
            sourceName: "Live TV",
            streamURL: option.url,
            streamHeaders: option.headers.isEmpty ? nil : option.headers
        )
        app.play(item)
        record(channel)
        return true
    }
}
