import Foundation
import Network

/// BEP 15 tracker announces over IPv4.
struct UDPTrackerClient {
    let url: URL

    func announce(_ announce: HTTPTrackerClient.Announce) async throws -> TrackerResponse {
        guard let host = url.host, let port = NWEndpoint.Port(rawValue: UInt16(clamping: url.port ?? 80)) else {
            throw TorrentError.sourceFailed("Invalid UDP tracker address.")
        }
        let parameters = NWParameters.udp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        connection.start(queue: .global())
        defer { connection.cancel() }
        return try await withThrowingTaskGroup(of: TrackerResponse.self) { group in
            group.addTask {
                let connectID = UInt32.random(in: .min ... .max)
                var request = Data()
                Self.append(UInt64(0x41727101980), to: &request)
                Self.append(UInt32(0), to: &request)
                Self.append(connectID, to: &request)
                let reply = try await Self.exchange(request, connection: connection)
                try Self.validate(reply, action: 0, transaction: connectID, minimum: 16)

                let announceID = UInt32.random(in: .min ... .max)
                request = Data(reply[8..<16])
                Self.append(UInt32(1), to: &request)
                Self.append(announceID, to: &request)
                request.append(announce.infoHash.bytes)
                request.append(announce.peerID)
                Self.append(announce.downloaded, to: &request)
                Self.append(announce.left, to: &request)
                Self.append(announce.uploaded, to: &request)
                Self.append(UInt32(announce.event == "started" ? 2 : 0), to: &request)
                Self.append(UInt32(0), to: &request)
                Self.append(UInt32.random(in: .min ... .max), to: &request)
                Self.append(Int32(clamping: announce.numWant), to: &request)
                Self.append(announce.port, to: &request)
                let response = try await Self.exchange(request, connection: connection)
                try Self.validate(response, action: 1, transaction: announceID, minimum: 20)
                let bytes = Array(response)
                let peers = stride(from: 20, to: bytes.count - (bytes.count - 20) % 6, by: 6).compactMap { i -> PeerAddress? in
                    let port = UInt16(bytes[i + 4]) << 8 | UInt16(bytes[i + 5])
                    guard port > 0 else { return nil }
                    let host = bytes[i..<i + 4].map(String.init).joined(separator: ".")
                    return PeerAddress(host: host, port: port)
                }
                return TrackerResponse(interval: min(max(Int(Self.word(response, at: 8)), 60), 3600), peers: peers)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw TorrentError.timedOut
            }
            defer {
                group.cancelAll()
                connection.cancel()
            }
            guard let reply = try await group.next() else { throw TorrentError.timedOut }
            return reply
        }
    }

    private static func exchange(_ data: Data, connection: NWConnection) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    connection.receiveMessage { data, _, _, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? TorrentError.noSources) }
                    }
                })
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    private static func word(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func validate(_ data: Data, action: UInt32, transaction: UInt32, minimum: Int) throws {
        guard data.count >= minimum, word(data, at: 0) == action, word(data, at: 4) == transaction else {
            throw TorrentError.sourceFailed("UDP tracker sent an unexpected reply.")
        }
    }
}
