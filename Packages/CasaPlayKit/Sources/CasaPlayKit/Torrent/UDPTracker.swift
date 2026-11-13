// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// UDP tracker announces (BEP 15). Most public torrents, including Torrentio's, list
// only udp:// trackers. Replies are parsed as fixed binary records; nothing is executed.

import Foundation

/// One request/response round trip with a UDP tracker.
public protocol UDPExchange: Sendable {
    func exchange(_ request: Data, timeout: TimeInterval) async throws -> Data
    func close()
}

public typealias UDPExchangeFactory = @Sendable (_ host: String, _ port: UInt16) -> UDPExchange?

struct UDPTrackerClient: Sendable {
    static let protocolID: UInt64 = 0x41727101980
    static let attemptTimeout: TimeInterval = 8

    let host: String
    let port: UInt16
    let factory: UDPExchangeFactory

    init?(announce: URL, factory: @escaping UDPExchangeFactory) {
        guard announce.scheme?.lowercased() == "udp", let host = announce.host, !host.isEmpty,
              let port = announce.port, (1...65535).contains(port) else { return nil }
        self.host = host
        self.port = UInt16(port)
        self.factory = factory
    }

    func announce(_ a: HTTPTrackerClient.Announce) async throws -> TrackerResponse {
        guard let exchange = factory(host, port) else {
            throw TorrentError.sourceFailed("UDP trackers aren't available on this device.")
        }
        defer { exchange.close() }

        let connectID = UInt32.random(in: .min ... .max)
        let connectReply = try await exchange.exchange(Self.connectRequest(transactionID: connectID),
                                                       timeout: Self.attemptTimeout)
        let connectionID = try Self.parseConnect(connectReply, transactionID: connectID)

        let announceID = UInt32.random(in: .min ... .max)
        let request = Self.announceRequest(connectionID: connectionID, transactionID: announceID,
                                           key: UInt32.random(in: .min ... .max), announce: a)
        let reply = try await exchange.exchange(request, timeout: Self.attemptTimeout)
        return try Self.parseAnnounce(reply, transactionID: announceID)
    }

    // MARK: Packets

    static func connectRequest(transactionID: UInt32) -> Data {
        var d = Data()
        d.appendBE(protocolID)
        d.appendBE(UInt32(0))
        d.appendBE(transactionID)
        return d
    }

    static func announceRequest(connectionID: UInt64, transactionID: UInt32, key: UInt32,
                                announce a: HTTPTrackerClient.Announce) -> Data {
        let event: UInt32
        switch a.event {
        case "completed": event = 1
        case "started": event = 2
        case "stopped": event = 3
        default: event = 0
        }
        var d = Data()
        d.appendBE(connectionID)
        d.appendBE(UInt32(1))
        d.appendBE(transactionID)
        d.append(a.infoHash.bytes)
        d.append(a.peerID.prefix(20))
        d.appendBE(UInt64(max(a.downloaded, 0)))
        d.appendBE(UInt64(max(a.left, 0)))
        d.appendBE(UInt64(max(a.uploaded, 0)))
        d.appendBE(event)
        d.appendBE(UInt32(0))            // IP: let the tracker use the sender's address
        d.appendBE(key)
        d.appendBE(UInt32(bitPattern: Int32(a.numWant)))
        d.appendBE(a.port)
        return d
    }

    static func parseConnect(_ data: Data, transactionID: UInt32) throws -> UInt64 {
        let b = [UInt8](data)
        try checkHeader(b, action: 0, transactionID: transactionID, minimum: 16)
        return b.readBE64(at: 8)
    }

    static func parseAnnounce(_ data: Data, transactionID: UInt32) throws -> TrackerResponse {
        let b = [UInt8](data)
        try checkHeader(b, action: 1, transactionID: transactionID, minimum: 20)
        let interval = Int(b.readBE32(at: 8))
        var peers: [PeerAddress] = []
        var i = 20
        while i + 6 <= b.count {
            let port = UInt16(b[i + 4]) << 8 | UInt16(b[i + 5])
            if port > 0 {
                peers.append(PeerAddress(host: "\(b[i]).\(b[i + 1]).\(b[i + 2]).\(b[i + 3])", port: port))
            }
            i += 6
        }
        return TrackerResponse(interval: min(max(interval, 60), 3600), peers: peers)
    }

    private static func checkHeader(_ b: [UInt8], action: UInt32, transactionID: UInt32, minimum: Int) throws {
        guard b.count >= 8 else { throw TorrentError.sourceFailed("Tracker sent an unreadable reply.") }
        guard b.readBE32(at: 4) == transactionID else {
            throw TorrentError.sourceFailed("Tracker reply didn't match the request.")
        }
        let got = b.readBE32(at: 0)
        if got == 3 {
            let message = String(decoding: b.dropFirst(8).prefix(200), as: UTF8.self)
            throw TorrentError.sourceFailed("Tracker: \(message)")
        }
        guard got == action, b.count >= minimum else {
            throw TorrentError.sourceFailed("Tracker sent an unreadable reply.")
        }
    }
}

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

private extension Array where Element == UInt8 {
    func readBE32(at i: Int) -> UInt32 {
        (i..<i + 4).reduce(UInt32(0)) { $0 << 8 | UInt32(self[$1]) }
    }

    func readBE64(at i: Int) -> UInt64 {
        (i..<i + 8).reduce(UInt64(0)) { $0 << 8 | UInt64(self[$1]) }
    }
}

#if canImport(Network)
import Network

/// UDP tracker exchanges over Apple's Network framework.
public final class NetworkUDPExchange: UDPExchange, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "casaplay.udp-tracker")

    public init?(host: String, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connection.start(queue: queue)
    }

    public static let factory: UDPExchangeFactory = { NetworkUDPExchange(host: $0, port: $1) }

    public func exchange(_ request: Data, timeout: TimeInterval) async throws -> Data {
        let gate = OnceGate()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            queue.asyncAfter(deadline: .now() + timeout) {
                if gate.claim() { c.resume(throwing: TorrentError.sourceFailed("Tracker didn't answer.")) }
            }
            connection.send(content: request, completion: .contentProcessed { error in
                if let error, gate.claim() { c.resume(throwing: error) }
            })
            connection.receiveMessage { data, _, _, error in
                guard gate.claim() else { return }
                if let data, !data.isEmpty { c.resume(returning: data) }
                else if let error { c.resume(throwing: error) }
                else { c.resume(throwing: TorrentError.sourceFailed("Tracker sent an empty reply.")) }
            }
        }
    }

    public func close() { connection.cancel() }
}

/// Lets exactly one of several racing callbacks resume a continuation.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
#endif

public enum UDPTrackerSupport {
    /// The platform's UDP transport, or nil where none exists (Linux test runs).
    public static var defaultFactory: UDPExchangeFactory? {
        #if canImport(Network)
        return NetworkUDPExchange.factory
        #else
        return nil
        #endif
    }
}
