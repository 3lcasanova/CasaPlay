// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation
import CasaPlayKit

enum ProfileStore {
    static var storeURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CasaPlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    static func save(_ profiles: [Profile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: storeURL, options: .atomicWrite)
    }
}
