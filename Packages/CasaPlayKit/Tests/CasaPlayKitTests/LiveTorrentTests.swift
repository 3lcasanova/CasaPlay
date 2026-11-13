// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Live check against a real, openly licensed torrent: Big Buck Bunny (CC BY 3.0,
// Blender Foundation) on the Internet Archive. Off by default because it uses the
// network. Run with:  CASAPLAY_LIVE_TORRENT=1 swift test --filter LiveTorrentTests

import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CasaPlayKit

/// On Linux, swift-corelibs-foundation's URLSession crashes on archive.org's cross-host
/// redirects (libcurl error 43 in EasyHandle). The live test therefore uses the curl
/// command there. On Apple platforms the app's own URLSessionTransport is used.
struct CurlTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("curl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        var args = ["-sS", "-L", "--max-time", "60", "-o", out.path, "-w", "%{http_code}"]
        for (key, value) in request.allHTTPHeaderFields ?? [:] { args += ["-H", "\(key): \(value)"] }
        args.append(url.absoluteString)
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.terminationHandler = { p in
                let code = Int(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) ?? 0
                guard p.terminationStatus == 0 else {
                    continuation.resume(throwing: URLError(.cannotConnectToHost)); return
                }
                continuation.resume(returning: HTTPResponse(status: code, body: (try? Data(contentsOf: out)) ?? Data()))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

#if os(Linux)
let liveTransport: HTTPTransport = CurlTransport()
#else
let liveTransport: HTTPTransport = URLSessionTransport()
#endif

final class LiveTorrentTests: XCTestCase {
    static let torrentURL = URL(string: "https://archive.org/download/BigBuckBunny_124/BigBuckBunny_124_archive.torrent")!
    static let directMP4 = URL(string: "https://archive.org/download/BigBuckBunny_124/Content/big_buck_bunny_720p_surround.mp4")!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CASAPLAY_LIVE_TORRENT"] == "1", "live network test")
    }

    /// Fetches bytes straight from the Archive, as an independent check.
    private func direct(_ range: Range<Int64>) async throws -> Data {
        var request = URLRequest(url: Self.directMP4)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        return try await liveTransport.send(request).body
    }

    func testAddSelectBufferSeekPauseRelaunchCancel() async throws {
        let root = tempRoot()
        let clock = ContinuousClock()
        let engine = TorrentEngine(root: root, transport: liveTransport, peerFactory: nil)

        // Add → metadata.
        var t0 = clock.now
        let session = try await engine.add(torrentURL: Self.torrentURL)
        let info = try await session.waitForMetadata()
        print("LIVE metadata: \(info.name), \(info.files.count) files, \(info.pieceCount) pieces of \(info.pieceLength) B, web seeds \(info.webSeeds.map(\.absoluteString)), hash \(info.infoHash) in \(clock.now - t0)")
        let index = try XCTUnwrap(info.files.firstIndex { $0.path == "Content/big_buck_bunny_720p_surround.mp4" })
        XCTAssertEqual(info.files[index].length, 61_878_609)
        let playable = info.files.filter { MediaContainer(fileExtension: $0.fileExtension).isNativeToApplePlayer }
        print("LIVE playable by Apple's player: \(playable.map(\.path))")

        // Select → buffer the start.
        try await session.selectFile(index)
        t0 = clock.now
        var head = Data()
        while head.count < 1_000_000 {
            let chunk = try await session.read(fileIndex: index, offset: Int64(head.count), length: 1_000_000 - head.count)
            head.append(chunk)
        }
        print("LIVE first 1 MB in \(clock.now - t0)")
        XCTAssertEqual(head.subdata(in: 4..<8), Data("ftyp".utf8))
        let directHead = try await direct(0..<1_000_000)
        XCTAssertEqual(head, directHead, "matches the Archive's own file")

        // Seek to the middle and near the end.
        for offset: Int64 in [30_000_000, 61_000_000] {
            t0 = clock.now
            let chunk = try await session.read(fileIndex: index, offset: offset, length: 262_144)
            print("LIVE seek to \(offset): \(chunk.count) B in \(clock.now - t0)")
            let expected = try await direct(offset..<(offset + Int64(chunk.count)))
            XCTAssertEqual(chunk, expected)
        }
        var stats = await session.stats()
        print("LIVE stats: progress \(String(format: "%.1f", stats.progress * 100))%, \(stats.downloadedBytes) B, \(Int(stats.downloadRate)) B/s, web seeds \(stats.activeWebSeeds), peers \(stats.connectedPeers)")

        // Pause, then resume.
        await session.pause()
        do {
            _ = try await session.read(fileIndex: index, offset: 50_000_000, length: 10, timeout: 2)
            XCTFail("paused torrents don't download")
        } catch {
            XCTAssertEqual(error as? TorrentError, .paused)
        }
        await session.start()
        let resumed = try await session.read(fileIndex: index, offset: 45_000_000, length: 1000)
        XCTAssertEqual(resumed.count, 1000)

        // Suspend and "relaunch" offline: data read earlier is still there and verified.
        await engine.suspendAll()
        let offline = RangeServer(files: [:])
        offline.online = false
        let relaunched = TorrentEngine(root: root, transport: offline, peerFactory: nil)
        await relaunched.restore()
        let restoredSession = await relaunched.session(info.infoHash)
        let restored = try XCTUnwrap(restoredSession)
        let again = try await restored.read(fileIndex: index, offset: 0, length: 500_000, timeout: 5)
        XCTAssertEqual(again, head.prefix(again.count))
        stats = await restored.stats()
        print("LIVE after relaunch: progress \(String(format: "%.1f", stats.progress * 100))%, used \(await relaunched.usedBytes()) B")

        // Low storage on a fresh engine.
        let tight = TorrentEngine(root: tempRoot(), transport: liveTransport, peerFactory: nil, freeSpace: { _ in 100_000_000 })
        let s2 = try await tight.add(torrentURL: Self.torrentURL)
        try await s2.selectFile(index)
        _ = try? await s2.read(fileIndex: index, offset: 0, length: 10, timeout: 20)
        let tightStats = await s2.stats()
        print("LIVE low storage: \(tightStats.state.label) – \(tightStats.lastError ?? "no error")")
        XCTAssertTrue(tightStats.lastError?.contains("Not enough free space") == true)
        await tight.clearAll()

        // Cancel and delete.
        await relaunched.remove(info.infoHash, deleteData: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(info.infoHash.hex).path))
    }

    func testInternetArchiveProviderSearch() async throws {
        let results = try await InternetArchiveProvider(transport: liveTransport).search("big buck bunny")
        print("LIVE provider: \(results.prefix(5).map { "\($0.title) [\($0.license ?? "?")]" })")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.torrentURL?.scheme == "https" && $0.license != nil })
    }
}
