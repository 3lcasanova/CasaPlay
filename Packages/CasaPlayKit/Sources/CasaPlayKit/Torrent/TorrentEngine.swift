// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Owns all torrent sessions. Source providers (which find torrents) stay separate from
// this engine (which transfers data): providers hand over magnet links or .torrent files.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TorrentSummary: Identifiable, Equatable, Sendable {
    public var id: InfoHash { infoHash }
    public let infoHash: InfoHash
    public var stats: TorrentStats
    public var storedBytes: Int64
}

public actor TorrentEngine {
    public nonisolated let root: URL
    private var settings: TorrentSettings
    private let transport: HTTPTransport
    private let peerFactory: PeerTransportFactory?
    private let udpFactory: UDPExchangeFactory?
    private let freeSpace: (@Sendable (URL) -> Int64?)?
    private let usage = StorageUsage()
    private var sessions: [InfoHash: TorrentSession] = [:]
    private var order: [InfoHash] = []

    /// - Parameters:
    ///   - root: a folder inside the app's own container (Caches on tvOS).
    ///   - peerFactory: makes connections to peers; nil disables peer-to-peer (web seeds only).
    public init(root: URL, settings: TorrentSettings = TorrentSettings(),
                transport: HTTPTransport = URLSessionTransport(), peerFactory: PeerTransportFactory?,
                udpFactory: UDPExchangeFactory? = UDPTrackerSupport.defaultFactory,
                freeSpace: (@Sendable (URL) -> Int64?)? = nil) {
        self.udpFactory = udpFactory
        self.freeSpace = freeSpace
        self.root = root.standardizedFileURL
        self.settings = settings
        self.transport = transport
        self.peerFactory = peerFactory
    }

    public var currentSettings: TorrentSettings { settings }

    // MARK: Adding

    public func add(magnet text: String) async throws -> TorrentSession {
        let magnet = try MagnetLink(parsing: text)
        if let existing = sessions[magnet.infoHash] { return existing }
        let session = makeSession(hash: magnet.infoHash, magnet: magnet, metainfo: nil, resume: nil)
        await session.start()
        return session
    }

    public func add(torrentFile data: Data) async throws -> TorrentSession {
        let info = try TorrentMetainfo.parse(torrentFile: data)
        if let existing = sessions[info.infoHash] { return existing }
        let session = makeSession(hash: info.infoHash, magnet: nil, metainfo: info, resume: nil)
        try saveTorrentFile(data, hash: info.infoHash)
        await session.start()
        return session
    }

    /// Downloads a .torrent over HTTPS (for example from a source provider) and adds it.
    public func add(torrentURL url: URL) async throws -> TorrentSession {
        guard url.scheme?.lowercased() == "https" else {
            throw TorrentError.sourceFailed("Only HTTPS links to .torrent files are accepted.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let response = try await transport.send(request)
        guard response.status == 200 else {
            throw TorrentError.sourceFailed(response.status == 403 || response.status == 401
                ? "This torrent isn't available to you (the source answered \(response.status))."
                : "Couldn't download the torrent file (error \(response.status)).")
        }
        return try await add(torrentFile: response.body)
    }

    private func makeSession(hash: InfoHash, magnet: MagnetLink?, metainfo: TorrentMetainfo?, resume: ResumeData?) -> TorrentSession {
        let session = TorrentSession(
            infoHash: hash, magnet: magnet, metainfo: metainfo, root: root, settings: settings,
            transport: transport, peerFactory: peerFactory, udpFactory: udpFactory, usage: usage, resume: resume, freeSpace: freeSpace
        )
        sessions[hash] = session
        order.removeAll { $0 == hash }
        order.insert(hash, at: 0)
        return session
    }

    private func saveTorrentFile(_ data: Data, hash: InfoHash) throws {
        let dir = try PieceStore.directory(for: hash, in: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AtomicFile.write(data, to: dir.appendingPathComponent("info.torrent"))
    }

    // MARK: Restoring after relaunch

    /// Finds torrents saved by earlier launches. Paused ones stay paused; others are left
    /// stopped until the user or the player asks for data (`resumeAll` or a read).
    public func restore() async {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        var total: Int64 = 0
        for dir in entries {
            guard let hash = InfoHash(hex: dir.lastPathComponent), sessions[hash] == nil else { continue }
            let resume = (try? Data(contentsOf: dir.appendingPathComponent("resume.json")))
                .flatMap { try? JSONDecoder().decode(ResumeData.self, from: $0) }
            let info = (try? Data(contentsOf: dir.appendingPathComponent("info.torrent")))
                .flatMap { try? TorrentMetainfo.parse(torrentFile: $0) }
            if let info, info.infoHash != hash { continue }  // damaged or tampered folder: ignore
            guard info != nil || resume?.magnet != nil else { continue }
            let magnet = resume?.magnet.flatMap { try? MagnetLink(parsing: $0) }
            _ = makeSession(hash: hash, magnet: magnet, metainfo: info, resume: resume)
            if let resume, let info { total += Int64(PieceStore.bools(fromBitfield: resume.have, count: info.pieceCount).enumerated()
                .filter(\.element).reduce(0) { $0 + info.pieceSize($1.offset) }) }
        }
        await usage.add(total)
    }

    // MARK: Control

    public func session(_ hash: InfoHash) -> TorrentSession? { sessions[hash] }

    public func summaries() async -> [TorrentSummary] {
        var out: [TorrentSummary] = []
        for hash in order {
            guard let s = sessions[hash] else { continue }
            out.append(TorrentSummary(infoHash: hash, stats: await s.stats(), storedBytes: await s.storedBytes))
        }
        return out
    }

    public func remove(_ hash: InfoHash, deleteData: Bool = true) async {
        guard let session = sessions.removeValue(forKey: hash) else { return }
        order.removeAll { $0 == hash }
        await session.cancel(deleteData: deleteData)
    }

    /// The app is going to the background or Apple TV is going to sleep.
    public func suspendAll() async {
        for s in sessions.values { await s.suspend() }
    }

    public func update(settings new: TorrentSettings) async {
        settings = new
        for s in sessions.values { await s.update(settings: new) }
    }

    public func usedBytes() async -> Int64 { await usage.total }

    /// Deletes the least recently used torrents until the cache fits `target` bytes.
    /// Torrents in `keep` (for example the one playing) are never removed.
    @discardableResult
    public func cleanUp(toFit target: Int64, keep: Set<InfoHash> = []) async -> [InfoHash] {
        var removed: [InfoHash] = []
        var candidates: [(InfoHash, Date)] = []
        for (hash, s) in sessions where !keep.contains(hash) { candidates.append((hash, await s.lastUsed)) }
        for (hash, _) in candidates.sorted(by: { $0.1 < $1.1 }) {
            if await usage.total <= target { break }
            await remove(hash, deleteData: true)
            removed.append(hash)
        }
        return removed
    }

    /// Removes every torrent and all cached data.
    public func clearAll() async {
        for hash in Array(sessions.keys) { await remove(hash, deleteData: true) }
        if let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for dir in entries where InfoHash(hex: dir.lastPathComponent) != nil {
                try? FileManager.default.removeItem(at: dir)
            }
        }
        await usage.add(-(await usage.total))
    }
}
