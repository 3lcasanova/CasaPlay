// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Persists per-title watch state to Application Support/CasaPlay/watchhistory.json,
// and titles added from Search to library.json.

import Foundation
import CasaPlayKit

extension MediaItem {
    /// Stable across launches, unlike `id`, which sample titles regenerate each run.
    var historyKey: String {
        if let imdbID, !imdbID.isEmpty { return imdbID }
        return "\(title.lowercased())|\(year ?? 0)"
    }
}

struct WatchRecord: Codable {
    var key: String
    var progressSeconds: TimeInterval
    var isWatched: Bool
    var isFavorite: Bool
    var lastPlayedAt: Date?
}

enum CasaPlayStorage {
    static func url(_ filename: String) -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CasaPlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        guard let data = try? Data(contentsOf: url(filename)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to filename: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(filename), options: .atomicWrite)
    }
}

enum WatchHistory {
    private static let file = "watchhistory.json"

    static func load() -> [String: WatchRecord] {
        let records = CasaPlayStorage.load([WatchRecord].self, from: file) ?? []
        return Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    static func save(_ map: [String: WatchRecord]) {
        CasaPlayStorage.save(Array(map.values), to: file)
    }

    static func apply(_ map: [String: WatchRecord], to items: inout [MediaItem]) {
        for i in items.indices {
            guard let rec = map[items[i].historyKey] else { continue }
            items[i].progressSeconds = rec.progressSeconds
            items[i].isWatched = rec.isWatched
            items[i].isFavorite = rec.isFavorite
            items[i].lastPlayedAt = rec.lastPlayedAt
        }
    }
}

enum LibraryStore {
    private static let file = "library.json"

    static func load() -> [MediaItem] {
        CasaPlayStorage.load([MediaItem].self, from: file) ?? []
    }

    static func save(_ items: [MediaItem]) {
        CasaPlayStorage.save(items, to: file)
    }
}
