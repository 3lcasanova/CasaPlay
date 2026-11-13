// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// HTTP(S) tracker announces (BEP 3, compact peers BEP 23, IPv6 peers BEP 7).
// Note for privacy: every tracker and every connected peer can see this device's public IP.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PeerAddress: Hashable, Sendable, CustomStringConvertible {
    public let host: String
    public let port: UInt16
    public var description: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }
}

struct TrackerResponse: Equatable {
    var interval: Int
    var peers: [PeerAddress]
}

struct HTTPTrackerClient: Sendable {
    let announce: URL
    let transport: HTTPTransport

    struct Announce {
        var infoHash: InfoHash
        var peerID: Data
        var port: UInt16 = 6881
        var uploaded: Int64 = 0
        var downloaded: Int64 = 0
        var left: Int64 = 0
        var event: String? = "started"
        var numWant = 50
    }

    func request(_ a: Announce) -> URLRequest? {
        guard var components = URLComponents(url: announce, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? "") else { return nil }
        func raw(_ d: Data) -> String {
            d.map { b -> String in
                let c = Character(UnicodeScalar(b))
                return (c.isLetter && c.isASCII) || (c.isNumber && c.isASCII) || "-_.~".contains(c)
                    ? String(c) : String(format: "%%%02X", b)
            }.joined()
        }
        var query = [
            "info_hash=\(raw(a.infoHash.bytes))",
            "peer_id=\(raw(a.peerID))",
            "port=\(a.port)",
            "uploaded=\(a.uploaded)",
            "downloaded=\(a.downloaded)",
            "left=\(a.left)",
            "compact=1",
            "numwant=\(a.numWant)"
        ]
        if let event = a.event { query.append("event=\(event)") }
        if let existing = components.percentEncodedQuery, !existing.isEmpty { query.insert(existing, at: 0) }
        components.percentEncodedQuery = query.joined(separator: "&")
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("CasaPlay/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    func announce(_ a: Announce) async throws -> TrackerResponse {
        guard let request = request(a) else { throw TorrentError.sourceFailed("Unsupported tracker address.") }
        let response = try await transport.send(request)
        guard response.status == 200 else { throw TorrentError.sourceFailed("Tracker answered \(response.status).") }
        return try Self.parse(response.body)
    }

    static func parse(_ data: Data) throws -> TrackerResponse {
        guard data.count < 2 * 1024 * 1024, let root = try? BencodeDecoder().decode(data) else {
            throw TorrentError.sourceFailed("Tracker sent an unreadable reply.")
        }
        if let failure = root["failure reason"]?.string {
            throw TorrentError.sourceFailed("Tracker: \(failure.prefix(200))")
        }
        var peers: [PeerAddress] = []
        if let compact = root["peers"]?.data {
            let b = [UInt8](compact)
            for i in stride(from: 0, to: b.count - b.count % 6, by: 6) {
                let port = UInt16(b[i + 4]) << 8 | UInt16(b[i + 5])
                peers.append(PeerAddress(host: "\(b[i]).\(b[i + 1]).\(b[i + 2]).\(b[i + 3])", port: port))
            }
        } else if let list = root["peers"]?.list {
            for p in list {
                if let ip = p["ip"]?.string, let port = p["port"]?.int, (1...65535).contains(port) {
                    peers.append(PeerAddress(host: ip, port: UInt16(port)))
                }
            }
        }
        if let compact6 = root["peers6"]?.data {
            let b = [UInt8](compact6)
            for i in stride(from: 0, to: b.count - b.count % 18, by: 18) {
                let groups = stride(from: 0, to: 16, by: 2).map { String(format: "%x", UInt16(b[i + $0]) << 8 | UInt16(b[i + $0 + 1])) }
                let port = UInt16(b[i + 16]) << 8 | UInt16(b[i + 17])
                peers.append(PeerAddress(host: groups.joined(separator: ":"), port: port))
            }
        }
        let interval = Int(root["interval"]?.int ?? 1800)
        return TrackerResponse(interval: min(max(interval, 60), 3600), peers: peers.filter { $0.port > 0 })
    }
}
