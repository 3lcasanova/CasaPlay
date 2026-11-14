// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation
import CasaPlayKit

enum ProfileStore {
    private static let file = "profiles.json"
    private static let activeKey = "activeProfileID"
    private static let backupKey = "profilesBackup"

    /// Saved profiles, or the starter set saved on first launch so their IDs stay fixed.
    static func load() -> [Profile] {
        if let saved = CasaPlayStorage.load([Profile].self, from: file), !saved.isEmpty {
            return saved
        }
        // Apple TV can clear its Caches folder, so a second copy is kept in the app's settings.
        if let data = UserDefaults.standard.data(forKey: backupKey),
           let saved = try? JSONDecoder().decode([Profile].self, from: data), !saved.isEmpty {
            return saved
        }
        let starter = SampleData.profiles
        save(starter)
        return starter
    }

    static func save(_ profiles: [Profile]) {
        CasaPlayStorage.save(profiles, to: file)
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: backupKey)
        }
    }

    static func loadActiveID(in profiles: [Profile]) -> UUID {
        if let raw = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id }) {
            return id
        }
        return profiles[0].id
    }

    static func saveActiveID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeKey)
    }
}
