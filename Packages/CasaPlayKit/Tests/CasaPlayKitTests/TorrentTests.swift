// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

// MARK: - Helpers

/// Builds a real, valid torrent in memory.
struct SyntheticTorrent {
    let files: [(path: [String], data: Data)]
    let pieceLength: Int
    let name: String
    let webSeed: URL?
    let trackers: [String]

    init(name: String = "Sample", files: [(path: [String], data: Data)], pieceLength: Int = 16 * 1024,
         webSeed: URL? = URL(string: "https://seed.example.com/files/"), trackers: [String] = []) {
        self.name = name
        self.files = files
        self.pieceLength = pieceLength
        self.webSeed = webSeed
        self.trackers = trackers
    }

    var payload: Data { files.reduce(into: Data()) { $0.append($1.data) } }

    var infoDictionary: Data {
        let all = payload
        var hashes = Data()
        var i = 0
        while i < all.count {
            hashes.append(SHA1.hash(all.subdata(in: i..<min(i + pieceLength, all.count))))
            i += pieceLength
        }
        var info: [String: BValue] = [
            "name": .string(name),
            "piece length": .int(Int64(pieceLength)),
            "pieces": .bytes(hashes)
        ]
        if files.count == 1 && files[0].path.isEmpty {
            info["length"] = .int(Int64(files[0].data.count))
        } else {
            info["files"] = .list(files.map { f in
                .dict(["length": .int(Int64(f.data.count)), "path": .list(f.path.map { .string($0) })])
            })
        }
        return BencodeEncoder.encode(.dict(info))
    }

    var torrentFile: Data {
        var root: [String: BValue] = ["info": .int(0)]
        if let webSeed { root["url-list"] = .list([.string(webSeed.absoluteString)]) }
        if let first = trackers.first { root["announce"] = .string(first) }
        var encoded = BencodeEncoder.encode(.dict(root))
        let placeholder = Data("4:infoi0e".utf8)
        encoded.replaceSubrange(encoded.range(of: placeholder)!, with: Data("4:info".utf8) + infoDictionary)
        return encoded
    }

    var infoHash: InfoHash { InfoHash(bytes: SHA1.hash(infoDictionary))! }

    /// URL path → file bytes, as a BEP 19 web seed lays them out.
    var webSeedFiles: [String: Data] {
        var out: [String: Data] = [:]
        for f in files {
            let comps = f.path.isEmpty ? [name] : [name] + f.path
            let encoded = comps.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#;")))! }
            out["/files/" + encoded.joined(separator: "/")] = f.data
        }
        return out
    }
}

func randomData(_ count: Int, seed: UInt8) -> Data {
    var x = UInt32(seed) &* 2654435761 &+ 1
    return Data((0..<count).map { _ in x ^= x << 13; x ^= x >> 17; x ^= x << 5; return UInt8(truncatingIfNeeded: x) })
}

/// A web seed that honours Range headers and can be switched off or made to corrupt data.
final class RangeServer: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data]
    private var _online = true
    private var _corrupt = false
    private var _requests = 0
    var extraRoutes: [String: HTTPResponse] = [:]

    init(files: [String: Data]) { self.files = files }

    var online: Bool { get { lock.withLock { _online } } set { lock.withLock { _online = newValue } } }
    var corrupt: Bool { get { lock.withLock { _corrupt } } set { lock.withLock { _corrupt = newValue } } }
    var requests: Int { lock.withLock { _requests } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.withLock { _requests += 1 }
        guard online else { throw URLError(.notConnectedToInternet) }
        let path = request.url?.path ?? ""
        if let fixed = extraRoutes[request.url?.absoluteString ?? ""] ?? extraRoutes[path] { return fixed }
        guard let data = lock.withLock({ files[path] }) else { return HTTPResponse(status: 404, body: Data()) }
        guard let range = request.value(forHTTPHeaderField: "Range"),
              let spec = range.split(separator: "=").last?.split(separator: "-"),
              spec.count == 2, let lo = Int(spec[0]), let hi = Int(spec[1]) else {
            return HTTPResponse(status: 200, body: data)
        }
        var body = data.subdata(in: lo..<min(hi + 1, data.count))
        if corrupt, !body.isEmpty { body[body.startIndex] ^= 0xFF }
        return HTTPResponse(status: 206, body: body)
    }
}

/// Two connected in-memory byte streams.
final class PipeEnd: PeerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var waiting: CheckedContinuation<Data, Error>?
    private var closed = false
    weak var other: PipeEnd?

    static func pair() -> (PipeEnd, PipeEnd) {
        let a = PipeEnd(), b = PipeEnd()
        a.other = b; b.other = a
        return (a, b)
    }

    func connect() async throws {}

    func send(_ data: Data) async throws {
        guard let other, !lock.withLock({ closed }) else { throw TorrentError.sourceFailed("closed") }
        other.deliver(data)
    }

    private func deliver(_ data: Data) {
        let cont: CheckedContinuation<Data, Error>? = lock.withLock {
            if let w = waiting { waiting = nil; return w }
            buffer.append(data)
            return nil
        }
        cont?.resume(returning: data)
    }

    func receive(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            let immediate: Data? = lock.withLock {
                if !buffer.isEmpty { let d = buffer; buffer = Data(); return d }
                if closed { return Data() }
                waiting = c
                return nil
            }
            if let immediate { c.resume(returning: immediate) }
        }
    }

    func close() {
        let cont: CheckedContinuation<Data, Error>? = lock.withLock {
            closed = true
            let w = waiting; waiting = nil; return w
        }
        cont?.resume(returning: Data())
        if let other, !other.lock.withLock({ other.closed }) { other.close() }
    }
}

func tempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("casaplay-torrent-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Encoding and parsing

final class BencodeAndHashTests: XCTestCase {
    func testSHA1KnownVectors() {
        XCTAssertEqual(SHA1.hash(Data()).hexString, "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(SHA1.hash(Data("abc".utf8)).hexString, "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(SHA1.hash(Data(repeating: 0x61, count: 1_000_000)).hexString, "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
    }

    func testRoundTripAndKeyOrder() throws {
        let value = BValue.dict(["b": .int(-3), "a": .list([.string("x"), .int(0)])])
        let encoded = BencodeEncoder.encode(value)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "d1:ali0ee1:bi-3ee".replacingOccurrences(of: "ali0ee", with: "al1:xi0ee"))
        XCTAssertEqual(try BencodeDecoder().decode(encoded)["b"]?.int, -3)
    }

    func testRejectsMalformedInput() {
        let bad = ["i03e", "i-0e", "ie", "5:abc", "l", "d1:a", "x", "i1ei2e", String(repeating: "l", count: 200) + String(repeating: "e", count: 200)]
        for text in bad {
            XCTAssertThrowsError(try BencodeDecoder().decode(Data(text.utf8)), text)
        }
    }

    func testRawInfoBytesAreUsedForHash() throws {
        let t = SyntheticTorrent(files: [(["a.mp4"], randomData(40_000, seed: 1))])
        let info = try TorrentMetainfo.parse(torrentFile: t.torrentFile)
        XCTAssertEqual(info.infoHash, t.infoHash)
        XCTAssertEqual(info.infoDictionary, t.infoDictionary)
    }
}

final class MetainfoTests: XCTestCase {
    func testMultiFileLayoutAndPieceMath() throws {
        let t = SyntheticTorrent(files: [
            (["Extras", "readme.txt"], randomData(1000, seed: 2)),
            (["Movie.mp4"], randomData(100_000, seed: 3)),
            (["Movie.srt"], randomData(500, seed: 4))
        ])
        let info = try TorrentMetainfo.parse(torrentFile: t.torrentFile)
        XCTAssertEqual(info.files.map(\.path), ["Extras/readme.txt", "Movie.mp4", "Movie.srt"])
        XCTAssertEqual(info.files[1].offset, 1000)
        XCTAssertEqual(info.totalLength, 101_500)
        XCTAssertEqual(info.pieceCount, 7)
        XCTAssertEqual(info.pieceSize(6), 101_500 - 6 * 16384)
        XCTAssertEqual(info.pieces(of: info.files[1]), 0...6)
        XCTAssertEqual(info.pieces(of: info.files[0]), 0...0)
        XCTAssertEqual(info.webSeeds.first?.host, "seed.example.com")
    }

    func testHostilePathsAreCleaned() throws {
        let t = SyntheticTorrent(files: [
            (["..", "..", "etc", "passwd"], randomData(10, seed: 5)),
            (["/abs", "a\\b:c"], randomData(10, seed: 6)),
            (["Movie\u{202E}4pm.exe"], randomData(10, seed: 7)),
            ([".", "..", "...", "  "], randomData(10, seed: 8)),
            (["CON.txt"], randomData(10, seed: 9))
        ])
        let info = try TorrentMetainfo.parse(torrentFile: t.torrentFile)
        let paths = info.files.map(\.path)
        XCTAssertEqual(paths[0], "etc/passwd")
        XCTAssertEqual(paths[1], "_abs/a_b_c")
        XCTAssertEqual(paths[2], "Movie4pm.exe")
        XCTAssertEqual(paths[3], "file-3")
        XCTAssertEqual(paths[4], "_CON.txt")
        XCTAssertTrue(paths.allSatisfy { !$0.contains("..") && !$0.hasPrefix("/") })
    }

    func testRejectsInconsistentTorrents() {
        var info: [String: BValue] = ["name": .string("x"), "piece length": .int(16384), "length": .int(50_000),
                                      "pieces": .bytes(Data(count: 20))]
        let wrongCount = BencodeEncoder.encode(.dict(info))
        XCTAssertThrowsError(try TorrentMetainfo.parse(infoDictionary: wrongCount))
        info["piece length"] = .int(100)
        XCTAssertThrowsError(try TorrentMetainfo.parse(infoDictionary: BencodeEncoder.encode(.dict(info))))
        XCTAssertThrowsError(try TorrentMetainfo.parse(torrentFile: Data("not a torrent".utf8)))
    }

    func testMagnetParsing() throws {
        let hex = "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"
        let m = try MagnetLink(parsing: "magnet:?xt=urn:btih:\(hex)&dn=Big%20Buck%20Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fexample.com%2Fa.torrent&xs=http%3A%2F%2Finsecure.example%2Fa.torrent")
        XCTAssertEqual(m.infoHash.hex, hex)
        XCTAssertEqual(m.displayName, "Big Buck Bunny")
        XCTAssertEqual(m.trackers.map(\.absoluteString), ["udp://explodie.org:6969"])
        XCTAssertEqual(m.webSeeds.count, 1)
        XCTAssertEqual(m.exactSources.map(\.absoluteString), ["https://example.com/a.torrent"], "plain HTTP sources are refused")

        let b32 = try MagnetLink(parsing: "magnet:?xt=urn:btih:3WBFL3G4PSSV7MF37AJSHWDQMLNR63I4")
        XCTAssertEqual(b32.infoHash.hex, hex)
        XCTAssertEqual(try MagnetLink(parsing: m.uri).infoHash, m.infoHash)

        XCTAssertThrowsError(try MagnetLink(parsing: "https://example.com")) { XCTAssertEqual($0 as? MagnetLink.ParseError, .notAMagnet) }
        XCTAssertThrowsError(try MagnetLink(parsing: "magnet:?dn=x")) { XCTAssertEqual($0 as? MagnetLink.ParseError, .missingInfoHash) }
        XCTAssertThrowsError(try MagnetLink(parsing: "magnet:?xt=urn:btmh:1220abcd")) { XCTAssertEqual($0 as? MagnetLink.ParseError, .unsupportedHash) }
    }

    func testTrackerReplies() throws {
        var compact = Data([10, 0, 0, 1, 0x1A, 0xE1, 192, 168, 1, 2, 0, 80])
        compact.append(contentsOf: [0])  // stray byte is ignored
        let reply = BencodeEncoder.encode(.dict(["interval": .int(900), "peers": .bytes(compact)]))
        let parsed = try HTTPTrackerClient.parse(reply)
        XCTAssertEqual(parsed.interval, 900)
        XCTAssertEqual(parsed.peers.map(\.description), ["10.0.0.1:6881", "192.168.1.2:80"])

        let failure = BencodeEncoder.encode(.dict(["failure reason": .string("unregistered torrent")]))
        XCTAssertThrowsError(try HTTPTrackerClient.parse(failure))

        let hash = InfoHash(hex: "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c")!
        let client = HTTPTrackerClient(announce: URL(string: "https://tracker.example.com/announce?key=1")!, transport: RangeServer(files: [:]))
        let request = client.request(.init(infoHash: hash, peerID: Data(repeating: 0x41, count: 20)))!
        XCTAssertTrue(request.url!.absoluteString.contains("info_hash=%DD%82U%EC%DC%7C%A5_%B0%BB%F8%13%23%D8pb%DB%1Fm%1C"))
        XCTAssertTrue(request.url!.absoluteString.hasPrefix("https://tracker.example.com/announce?key=1&"))
    }

    func testWebSeedURLs() throws {
        let t = SyntheticTorrent(name: "My Film", files: [(["Sub dir", "Film #1.mp4"], randomData(10, seed: 1))])
        let info = try TorrentMetainfo.parse(torrentFile: t.torrentFile)
        let client = WebSeedClient(base: URL(string: "https://seed.example.com/files/")!, transport: RangeServer(files: [:]))
        XCTAssertEqual(client.url(for: info.files[0], in: info)?.absoluteString,
                       "https://seed.example.com/files/My%20Film/Sub%20dir/Film%20%231.mp4")

        let evil = SyntheticTorrent(files: [(["..", "x.mp4"], randomData(10, seed: 1))])
        let evilInfo = try TorrentMetainfo.parse(torrentFile: evil.torrentFile)
        XCTAssertNil(client.url(for: evilInfo.files[0], in: evilInfo), "'..' is never sent to a web seed")
    }

    func testPiecePickerStreamingOrder() throws {
        let t = SyntheticTorrent(files: [(["a.bin"], randomData(16384 * 40, seed: 9))])
        let info = try TorrentMetainfo.parse(torrentFile: t.torrentFile)
        var picker = PiecePicker(metainfo: info, readAhead: 16384 * 4)
        picker.select(file: info.files[0])
        var have = Array(repeating: false, count: 40)
        // Start and end of the file come first (MP4 headers can be at either end).
        var first: [Int] = []
        for _ in 0..<4 { first.append(picker.next(have: have, canSupply: { _ in true })!) }
        XCTAssertEqual(Set(first), [0, 1, 38, 39])
        // A seek makes the player's position urgent.
        picker.setFocus(offset: 16384 * 20)
        picker.markUrgent(20...20)
        XCTAssertEqual(picker.next(have: have, canSupply: { _ in true }), 20)
        // Then read-ahead after the new position.
        have[20] = true; picker.done(20)
        XCTAssertEqual(picker.next(have: have, canSupply: { _ in true }), 21)
        // A stalled piece is handed to another source after the timeout.
        picker.stallTimeout = 0
        XCTAssertEqual(picker.next(have: have, canSupply: { $0 == 21 }, now: Date().addingTimeInterval(1)), 21)
    }
}

// MARK: - Sessions

final class TorrentSessionTests: XCTestCase {
    private func movieTorrent() -> SyntheticTorrent {
        SyntheticTorrent(files: [
            (["info.txt"], randomData(3000, seed: 11)),
            (["Movie.mp4"], randomData(16384 * 30 + 1234, seed: 12)),
            (["Movie.en.srt"], randomData(700, seed: 13))
        ])
    }

    func testStreamFromWebSeedWithSeekPauseCancel() async throws {
        let t = movieTorrent()
        let server = RangeServer(files: t.webSeedFiles)
        let root = tempRoot()
        let engine = TorrentEngine(root: root, transport: server, peerFactory: nil)
        let session = try await engine.add(torrentFile: t.torrentFile)
        let files = await session.files()
        XCTAssertEqual(files.map(\.name), ["info.txt", "Movie.mp4", "Movie.en.srt"])

        try await session.selectFile(1)
        let movie = t.files[1].data
        // Start of the file.
        let head = try await session.read(fileIndex: 1, offset: 0, length: 4096)
        XCTAssertEqual(head, movie.prefix(4096))
        // Seek to the middle, across a piece boundary.
        let mid = try await session.read(fileIndex: 1, offset: 250_000, length: 20_000)
        XCTAssertFalse(mid.isEmpty)
        XCTAssertEqual(mid, movie.subdata(in: 250_000..<(250_000 + mid.count)))
        // End of file.
        let tail = try await session.read(fileIndex: 1, offset: Int64(movie.count - 10), length: 100)
        XCTAssertEqual(tail, movie.suffix(10))
        let eof = try await session.read(fileIndex: 1, offset: Int64(movie.count), length: 100)
        XCTAssertTrue(eof.isEmpty)

        // Pause: reads fail with an actionable error instead of hanging.
        await session.pause()
        var stats = await session.stats()
        XCTAssertEqual(stats.state, .paused)

        // Cancel and delete.
        await engine.remove(t.infoHash, deleteData: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(t.infoHash.hex).path))
        stats = await session.stats()
        XCTAssertEqual(stats.state, .failed("Cancelled"))
    }

    func testWholeFileCompletesAndDataMatches() async throws {
        let t = movieTorrent()
        let server = RangeServer(files: t.webSeedFiles)
        let engine = TorrentEngine(root: tempRoot(), transport: server, peerFactory: nil)
        let session = try await engine.add(torrentFile: t.torrentFile)
        try await session.selectFile(1)
        var collected = Data()
        while true {
            let chunk = try await session.read(fileIndex: 1, offset: Int64(collected.count), length: 65_536)
            if chunk.isEmpty { break }
            collected.append(chunk)
        }
        XCTAssertEqual(collected, t.files[1].data)
        for _ in 0..<50 {
            if case .completed = await session.stats().state { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let stats = await session.stats()
        XCTAssertEqual(stats.state, .completed)
        XCTAssertEqual(stats.progress, 1)
    }

    func testCorruptDataIsRejected() async throws {
        let t = movieTorrent()
        let server = RangeServer(files: t.webSeedFiles)
        server.corrupt = true
        let engine = TorrentEngine(root: tempRoot(), transport: server, peerFactory: nil)
        let session = try await engine.add(torrentFile: t.torrentFile)
        try await session.selectFile(1)
        do {
            _ = try await session.read(fileIndex: 1, offset: 0, length: 100, timeout: 1)
            XCTFail("corrupt data must never be returned")
        } catch {
            XCTAssertEqual(error as? TorrentError, .timedOut)
        }
        // Once the source is fixed, the same read succeeds.
        server.corrupt = false
        let ok = try await session.read(fileIndex: 1, offset: 0, length: 100, timeout: 40)
        XCTAssertEqual(ok, t.files[1].data.prefix(100))
    }

    func testInterruptedConnectionThenRecovery() async throws {
        let t = movieTorrent()
        let server = RangeServer(files: t.webSeedFiles)
        let engine = TorrentEngine(root: tempRoot(), transport: server, peerFactory: nil)
        let session = try await engine.add(torrentFile: t.torrentFile)
        try await session.selectFile(1)
        server.online = false
        do {
            _ = try await session.read(fileIndex: 1, offset: 100_000, length: 100, timeout: 1)
            XCTFail("expected a timeout while offline")
        } catch {
            XCTAssertEqual(error as? TorrentError, .timedOut)
        }
        let offlineStats = await session.stats()
        XCTAssertNotNil(offlineStats.lastError, "the UI gets an explanation")
        server.online = true
        let data = try await session.read(fileIndex: 1, offset: 100_000, length: 100, timeout: 60)
        XCTAssertEqual(data, t.files[1].data.subdata(in: 100_000..<100_100))
    }

    func testRelaunchRestoresVerifiedPiecesWithoutNetwork() async throws {
        let t = movieTorrent()
        let server = RangeServer(files: t.webSeedFiles)
        let root = tempRoot()
        do {
            let engine = TorrentEngine(root: root, transport: server, peerFactory: nil)
            let session = try await engine.add(torrentFile: t.torrentFile)
            try await session.selectFile(1)
            _ = try await session.read(fileIndex: 1, offset: 0, length: 40_000)
            await engine.suspendAll()
        }
        // "Relaunch": a new engine over the same folder, with the network gone.
        server.online = false
        let engine = TorrentEngine(root: root, transport: server, peerFactory: nil)
        await engine.restore()
        let summaries = await engine.summaries()
        XCTAssertEqual(summaries.map(\.infoHash), [t.infoHash])
        let maybeRestored = await engine.session(t.infoHash)
        let restored = try XCTUnwrap(maybeRestored)
        let files = await restored.files()
        XCTAssertEqual(files.count, 3)
        let data = try await restored.read(fileIndex: 1, offset: 0, length: 16_000, timeout: 2)
        XCTAssertEqual(data, t.files[1].data.prefix(16_000))
        let used = await engine.usedBytes()
        XCTAssertGreaterThan(used, 0)
    }

    func testDamagedDataIsReverifiedAfterRelaunch() async throws {
        let t = movieTorrent()
        let server = RangeServer(files: t.webSeedFiles)
        let root = tempRoot()
        do {
            let engine = TorrentEngine(root: root, transport: server, peerFactory: nil)
            let session = try await engine.add(torrentFile: t.torrentFile)
            try await session.selectFile(1)
            _ = try await session.read(fileIndex: 1, offset: 0, length: 1000)
            await engine.suspendAll()
        }
        // Damage the stored data (for example a crash mid-write).
        let dataFile = root.appendingPathComponent(t.infoHash.hex).appendingPathComponent("data.bin")
        let handle = try FileHandle(forUpdating: dataFile)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(repeating: 0, count: 64))
        try handle.close()
        server.online = false
        let engine = TorrentEngine(root: root, transport: server, peerFactory: nil)
        await engine.restore()
        let maybeSession = await engine.session(t.infoHash)
        let session = try XCTUnwrap(maybeSession)
        do {
            _ = try await session.read(fileIndex: 1, offset: 0, length: 100, timeout: 1)
            XCTFail("damaged piece must not be served")
        } catch {
            XCTAssertEqual(error as? TorrentError, .timedOut)
        }
    }

    func testStorageLimitAndLowSpace() async throws {
        let t = movieTorrent()
        let server = RangeServer(files: t.webSeedFiles)
        var settings = TorrentSettings()
        settings.storageLimit = 10_000  // smaller than one piece
        settings.reserveFreeSpace = 0
        let engine = TorrentEngine(root: tempRoot(), settings: settings, transport: server, peerFactory: nil)
        let session = try await engine.add(torrentFile: t.torrentFile)
        try await session.selectFile(1)
        do {
            _ = try await session.read(fileIndex: 1, offset: 300_000, length: 100, timeout: 5)
            XCTFail("expected the limit to stop the download")
        } catch {
            XCTAssertTrue([.paused, .timedOut].contains(error as? TorrentError))
        }
        let stats = await session.stats()
        XCTAssertEqual(stats.state, .paused)
        XCTAssertTrue(stats.lastError?.contains("limit") == true)

        // Nearly full device: 1 MB free, 2 GB reserve.
        let low = TorrentEngine(root: tempRoot(), transport: server, peerFactory: nil, freeSpace: { _ in 1_000_000 })
        let s2 = try await low.add(torrentFile: t.torrentFile)
        try await s2.selectFile(1)
        _ = try? await s2.read(fileIndex: 1, offset: 0, length: 10, timeout: 5)
        let lowStats = await s2.stats()
        XCTAssertTrue(lowStats.lastError?.contains("Not enough free space") == true)
    }

    func testCleanupRemovesLeastRecentlyUsed() async throws {
        let a = movieTorrent()
        let b = SyntheticTorrent(name: "Other", files: [(["Other.mp4"], randomData(16384 * 4, seed: 20))])
        let server = RangeServer(files: a.webSeedFiles.merging(b.webSeedFiles) { $1 })
        let engine = TorrentEngine(root: tempRoot(), transport: server, peerFactory: nil)
        let sa = try await engine.add(torrentFile: a.torrentFile)
        try await sa.selectFile(1)
        _ = try await sa.read(fileIndex: 1, offset: 0, length: 1000)
        let sb = try await engine.add(torrentFile: b.torrentFile)
        try await sb.selectFile(0)
        _ = try await sb.read(fileIndex: 0, offset: 0, length: 1000)
        let removed = await engine.cleanUp(toFit: 0, keep: [b.infoHash])
        XCTAssertEqual(removed, [a.infoHash])
        let remaining = await engine.summaries().map(\.infoHash)
        XCTAssertEqual(remaining, [b.infoHash])
    }

    func testMagnetExactSourceMustMatchHash() async throws {
        let t = movieTorrent()
        let other = SyntheticTorrent(name: "Wrong", files: [(["x.mp4"], randomData(20_000, seed: 30))])
        let server = RangeServer(files: t.webSeedFiles)
        server.extraRoutes["https://good.example.com/a.torrent"] = HTTPResponse(status: 200, body: t.torrentFile)
        server.extraRoutes["https://evil.example.com/a.torrent"] = HTTPResponse(status: 200, body: other.torrentFile)
        let engine = TorrentEngine(root: tempRoot(), transport: server, peerFactory: nil)

        let magnet = "magnet:?xt=urn:btih:\(t.infoHash.hex)&xs=https%3A%2F%2Fevil.example.com%2Fa.torrent&xs=https%3A%2F%2Fgood.example.com%2Fa.torrent"
        let session = try await engine.add(magnet: magnet)
        let info = try await session.waitForMetadata(timeout: 10)
        XCTAssertEqual(info.infoHash, t.infoHash, "the mismatching source is skipped")
        try await session.selectFile(1)
        let data = try await session.read(fileIndex: 1, offset: 0, length: 500)
        XCTAssertEqual(data, t.files[1].data.prefix(500))
    }

    func testMagnetWithoutSourcesReportsMetadataUnavailable() async throws {
        let engine = TorrentEngine(root: tempRoot(), transport: RangeServer(files: [:]), peerFactory: nil)
        let session = try await engine.add(magnet: "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c")
        do {
            _ = try await session.waitForMetadata(timeout: 0.5)
            XCTFail("expected no metadata")
        } catch {
            XCTAssertEqual(error as? TorrentError, .metadataUnavailable)
        }
        let stats = await session.stats()
        XCTAssertEqual(stats.state, .fetchingMetadata)
    }
}

// MARK: - Peer to peer

final class PeerToPeerTests: XCTestCase {
    func testMagnetMetadataAndPiecesFromAPeer() async throws {
        let t = SyntheticTorrent(files: [
            (["Movie.mp4"], randomData(16384 * 12 + 77, seed: 40)),
            (["notes.txt"], randomData(900, seed: 41))
        ], webSeed: nil)

        // Seeder: has the whole torrent and is allowed to upload.
        var seedSettings = TorrentSettings()
        seedSettings.seedAfterDownload = true
        seedSettings.uploadLimit = 0  // 0 = no uploads...
        let seederServer = RangeServer(files: [:])
        // ...so first prove the leecher gets nothing while uploading is off.
        let seedRoot = tempRoot()
        let seederEngine = TorrentEngine(root: seedRoot, settings: seedSettings, transport: seederServer, peerFactory: nil)
        let seeder = try await seederEngine.add(torrentFile: t.torrentFile)
        try await seeder.selectFile(0)
        let info = try await seeder.waitForMetadata()
        for i in 0..<info.pieceCount {
            let start = i * info.pieceLength
            let ok = await seeder.deliver(piece: i, data: t.payload.subdata(in: start..<min(start + info.pieceLength, t.payload.count)))
            XCTAssertTrue(ok)
        }

        // Leecher: only knows the magnet link and one peer.
        let pipes = PipeEnd.pair()
        let address = PeerAddress(host: "192.0.2.10", port: 6881)
        let leecherEngine = TorrentEngine(root: tempRoot(), transport: RangeServer(files: [:]),
                                          peerFactory: { $0 == address ? pipes.0 : nil })
        let leecher = try await leecherEngine.add(magnet: "magnet:?xt=urn:btih:\(t.infoHash.hex)&dn=Peer%20test")
        await seeder.acceptIncoming(pipes.1, from: PeerAddress(host: "192.0.2.20", port: 50000))
        await leecher.addPeers([address])

        // Metadata comes over BEP 9 even with uploads off (it is not file data).
        let got = try await leecher.waitForMetadata(timeout: 10)
        XCTAssertEqual(got.infoHash, t.infoHash)
        XCTAssertEqual(got.files.map(\.name), ["Movie.mp4", "notes.txt"])
        try await leecher.selectFile(0)
        do {
            _ = try await leecher.read(fileIndex: 0, offset: 0, length: 100, timeout: 1)
            XCTFail("with uploads off the seeder must not send file data")
        } catch {
            XCTAssertEqual(error as? TorrentError, .timedOut)
        }
        await seederEngine.remove(t.infoHash, deleteData: false)
        await leecherEngine.remove(t.infoHash, deleteData: true)

        // Now allow uploads and stream the file over the peer connection, including a seek.
        seedSettings.uploadLimit = 10 * 1024 * 1024
        let seederEngine2 = TorrentEngine(root: seedRoot, settings: seedSettings, transport: seederServer, peerFactory: nil)
        await seederEngine2.restore()
        let maybeSeeder = await seederEngine2.session(t.infoHash)
        let seeder2 = try XCTUnwrap(maybeSeeder)
        await seeder2.start()
        let pipes2 = PipeEnd.pair()
        let leecherEngine2 = TorrentEngine(root: tempRoot(), transport: RangeServer(files: [:]),
                                           peerFactory: { $0 == address ? pipes2.0 : nil })
        let leecher2 = try await leecherEngine2.add(magnet: "magnet:?xt=urn:btih:\(t.infoHash.hex)")
        await seeder2.acceptIncoming(pipes2.1, from: PeerAddress(host: "192.0.2.20", port: 50000))
        await leecher2.addPeers([address])
        _ = try await leecher2.waitForMetadata(timeout: 10)
        try await leecher2.selectFile(0)
        let movie = t.files[0].data
        let seek = try await leecher2.read(fileIndex: 0, offset: 150_000, length: 1000, timeout: 20)
        XCTAssertEqual(seek, movie.subdata(in: 150_000..<(150_000 + seek.count)))
        let head = try await leecher2.read(fileIndex: 0, offset: 0, length: 1000, timeout: 20)
        XCTAssertEqual(head, movie.prefix(1000))
        let leecherStats = await leecher2.stats()
        XCTAssertEqual(leecherStats.connectedPeers, 1)
        let seederStats = await seeder2.stats()
        XCTAssertGreaterThan(seederStats.uploadedBytes, 0)
        await leecherEngine2.remove(t.infoHash)
        await seederEngine2.remove(t.infoHash)
    }

    func testPeerSendingBadMetadataIsIgnored() async throws {
        let t = SyntheticTorrent(files: [(["a.mp4"], randomData(20_000, seed: 50))], webSeed: nil)
        let engine = TorrentEngine(root: tempRoot(), transport: RangeServer(files: [:]), peerFactory: nil)
        let session = try await engine.add(magnet: "magnet:?xt=urn:btih:\(t.infoHash.hex)")
        var tampered = t.infoDictionary
        tampered[tampered.count - 3] ^= 0x01
        let accepted = await session.acceptMetadata(tampered)
        XCTAssertFalse(accepted)
        let stillNone = await session.currentMetainfo
        XCTAssertNil(stillNone)
        let good = await session.acceptMetadata(t.infoDictionary)
        XCTAssertTrue(good)
    }

    func testWireMessagesRoundTripAndLimits() throws {
        let messages: [PeerMessage] = [.choke, .unchoke, .interested, .have(7), .bitfield(Data([0xF0])),
                                       .request(index: 1, begin: 16384, length: 16384), .piece(index: 2, begin: 0, block: Data([1, 2, 3])),
                                       .extended(id: 3, payload: Data("d1:ai1ee".utf8))]
        for m in messages {
            let encoded = m.encoded()
            XCTAssertEqual(try PeerMessage.decode(encoded.dropFirst(4)), m)
        }
        XCTAssertThrowsError(try PeerMessage.decode(Data([4, 0, 0])))
        let hash = InfoHash(hex: "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c")!
        let handshake = Handshake.make(infoHash: hash, peerID: Data(repeating: 1, count: 20))
        XCTAssertEqual(handshake.count, 68)
        XCTAssertTrue(try Handshake.parse(handshake, expecting: hash).0)
        XCTAssertThrowsError(try Handshake.parse(handshake, expecting: InfoHash(hex: String(repeating: "0", count: 40))!))
    }
}

// MARK: - Providers

final class TorrentProviderTests: XCTestCase {
    func testInternetArchiveParsing() throws {
        let json = """
        {"response":{"docs":[
          {"identifier":"BigBuckBunny_124","title":"Big Buck Bunny","year":"2008","licenseurl":"http://creativecommons.org/licenses/by/3.0/"},
          {"identifier":"night_film","title":["Night Film"],"licenseurl":"http://creativecommons.org/publicdomain/mark/1.0/"},
          {"identifier":"../../evil","title":"Bad id"}
        ]}}
        """
        let results = try InternetArchiveProvider.parse(Data(json.utf8))
        XCTAssertEqual(results.map(\.title), ["Big Buck Bunny", "Night Film"])
        XCTAssertEqual(results[0].license, "CC BY 3.0")
        XCTAssertEqual(results[1].license, "Public domain")
        XCTAssertEqual(results[0].torrentURL?.absoluteString, "https://archive.org/download/BigBuckBunny_124/BigBuckBunny_124_archive.torrent")

        let request = InternetArchiveProvider().request(for: "bunny\" OR identifier:*")
        let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "q" }!.value!
        XCTAssertTrue(q.contains("licenseurl:*publicdomain*"))
        XCTAssertFalse(q.contains("identifier:*"), "query syntax from the user is stripped")
    }

    func testRSSFeedParsing() {
        let xml = """
        <?xml version="1.0"?>
        <!DOCTYPE rss [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
        <rss><channel>
          <item><title>Release 1.0 &xxe;</title><enclosure url="https://example.org/r1.torrent" type="application/x-bittorrent"/></item>
          <item><title>Magnet item</title><link>magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c</link></item>
          <item><title>Plain HTTP</title><enclosure url="http://example.org/r2.torrent" type="application/x-bittorrent"/></item>
          <item><title>No torrent</title><link>https://example.org</link></item>
        </channel></rss>
        """
        let items = RSSTorrentParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].torrentURL?.absoluteString, "https://example.org/r1.torrent")
        XCTAssertFalse(items[0].title.contains("root:"), "external entities are never resolved")
        XCTAssertNotNil(items[1].magnet)
    }
}
