// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// On-disk layout, inside CasaPlay's own container only:
//   <root>/<40-hex info-hash>/data.bin     sparse file, torrent bytes at their torrent offsets
//   <root>/<40-hex info-hash>/info.torrent  metadata, so the torrent can be restored
//   <root>/<40-hex info-hash>/resume.json  verified pieces, selection and settings
// Names from the torrent are never used for paths, so a hostile torrent cannot write
// outside this folder, and nothing downloaded is ever opened or executed.

import Foundation

public struct ResumeData: Codable, Equatable, Sendable {
    public var have: Data
    public var selectedFileIndex: Int?
    public var paused: Bool
    public var addedAt: Date
    public var lastUsedAt: Date
    public var displayName: String
    public var magnet: String?
}

/// Free space and the user's cache limit.
public struct StorageBudget: Sendable {
    public var limit: Int64
    public var reserve: Int64
    /// Returns available bytes on the volume, or nil when unknown.
    public var freeSpace: @Sendable () -> Int64?

    public init(limit: Int64, reserve: Int64, freeSpace: @escaping @Sendable () -> Int64?) {
        self.limit = limit
        self.reserve = reserve
        self.freeSpace = freeSpace
    }

    /// The most free space that is kept untouched on this platform.
    ///
    /// Apple TV reports only raw free space, and tvOS deliberately keeps that small: it fills
    /// storage with other apps' purgeable caches and clears them when an app needs room. A
    /// 2 GB reserve measured against that figure refused every piece on a healthy Apple TV,
    /// so the torrent paused itself before the first byte was stored.
    public static var platformReserveCap: Int64 {
        #if os(tvOS)
        return 128 * 1024 * 1024
        #else
        return .max
        #endif
    }

    public static func volume(of url: URL, limit: Int64, reserve: Int64) -> StorageBudget {
        StorageBudget(limit: limit, reserve: min(reserve, platformReserveCap)) {
            #if os(Linux)
            let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path)
            return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value
            #elseif os(tvOS)
            // tvOS has no "important usage" figure; use plain available capacity.
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return values?.volumeAvailableCapacity.map(Int64.init)
            #else
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values?.volumeAvailableCapacityForImportantUsage
            #endif
        }
    }

    /// Throws when writing `bytes` more would break the limit or the free-space reserve.
    func check(adding bytes: Int64, currentUsage: Int64) throws {
        if currentUsage + bytes > limit { throw TorrentError.storageLimitReached(limitBytes: limit) }
        if let free = freeSpace(), free - bytes < reserve {
            throw TorrentError.storageFull(neededBytes: reserve - (free - bytes))
        }
    }
}

final class PieceStore {
    let directory: URL
    let pieceCount: Int
    private(set) var have: [Bool]
    private let metainfo: TorrentMetainfo
    private var handle: FileHandle?

    static func directory(for hash: InfoHash, in root: URL) throws -> URL {
        // The hex string is 40 characters of [0-9a-f], so this cannot leave `root`.
        let dir = root.appendingPathComponent(hash.hex, isDirectory: true).standardizedFileURL
        guard dir.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw TorrentError.unsafeLocation }
        return dir
    }

    init(metainfo: TorrentMetainfo, root: URL, have: [Bool]?) throws {
        self.metainfo = metainfo
        self.pieceCount = metainfo.pieceCount
        self.directory = try Self.directory(for: metainfo.infoHash, in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = directory.appendingPathComponent("data.bin")
        if !FileManager.default.fileExists(atPath: data.path) {
            _ = FileManager.default.createFile(atPath: data.path, contents: nil)
        }
        self.handle = try FileHandle(forUpdating: data)
        if let have, have.count == pieceCount {
            self.have = have
        } else {
            self.have = Array(repeating: false, count: pieceCount)
        }
    }

    deinit { try? handle?.close() }

    var storedBytes: Int64 {
        have.indices.reduce(Int64(0)) { $0 + (have[$1] ? Int64(metainfo.pieceSize($1)) : 0) }
    }

    func write(piece index: Int, data: Data) throws {
        guard let handle, index >= 0, index < pieceCount, data.count == metainfo.pieceSize(index) else {
            throw TorrentError.sourceFailed("Bad piece write.")
        }
        try handle.seek(toOffset: UInt64(index) * UInt64(metainfo.pieceLength))
        try handle.write(contentsOf: data)
        have[index] = true
    }

    func read(offset: Int64, length: Int) throws -> Data {
        guard let handle else { throw TorrentError.cancelled }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length) ?? Data()
    }

    func readPiece(_ index: Int) throws -> Data {
        try read(offset: Int64(index) * Int64(metainfo.pieceLength), length: metainfo.pieceSize(index))
    }

    /// Re-hashes pieces marked as present (after a crash the resume file may be ahead of the data).
    func verifyAll() {
        for i in have.indices where have[i] {
            if (try? readPiece(i)).map({ SHA1.hash($0) }) != metainfo.pieceHashes[i] { have[i] = false }
        }
    }

    func close() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
    }

    // MARK: Bitfield

    var bitfield: Data {
        var bytes = [UInt8](repeating: 0, count: (pieceCount + 7) / 8)
        for i in have.indices where have[i] { bytes[i / 8] |= 0x80 >> UInt8(i % 8) }
        return Data(bytes)
    }

    static func bools(fromBitfield data: Data, count: Int) -> [Bool] {
        let bytes = [UInt8](data)
        return (0..<count).map { i in i / 8 < bytes.count && bytes[i / 8] & (0x80 >> UInt8(i % 8)) != 0 }
    }
}

enum AtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: temp)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}
