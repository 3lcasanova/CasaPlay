// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// One torrent: gets its metadata, fetches pieces from web seeds and peers, checks every
// piece's SHA-1, stores it, and answers the player's byte-range reads as soon as the
// needed pieces arrive. Runs only while the app is allowed to run.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Total cache usage shared by all sessions, for the storage limit.
public actor StorageUsage {
    private(set) var bytes: Int64
    public init(bytes: Int64 = 0) { self.bytes = bytes }
    func add(_ delta: Int64) { bytes = max(0, bytes + delta) }
    public var total: Int64 { bytes }
}

public actor TorrentSession: PeerHost {
    public nonisolated let infoHash: InfoHash
    nonisolated let localPeerID: Data
    private let root: URL
    private let transport: HTTPTransport
    private let peerFactory: PeerTransportFactory?
    private let udpFactory: UDPExchangeFactory?
    private let usage: StorageUsage
    private let freeSpace: (@Sendable (URL) -> Int64?)?
    private var settings: TorrentSettings
    private var magnet: MagnetLink?

    public private(set) var currentMetainfo: TorrentMetainfo?
    private var store: PieceStore?
    private var picker: PiecePicker?
    private var selectedFile: Int?
    private var metadataSearchStartedAt: ContinuousClock.Instant?
    private var paused = false
    /// Why the engine paused the torrent by itself (storage full, cache limit). Nil when the
    /// user paused it. Readers are given this instead of a bare "paused".
    private var pauseReason: TorrentError?
    private var stopped = false
    private var addedAt = Date()
    private var lastUsedAt = Date()

    private var workers: [Task<Void, Never>] = []
    private var peers: [ObjectIdentifier: PeerConnection] = [:]
    private var peerTasks: [Task<Void, Never>] = []
    private var knownPeers: Set<PeerAddress> = []
    private var attemptedPeers: Set<PeerAddress> = []
    private var activeWebSeeds = 0
    private var metadataWaiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var pieceWaiters: [Int: [(id: UUID, continuation: CheckedContinuation<Void, Error>)]] = [:]
    private var downloadMeter = RateMeter()
    private var uploadMeter = RateMeter()
    private var downloaded: Int64 = 0
    private var uploaded: Int64 = 0
    private var readPosition: Int64 = 0
    private var isWaitingForData = false
    private var lastError: String?
    private var piecesSinceSave = 0
    private let uploadLimiter: RateLimiter
    private let downloadLimiter: RateLimiter
    private var uploadSlots = 0

    init(
        infoHash: InfoHash,
        magnet: MagnetLink?,
        metainfo: TorrentMetainfo?,
        root: URL,
        settings: TorrentSettings,
        transport: HTTPTransport,
        peerFactory: PeerTransportFactory?,
        udpFactory: UDPExchangeFactory? = nil,
        usage: StorageUsage,
        resume: ResumeData? = nil,
        freeSpace: (@Sendable (URL) -> Int64?)? = nil
    ) {
        self.freeSpace = freeSpace
        self.infoHash = infoHash
        self.magnet = magnet
        self.currentMetainfo = metainfo
        self.root = root
        self.settings = settings
        self.transport = transport
        self.peerFactory = peerFactory
        self.udpFactory = udpFactory
        self.usage = usage
        self.localPeerID = Data("-CP0010-".utf8) + Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        self.uploadLimiter = RateLimiter(bytesPerSecond: settings.uploadLimit)
        self.downloadLimiter = RateLimiter(bytesPerSecond: settings.downloadLimit)
        if let resume {
            selectedFile = resume.selectedFileIndex
            paused = resume.paused
            addedAt = resume.addedAt
            lastUsedAt = resume.lastUsedAt
            if let m = resume.magnet { self.magnet = try? MagnetLink(parsing: m) }
        }
    }

    // MARK: Lifecycle

    /// Starts getting metadata and, when a file is selected, data.
    public func start() async {
        guard !stopped else { return }
        paused = false
        pauseReason = nil
        lastError = nil
        if currentMetainfo == nil {
            metadataSearchStartedAt = .now
            startPeerDiscovery()
            workers.append(Task { await self.fetchMetadataFromExactSources() })
        } else {
            do { try openStore() } catch { fail(error); return }
            startPeerDiscovery()
            startWebSeeds()
        }
        saveResume()
    }

    /// Starts again if the torrent was paused, by the user or by an error such as low storage.
    /// Called when the user explicitly plays a file; a running torrent is left alone.
    public func resumeIfPaused() async {
        if paused { await start() }
    }

    public func pause() {
        paused = true
        pauseReason = nil
        stopNetwork()
        failWaiters(TorrentError.paused)
        saveResume()
    }

    /// Pauses because of an error, and tells anyone waiting for data what the error was.
    private func pause(because reason: TorrentError) {
        paused = true
        pauseReason = reason
        stopNetwork()
        failWaiters(reason)
        saveResume()
    }

    /// Stops everything. With `deleteData` the torrent's folder is removed.
    public func cancel(deleteData: Bool) async {
        stopped = true
        stopNetwork()
        failWaiters(TorrentError.cancelled)
        if !deleteData { saveResume() }
        let freed = store?.storedBytes ?? 0
        store?.close()
        store = nil
        if deleteData, let dir = try? PieceStore.directory(for: infoHash, in: root) {
            try? FileManager.default.removeItem(at: dir)
            await usage.add(-freed)
        }
    }

    /// Saves progress and closes connections, e.g. when the app moves to the background.
    public func suspend() {
        stopNetwork()
        failWaiters(TorrentError.paused)
        saveResume()
    }

    public func update(settings new: TorrentSettings) async {
        settings = new
        picker?.readAhead = new.streamingWindow
        await uploadLimiter.setLimit(new.uploadLimit)
        await downloadLimiter.setLimit(new.downloadLimit)
        saveResume()
    }

    private func stopNetwork() {
        workers.forEach { $0.cancel() }
        workers = []
        peerTasks.forEach { $0.cancel() }
        peerTasks = []
        peers.values.forEach { $0.stop() }
        peers = [:]
        activeWebSeeds = 0
        attemptedPeers = []
    }

    private func fail(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }

    // MARK: Metadata

    public func waitForMetadata(timeout: TimeInterval = 60) async throws -> TorrentMetainfo {
        if let currentMetainfo { return currentMetainfo }
        let id = UUID()
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self.expireMetadataWaiter(id)
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            metadataWaiters.append((id, c))
        }
        guard let currentMetainfo else { throw TorrentError.metadataUnavailable }
        return currentMetainfo
    }

    private func expireMetadataWaiter(_ id: UUID) {
        guard let i = metadataWaiters.firstIndex(where: { $0.id == id }) else { return }
        metadataWaiters.remove(at: i).continuation.resume(throwing: TorrentError.metadataUnavailable)
    }

    /// Fetches the .torrent from the magnet's "xs" (exact source) URLs and checks its hash.
    private func fetchMetadataFromExactSources() async {
        for url in magnet?.exactSources ?? [] {
            guard currentMetainfo == nil, !Task.isCancelled else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            guard let response = try? await transport.send(request), response.status == 200,
                  let info = try? TorrentMetainfo.parse(torrentFile: response.body) else { continue }
            guard info.infoHash == infoHash else {
                lastError = TorrentError.metadataMismatch.errorDescription
                continue
            }
            await install(metainfo: info)
            return
        }
    }

    /// Called with metadata assembled from a peer. Accepted only when its SHA-1 is the info-hash.
    func acceptMetadata(_ info: Data) async -> Bool {
        guard currentMetainfo == nil else { return true }
        guard SHA1.hash(info) == infoHash.bytes,
              let parsed = try? TorrentMetainfo.parse(
                  infoDictionary: info,
                  trackers: magnet?.trackers ?? [],
                  webSeeds: magnet?.webSeeds ?? []
              ) else {
            lastError = TorrentError.metadataMismatch.errorDescription
            return false
        }
        await install(metainfo: parsed)
        return true
    }

    private func install(metainfo: TorrentMetainfo) async {
        guard currentMetainfo == nil else { return }
        // Keep trackers and web seeds from the magnet link as well as the torrent's own.
        currentMetainfo = metainfo
        do {
            try openStore()
            try saveMetainfo(metainfo)
        } catch {
            fail(error)
        }
        metadataWaiters.forEach { $0.continuation.resume() }
        metadataWaiters = []
        for peer in peers.values { await peer.metadataReady(pieceCount: metainfo.pieceCount) }
        startPeerDiscovery()
        startWebSeeds()
        saveResume()
    }

    private func openStore() throws {
        guard store == nil, let info = currentMetainfo else { return }
        let dir = try PieceStore.directory(for: infoHash, in: root)
        let resume = (try? Data(contentsOf: dir.appendingPathComponent("resume.json")))
            .flatMap { try? JSONDecoder().decode(ResumeData.self, from: $0) }
        let have = resume.map { PieceStore.bools(fromBitfield: $0.have, count: info.pieceCount) }
        let store = try PieceStore(metainfo: info, root: root, have: have)
        if resume != nil { store.verifyAll() }
        self.store = store
        var picker = PiecePicker(metainfo: info, readAhead: settings.streamingWindow)
        if let selectedFile, selectedFile < info.files.count { picker.select(file: info.files[selectedFile]) }
        self.picker = picker
    }

    private func saveMetainfo(_ info: TorrentMetainfo) throws {
        let dir = try PieceStore.directory(for: infoHash, in: root)
        var root: [String: BValue] = ["info": .int(0)]
        if !info.trackers.isEmpty {
            root["announce-list"] = .list(info.trackers.map { .list([.string($0.absoluteString)]) })
        }
        if !info.webSeeds.isEmpty { root["url-list"] = .list(info.webSeeds.map { .string($0.absoluteString) }) }
        // Splice the original info bytes in so the info-hash stays identical.
        var encoded = BencodeEncoder.encode(.dict(root))
        let placeholder = Data("4:infoi0e".utf8)
        if let range = encoded.range(of: placeholder) {
            encoded.replaceSubrange(range, with: Data("4:info".utf8) + info.infoDictionary)
        }
        try AtomicFile.write(encoded, to: dir.appendingPathComponent("info.torrent"))
    }

    // MARK: File selection and reading

    public func selectFile(_ index: Int) async throws {
        let info = try await waitForMetadata()
        guard index >= 0, index < info.files.count else { throw TorrentError.fileNotSelected }
        selectedFile = index
        if store == nil { try openStore() }
        picker?.select(file: info.files[index])
        readPosition = info.files[index].offset
        saveResume()
        if !paused, !stopped {
            startWebSeeds()
            startPeerDiscovery()
        }
    }

    /// Returns up to `length` bytes of the selected file starting at `offset`, waiting for the
    /// pieces if needed. Never returns unverified data. Returns empty data at end of file.
    public func read(fileIndex: Int, offset: Int64, length: Int, timeout: TimeInterval = 45) async throws -> Data {
        guard let info = currentMetainfo, fileIndex < info.files.count else { throw TorrentError.fileNotSelected }
        let file = info.files[fileIndex]
        guard offset < file.length else { return Data() }
        let wanted = Int(min(Int64(length), file.length - offset))
        let startOffset = file.offset + offset
        lastUsedAt = Date()
        readPosition = startOffset
        picker?.setFocus(offset: startOffset)
        if let urgent = info.pieces(covering: startOffset..<(startOffset + Int64(min(wanted, info.pieceLength * 2)))) {
            picker?.markUrgent(urgent)
        }
        guard let first = info.pieces(covering: startOffset..<(startOffset + 1))?.lowerBound else { return Data() }
        // Cleared on every exit, including errors: a failed read used to leave the player
        // saying "Buffering" for ever, hiding the real reason in `lastError`.
        defer { isWaitingForData = false }
        while store?.have[first] != true {
            if paused { throw pauseReason ?? TorrentError.paused }
            if stopped { throw TorrentError.cancelled }
            isWaitingForData = true
            if workers.isEmpty && peers.isEmpty && !paused {
                await start()
                continue  // starting may have loaded the piece from disk
            }
            try await waitForPiece(first, timeout: timeout)
        }
        isWaitingForData = false
        // Return the verified run of bytes starting at `startOffset`.
        guard let store else { throw TorrentError.cancelled }
        var end = startOffset
        let limit = startOffset + Int64(wanted)
        var piece = first
        while end < limit, piece < info.pieceCount, store.have[piece] {
            end = min(limit, Int64(piece + 1) * Int64(info.pieceLength))
            piece += 1
        }
        return try store.read(offset: startOffset, length: Int(end - startOffset))
    }

    private func waitForPiece(_ index: Int, timeout: TimeInterval) async throws {
        let id = UUID()
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self.expireWaiter(index, id: id)
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            pieceWaiters[index, default: []].append((id, continuation))
        }
    }

    private func expireWaiter(_ index: Int, id: UUID) {
        guard let i = pieceWaiters[index]?.firstIndex(where: { $0.id == id }) else { return }
        let waiter = pieceWaiters[index]!.remove(at: i)
        waiter.continuation.resume(throwing: TorrentError.timedOut)
    }

    private func failWaiters(_ error: Error) {
        let all = pieceWaiters.values.flatMap { $0 }
        pieceWaiters = [:]
        all.forEach { $0.continuation.resume(throwing: error) }
        metadataWaiters.forEach { $0.continuation.resume(throwing: error) }
        metadataWaiters = []
    }

    // MARK: Pieces

    func nextPiece(peerHas: [Bool]) -> Int? {
        guard !paused, let store else { return nil }
        return picker?.next(have: store.have, canSupply: { $0 < peerHas.count && peerHas[$0] })
    }

    func releasePiece(_ index: Int) { picker?.release(index) }

    func peerAvailability(add pieces: [Int]) {
        guard picker != nil else { return }
        for i in pieces where i < picker!.availability.count { picker!.availability[i] += 1 }
    }

    /// Verifies and stores a piece. Returns false if it was rejected.
    func deliver(piece index: Int, data: Data) async -> Bool {
        guard let info = currentMetainfo, let store, index >= 0, index < info.pieceCount else { return false }
        if store.have[index] { picker?.done(index); return true }
        guard data.count == info.pieceSize(index), SHA1.hash(data) == info.pieceHashes[index] else {
            picker?.release(index)
            return false
        }
        do {
            var budget = StorageBudget.volume(of: root, limit: settings.storageLimit, reserve: settings.reserveFreeSpace)
            if let freeSpace {
                let root = self.root
                budget.freeSpace = { freeSpace(root) }
            }
            try budget.check(adding: Int64(data.count), currentUsage: await usage.total)
            try store.write(piece: index, data: data)
            await usage.add(Int64(data.count))
        } catch {
            picker?.release(index)
            fail(error)
            if let reason = error as? TorrentError { pause(because: reason) }
            return false
        }
        picker?.done(index)
        downloaded += Int64(data.count)
        downloadMeter.add(data.count)
        if let waiters = pieceWaiters.removeValue(forKey: index) {
            waiters.forEach { $0.continuation.resume() }
        }
        if settings.uploadsAllowed {
            for peer in peers.values { Task { await peer.sendHave(index) } }
        }
        piecesSinceSave += 1
        if piecesSinceSave >= 8 { saveResume() }
        if picker?.isComplete(have: store.have) == true {
            saveResume()
            if !settings.seedAfterDownload { stopNetwork() }
        }
        return true
    }

    // MARK: Uploading

    var wantsUploadSlot: Bool {
        guard settings.uploadsAllowed, uploadSlots < 4 else { return false }
        let complete = picker.map { p in store.map { p.isComplete(have: $0.have) } ?? false } ?? false
        guard complete ? settings.seedAfterDownload : settings.uploadWhileDownloading else { return false }
        uploadSlots += 1
        return true
    }

    var advertisedBitfield: Data? {
        guard settings.uploadsAllowed, let store, store.have.contains(true) else { return nil }
        return store.bitfield
    }

    func uploadBlock(index: Int, begin: Int, length: Int) async -> Data? {
        guard settings.uploadsAllowed, let info = currentMetainfo, let store,
              index >= 0, index < info.pieceCount, store.have[index],
              begin >= 0, begin + length <= info.pieceSize(index) else { return nil }
        guard await uploadLimiter.acquire(length, unlimitedWhenZero: false) else { return nil }
        guard let data = try? store.read(offset: Int64(index) * Int64(info.pieceLength) + Int64(begin), length: length) else { return nil }
        uploaded += Int64(data.count)
        uploadMeter.add(data.count)
        return data
    }

    // MARK: Sources

    private func startWebSeeds() {
        guard !paused, !stopped, let info = currentMetainfo, selectedFile != nil, activeWebSeeds == 0 else { return }
        // HTTPS only: Apple's App Transport Security blocks plain HTTP in this app, and
        // HTTPS keeps the files being fetched private from the local network.
        let seeds = Array(Set(info.webSeeds + (magnet?.webSeeds ?? []))).filter { $0.scheme?.lowercased() == "https" }
        for seed in seeds {
            let client = WebSeedClient(base: seed, transport: transport)
            for _ in 0..<3 {  // a few parallel range requests per web seed
                activeWebSeeds += 1
                workers.append(Task { await self.webSeedLoop(client) })
            }
        }
    }

    private func webSeedLoop(_ client: WebSeedClient) async {
        defer { activeWebSeeds = max(activeWebSeeds - 1, 0) }
        var failures = 0
        while !Task.isCancelled, !paused, let info = currentMetainfo, let store {
            guard let piece = picker?.next(have: store.have, canSupply: { _ in true }) else {
                if picker?.isComplete(have: store.have) == true { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            }
            _ = await downloadLimiter.acquire(info.pieceSize(piece), unlimitedWhenZero: true)
            do {
                let data = try await client.fetch(piece: piece, metainfo: info)
                if await deliver(piece: piece, data: data) { failures = 0 } else { failures += 1 }
            } catch {
                picker?.release(piece)
                failures += 1
                if Task.isCancelled { return }
                lastError = (error as? LocalizedError)?.errorDescription ?? "Web seed error."
            }
            if failures >= 5 {
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // back off, then try again
                failures = 0
            }
        }
    }

    /// Used only when a torrent lists no tracker CasaPlay can reach.
    static let fallbackTrackers: [URL] = [
        "udp://tracker.opentrackr.org:1337/announce",
        "http://tracker.opentrackr.org:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://exodus.desync.com:6969/announce"
    ].compactMap(URL.init(string:))

    private func startPeerDiscovery() {
        guard !paused, !stopped, peerFactory != nil else { return }
        var trackers = Array(Set((currentMetainfo?.trackers ?? []) + (magnet?.trackers ?? [])))
            .filter(canAnnounce)
        if trackers.isEmpty { trackers = Self.fallbackTrackers.filter(canAnnounce) }
        for tracker in trackers {
            workers.append(Task { await self.trackerLoop(tracker) })
        }
    }

    private nonisolated func canAnnounce(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https": return true
        case "udp": return udpFactory != nil
        default: return false
        }
    }

    private func trackerLoop(_ url: URL) async {
        let http = HTTPTrackerClient(announce: url, transport: transport)
        let udp = udpFactory.flatMap { UDPTrackerClient(announce: url, factory: $0) }
        var event: String? = "started"
        var failures = 0
        while !Task.isCancelled, !paused {
            let left = currentMetainfo.map { info in
                info.totalLength - (store?.storedBytes ?? 0)
            } ?? 1
            let announce = HTTPTrackerClient.Announce(
                infoHash: infoHash, peerID: localPeerID,
                uploaded: uploaded, downloaded: downloaded, left: max(left, 0), event: event
            )
            var wait = 300
            let response: TrackerResponse?
            if let udp {
                response = try? await udp.announce(announce)
            } else {
                response = try? await http.announce(announce)
            }
            if let response {
                event = nil
                failures = 0
                wait = response.interval
                knownPeers.formUnion(response.peers)
                connectMorePeers()
            } else {
                // Retry soon at first: UDP packets get lost, and a tracker may be briefly busy.
                failures += 1
                wait = min(15 << min(failures - 1, 4), 300)
            }
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
        }
    }

    /// Adds peers directly (used by tests and by sources that supply peer addresses).
    public func addPeers(_ addresses: [PeerAddress]) {
        knownPeers.formUnion(addresses)
        connectMorePeers()
    }

    private func connectMorePeers() {
        guard !paused, !stopped, let factory = peerFactory else { return }
        let complete = picker.map { p in store.map { p.isComplete(have: $0.have) } ?? false } ?? false
        if complete && !settings.seedAfterDownload { return }
        for address in knownPeers.subtracting(attemptedPeers) {
            guard attemptedPeers.count - 0 < settings.maxPeers + 20, peers.count < settings.maxPeers else { break }
            attemptedPeers.insert(address)
            guard let transport = factory(address) else { continue }
            let connection = PeerConnection(address: address, transport: transport, host: self)
            peerTasks.append(Task { await connection.run() })
        }
    }

    /// Runs a connection that a peer opened to us (or, in tests, an in-memory pipe).
    public func acceptIncoming(_ transport: PeerTransport, from address: PeerAddress) {
        guard !paused, !stopped else { transport.close(); return }
        let connection = PeerConnection(address: address, transport: transport, host: self)
        peerTasks.append(Task { await connection.run() })
    }

    func peerConnected(_ connection: PeerConnection) {
        peers[ObjectIdentifier(connection)] = connection
    }

    func peerDisconnected(_ connection: PeerConnection) {
        peers[ObjectIdentifier(connection)] = nil
    }

    // MARK: Stats and persistence

    public func stats() -> TorrentStats {
        var s = TorrentStats()
        s.name = currentMetainfo?.name ?? magnet?.displayName ?? infoHash.hex
        s.selectedFileIndex = selectedFile
        s.downloadedBytes = downloaded
        s.uploadedBytes = uploaded
        s.downloadRate = downloadMeter.rate()
        s.uploadRate = uploadMeter.rate()
        s.connectedPeers = peers.count
        s.knownPeers = knownPeers.count
        s.activeWebSeeds = activeWebSeeds
        s.lastError = lastError
        s.isBuffering = isWaitingForData
        if let info = currentMetainfo, let store {
            let range: ClosedRange<Int>? = selectedFile.flatMap { info.pieces(of: info.files[$0]) }
                ?? (0...(info.pieceCount - 1))
            if let range {
                let have = range.filter { store.have[$0] }.count
                s.progress = Double(have) / Double(range.count)
            }
            if let first = info.pieces(covering: readPosition..<(readPosition + 1))?.lowerBound {
                var piece = first
                while piece < info.pieceCount, store.have[piece] { piece += 1 }
                s.bufferedAhead = max(0, Int64(piece) * Int64(info.pieceLength) - readPosition)
            }
        }
        if stopped { s.state = .failed("Cancelled") }
        else if paused { s.state = .paused }
        else if currentMetainfo == nil {
            if let started = metadataSearchStartedAt, started.duration(to: .now) >= .seconds(60) {
                let message = lastError ?? "Still waiting for torrent details. Try importing the .torrent file."
                s.lastError = message
                s.state = .failed(message)
            } else {
                s.state = .fetchingMetadata
            }
        }
        else if s.progress >= 1, selectedFile != nil { s.state = .completed }
        else if selectedFile == nil { s.state = .ready }
        else { s.state = .downloading }
        if let error = lastError, case .downloading = s.state, s.connectedPeers == 0, activeWebSeeds == 0 {
            s.state = .failed(error)
        }
        return s
    }

    public func files() -> [TorrentFile] { currentMetainfo?.files ?? [] }

    func saveResume() {
        piecesSinceSave = 0
        guard let dir = try? PieceStore.directory(for: infoHash, in: root) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let resume = ResumeData(
            have: store?.bitfield ?? Data(),
            selectedFileIndex: selectedFile,
            paused: paused,
            addedAt: addedAt,
            lastUsedAt: lastUsedAt,
            displayName: currentMetainfo?.name ?? magnet?.displayName ?? infoHash.hex,
            magnet: magnet?.uri
        )
        if let data = try? JSONEncoder().encode(resume) {
            try? AtomicFile.write(data, to: dir.appendingPathComponent("resume.json"))
        }
    }

    var storedBytes: Int64 { store?.storedBytes ?? 0 }
    var lastUsed: Date { lastUsedAt }
    var isPaused: Bool { paused }
}
