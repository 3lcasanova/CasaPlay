// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Persists per-item watch state (progress, watched flag, favourite flag)
// to ~/Library/Application Support/CasaPlay/watchhistory.json.
// Loaded once at app start and merged into app.items; written on every
// progress update, toggle-watched, and toggle-favourite.

import Foundation
import CasaPlayKit

struct WatchRecord: Codable {
    var id: UUID
    var progressSeconds: TimeInterval
    var isWatched: Bool
    var isFavorite: Bool
    var lastPlayedAt: Date?
}

struct WatchHistory {
    private static var storeURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CasaPlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("watchhistory.json")
    }()

    static func load() -> [UUID: WatchRecord] {
        guard let data = try? Data(contentsOf: storeURL),
              let records = try? JSONDecoder().decode([WatchRecord].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    static func save(_ map: [UUID: WatchRecord]) {
        let records = Array(map.values)
        guard let data = try? JSONEncoder().encode(records) else { return }
        let opts: Data.WritingOptions = [.atomicWrite]
        try? data.write(to: storeURL, options: opts)
    }

    static func apply(_ map: [UUID: WatchRecord], to items: inout [MediaItem]) {
        for i in items.indices {
            guard let rec = map[items[i].id] else { continue }
            items[i].progressSeconds = rec.progressSeconds
            items[i].isWatched = rec.isWatched
            items[i].isFavorite = rec.isFavorite
            items[i].lastPlayedAt = rec.lastPlayedAt
        }
    }
}
