// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// TCP connections to peers with Apple's Network framework (iOS, iPadOS, tvOS, macOS).
// Outgoing only: CasaPlay does not open a listening port.

#if canImport(Network)
import Foundation
import Network

public final class NetworkPeerTransport: PeerTransport, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "casaplay.peer")
    private let lock = NSLock()
    private var connectContinuation: CheckedContinuation<Void, Error>?

    public init?(address: PeerAddress) {
        guard let port = NWEndpoint.Port(rawValue: address.port) else { return nil }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.prohibitExpensivePaths = false
        connection = NWConnection(host: NWEndpoint.Host(address.host), port: port, using: params)
    }

    public static let factory: PeerTransportFactory = { NetworkPeerTransport(address: $0) }

    public func connect() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.withLock { connectContinuation = c }
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                let pending: CheckedContinuation<Void, Error>? = self.lock.withLock {
                    switch state {
                    case .ready, .failed, .cancelled, .waiting:
                        let c = self.connectContinuation
                        self.connectContinuation = nil
                        return c
                    default:
                        return nil
                    }
                }
                switch state {
                case .ready: pending?.resume()
                case .failed(let error), .waiting(let error):
                    pending?.resume(throwing: error)
                    if case .waiting = state { self.connection.cancel() }
                case .cancelled: pending?.resume(throwing: TorrentError.cancelled)
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }

    public func receive(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let data, !data.isEmpty { c.resume(returning: data) }
                else if isComplete { c.resume(returning: Data()) }
                else if let error { c.resume(throwing: error) }
                else { c.resume(returning: Data()) }
            }
        }
    }

    public func close() { connection.cancel() }
}
#endif
