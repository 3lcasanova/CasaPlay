// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

/// Plays the tracker side of BEP 15 and records what CasaPlay sent.
private final class FakeUDPTracker: UDPExchange, @unchecked Sendable {
    var requests: [[UInt8]] = []
    var connectionID: UInt64 = 0x1122_3344_5566_7788
    var peers: [UInt8] = [10, 0, 0, 1, 0x1A, 0xE1, 192, 168, 1, 2, 0xC8, 0xD5]
    var failWith: String?
    var corruptTransaction = false
    private(set) var closed = false

    func exchange(_ request: Data, timeout: TimeInterval) async throws -> Data {
        let b = [UInt8](request)
        requests.append(b)
        let action = UInt32(b[8]) << 24 | UInt32(b[9]) << 16 | UInt32(b[10]) << 8 | UInt32(b[11])
        var tid = Array(b[12..<16])
        if corruptTransaction { tid[0] ^= 0xFF }
        if let failWith {
            return Data([0, 0, 0, 3] + tid + Array(failWith.utf8))
        }
        if action == 0 {
            return Data([0, 0, 0, 0] + tid + be(connectionID))
        }
        return Data([0, 0, 0, 1] + tid + [0, 0, 0x07, 0x08] + [0, 0, 0, 5] + [0, 0, 0, 9] + peers)
    }

    func close() { closed = true }

    private func be(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: v >> (56 - 8 * $0)) } }
}

final class UDPTrackerTests: XCTestCase {
    private let hash = InfoHash(hex: "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c")!

    private func announce() -> HTTPTrackerClient.Announce {
        HTTPTrackerClient.Announce(infoHash: hash, peerID: Data(repeating: 0x41, count: 20),
                                   uploaded: 3, downloaded: 2, left: 1_000, event: "started")
    }

    func testAcceptsOnlyUDPURLsWithPort() {
        let f: UDPExchangeFactory = { _, _ in nil }
        XCTAssertNotNil(UDPTrackerClient(announce: URL(string: "udp://tracker.opentrackr.org:1337/announce")!, factory: f))
        XCTAssertNil(UDPTrackerClient(announce: URL(string: "udp://tracker.example.org/announce")!, factory: f))
        XCTAssertNil(UDPTrackerClient(announce: URL(string: "http://tracker.example.org:80/announce")!, factory: f))
    }

    func testAnnounceReturnsPeersAndSendsWellFormedPackets() async throws {
        let tracker = FakeUDPTracker()
        let client = UDPTrackerClient(announce: URL(string: "udp://t.example:6969/announce")!,
                                      factory: { _, _ in tracker })!
        let response = try await client.announce(announce())

        XCTAssertEqual(response.peers, [PeerAddress(host: "10.0.0.1", port: 6881),
                                        PeerAddress(host: "192.168.1.2", port: 51413)])
        XCTAssertEqual(response.interval, 1800)
        XCTAssertTrue(tracker.closed)

        let connect = tracker.requests[0]
        XCTAssertEqual(connect.count, 16)
        XCTAssertEqual(Array(connect[0..<8]), [0, 0, 0x04, 0x17, 0x27, 0x10, 0x19, 0x80])

        let ann = tracker.requests[1]
        XCTAssertEqual(ann.count, 98)
        XCTAssertEqual(Array(ann[0..<8]), [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        XCTAssertEqual(Array(ann[8..<12]), [0, 0, 0, 1])
        XCTAssertEqual(Data(ann[16..<36]), hash.bytes)
        XCTAssertEqual(Array(ann[80..<84]), [0, 0, 0, 2], "event should be 'started'")
        XCTAssertEqual(Array(ann[96..<98]), [0x1A, 0xE1], "port 6881")
    }

    func testTrackerErrorIsReported() async {
        let tracker = FakeUDPTracker()
        tracker.failWith = "torrent not registered"
        let client = UDPTrackerClient(announce: URL(string: "udp://t.example:6969")!, factory: { _, _ in tracker })!
        do {
            _ = try await client.announce(announce())
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue("\(error)".contains("torrent not registered") ||
                          (error as? LocalizedError)?.errorDescription?.contains("torrent not registered") == true)
        }
    }

    func testMismatchedTransactionIsRejected() async {
        let tracker = FakeUDPTracker()
        tracker.corruptTransaction = true
        let client = UDPTrackerClient(announce: URL(string: "udp://t.example:6969")!, factory: { _, _ in tracker })!
        do {
            _ = try await client.announce(announce())
            XCTFail("expected an error")
        } catch {}
    }
}
