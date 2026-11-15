// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Remembers which stream a title or episode was last played from (Application Support/CasaPlay/streampicks.json),
// so Resume plays the same one without going back to the stream list.

import Foundation
import CasaPlayKit

enum StreamPickStore {
    private static let file = "streampicks.json"

    static func load() -> [String: StreamPick] {
        let list = CasaPlayStorage.load([StreamPick].self, from: file) ?? []
        return Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    static func save(_ map: [String: StreamPick]) {
        CasaPlayStorage.save(Array(map.values), to: file)
    }
}

extension AppState {
    /// Notes the stream a title was just started from. Torrents are not kept: they need a file chosen.
    func rememberStream(_ candidate: StreamCandidate, for id: MediaItem.ID) {
        guard let item = item(id: id),
              let pick = StreamPick(key: item.historyKey, candidate: candidate) else { return }
        streamPicks[item.historyKey] = pick
        StreamPickStore.save(streamPicks)
    }

    /// The stream this title was last played from, if it is one that can be started again by itself.
    func savedStream(for id: MediaItem.ID) -> StreamPick? {
        item(id: id).flatMap { streamPicks[$0.historyKey] }
    }
}
