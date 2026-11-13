// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Peer wire protocol (BEP 3), extension protocol (BEP 10) and metadata exchange (BEP 9).
// Every length and index from a peer is checked before use.

import Foundation

/// A byte stream to one peer. The app uses Network.framework; tests use an in-memory pipe.
public protocol PeerTransport: AnyObject, Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    /// Returns the next bytes, or empty data when the connection closed.
    func receive(maximumLength: Int) async throws -> Data
    func close()
}

public typealias PeerTransportFactory = @Sendable (PeerAddress) -> PeerTransport?

enum PeerMessage: Equatable {
    case keepAlive
    case choke, unchoke, interested, notInterested
    case have(Int)
    case bitfield(Data)
    case request(index: Int, begin: Int, length: Int)
    case piece(index: Int, begin: Int, block: Data)
    case cancel(index: Int, begin: Int, length: Int)
    case extended(id: UInt8, payload: Data)
    case other(UInt8)

    static let maxLength = 256 * 1024
    static let blockSize = 16 * 1024

    func encoded() -> Data {
        func u32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        var body: [UInt8]
        switch self {
        case .keepAlive: return Data(u32(0))
        case .choke: body = [0]
        case .unchoke: body = [1]
        case .interested: body = [2]
        case .notInterested: body = [3]
        case .have(let i): body = [4] + u32(i)
        case .bitfield(let d): body = [5] + [UInt8](d)
        case let .request(i, b, l): body = [6] + u32(i) + u32(b) + u32(l)
        case let .piece(i, b, block): body = [7] + u32(i) + u32(b) + [UInt8](block)
        case let .cancel(i, b, l): body = [8] + u32(i) + u32(b) + u32(l)
        case let .extended(id, payload): body = [20, id] + [UInt8](payload)
        case .other(let id): body = [id]
        }
        return Data(u32(body.count) + body)
    }

    static func decode(_ body: Data) throws -> PeerMessage {
        let b = [UInt8](body)
        guard let id = b.first else { return .keepAlive }
        func u32(_ at: Int) throws -> Int {
            guard at + 4 <= b.count else { throw TorrentError.sourceFailed("Short peer message.") }
            return Int(b[at]) << 24 | Int(b[at + 1]) << 16 | Int(b[at + 2]) << 8 | Int(b[at + 3])
        }
        switch id {
        case 0: return .choke
        case 1: return .unchoke
        case 2: return .interested
        case 3: return .notInterested
        case 4: return .have(try u32(1))
        case 5: return .bitfield(Data(b[1...]))
        case 6: return .request(index: try u32(1), begin: try u32(5), length: try u32(9))
        case 7:
            guard b.count >= 9 else { throw TorrentError.sourceFailed("Short piece message.") }
            return .piece(index: try u32(1), begin: try u32(5), block: Data(b[9...]))
        case 8: return .cancel(index: try u32(1), begin: try u32(5), length: try u32(9))
        case 20:
            guard b.count >= 2 else { throw TorrentError.sourceFailed("Short extended message.") }
            return .extended(id: b[1], payload: Data(b[2...]))
        default: return .other(id)
        }
    }
}

enum Handshake {
    static let protocolName = Array("BitTorrent protocol".utf8)

    static func make(infoHash: InfoHash, peerID: Data) -> Data {
        var reserved = [UInt8](repeating: 0, count: 8)
        reserved[5] |= 0x10  // BEP 10 extension protocol
        return Data([19] + protocolName + reserved) + infoHash.bytes + peerID
    }

    /// Validates a 68-byte handshake and returns (supportsExtensions, remote peer ID).
    static func parse(_ data: Data, expecting hash: InfoHash) throws -> (Bool, Data) {
        let b = [UInt8](data)
        guard b.count == 68, b[0] == 19, Array(b[1..<20]) == protocolName else {
            throw TorrentError.sourceFailed("Not a BitTorrent peer.")
        }
        guard Data(b[28..<48]) == hash.bytes else { throw TorrentError.sourceFailed("Peer is on another torrent.") }
        return (b[25] & 0x10 != 0, Data(b[48..<68]))
    }
}

/// Buffers a byte stream into handshake and length-prefixed messages.
final class MessageReader {
    private let transport: PeerTransport
    private var buffer = Data()

    init(transport: PeerTransport) { self.transport = transport }

    func read(exactly count: Int) async throws -> Data {
        while buffer.count < count {
            let chunk = try await transport.receive(maximumLength: 64 * 1024)
            guard !chunk.isEmpty else { throw TorrentError.sourceFailed("Peer disconnected.") }
            buffer.append(chunk)
        }
        let out = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(out)
    }

    func next() async throws -> PeerMessage {
        let header = [UInt8](try await read(exactly: 4))
        let length = Int(header[0]) << 24 | Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
        guard length <= PeerMessage.maxLength else { throw TorrentError.sourceFailed("Peer sent an oversized message.") }
        if length == 0 { return .keepAlive }
        return try PeerMessage.decode(try await read(exactly: length))
    }
}

/// What a peer connection needs from its torrent session.
protocol PeerHost: Actor {
    var currentMetainfo: TorrentMetainfo? { get }
    var infoHash: InfoHash { get }
    var localPeerID: Data { get }
    func acceptMetadata(_ info: Data) async -> Bool
    func peerAvailability(add pieces: [Int])
    func nextPiece(peerHas: [Bool]) -> Int?
    func releasePiece(_ index: Int)
    func deliver(piece: Int, data: Data) async -> Bool
    func uploadBlock(index: Int, begin: Int, length: Int) async -> Data?
    var wantsUploadSlot: Bool { get }
    /// Our verified pieces, or nil when uploading is off (then nothing is advertised).
    var advertisedBitfield: Data? { get }
    func peerConnected(_ connection: PeerConnection)
    func peerDisconnected(_ connection: PeerConnection)
}

/// One connection to one peer: downloads pieces, answers metadata and block requests.
actor PeerConnection {
    nonisolated let address: PeerAddress
    private let transport: PeerTransport
    private weak var host: (any PeerHost)?
    private let reader: MessageReader

    private var peerChoking = true
    private var amChoking = true
    private var peerInterested = false
    private var amInterested = false
    private var peerHas: [Bool] = []
    private var pendingBitfield: Data?
    private var remoteMetadataID: UInt8?
    private var remoteMetadataSize: Int?
    private var metadataPieces: [Int: Data] = [:]

    private var currentPiece: Int?
    private var pieceBuffer = Data()
    private var received = Set<Int>()
    private var outstanding = 0
    private var nextBegin = 0
    private let pipeline = 12

    private static let localMetadataID: UInt8 = 2

    init(address: PeerAddress, transport: PeerTransport, host: any PeerHost) {
        self.address = address
        self.transport = transport
        self.host = host
        self.reader = MessageReader(transport: transport)
    }

    /// Runs until the peer disconnects or the task is cancelled.
    func run() async {
        guard let host else { return }
        do {
            try await transport.connect()
            let hash = await host.infoHash
            try await transport.send(Handshake.make(infoHash: hash, peerID: await host.localPeerID))
            let (extensions, _) = try Handshake.parse(try await reader.read(exactly: 68), expecting: hash)
            await host.peerConnected(self)
            if extensions { try await sendExtendedHandshake() }
            if let bits = await host.advertisedBitfield {
                try await transport.send(PeerMessage.bitfield(bits).encoded())
            }
            if let info = await host.currentMetainfo { peerHas = Array(repeating: false, count: info.pieceCount) }
            try await pump()
            while !Task.isCancelled {
                let message = try await reader.next()
                try await handle(message)
                try await pump()
            }
        } catch {
            // Disconnected or misbehaving peer: drop it quietly.
        }
        if let piece = currentPiece { await host.releasePiece(piece) }
        transport.close()
        await host.peerDisconnected(self)
    }

    nonisolated func stop() { transport.close() }

    func sendHave(_ index: Int) async {
        try? await transport.send(PeerMessage.have(index).encoded())
    }

    /// Called when metadata arrived from elsewhere.
    func metadataReady(pieceCount: Int) async {
        if peerHas.count != pieceCount {
            peerHas = pendingBitfield.map { PieceStore.bools(fromBitfield: $0, count: pieceCount) }
                ?? Array(repeating: false, count: pieceCount)
            await host?.peerAvailability(add: peerHas.indices.filter { peerHas[$0] })
        }
        try? await pump()
    }

    // MARK: Messages

    private func handle(_ message: PeerMessage) async throws {
        guard let host else { return }
        switch message {
        case .keepAlive, .other, .cancel: break
        case .choke:
            peerChoking = true
            if let piece = currentPiece { await host.releasePiece(piece) }
            resetPiece()
        case .unchoke:
            peerChoking = false
        case .interested:
            peerInterested = true
            if amChoking, await host.wantsUploadSlot {
                amChoking = false
                try await transport.send(PeerMessage.unchoke.encoded())
            }
        case .notInterested:
            peerInterested = false
        case .have(let i):
            if i >= 0, i < peerHas.count, !peerHas[i] {
                peerHas[i] = true
                await host.peerAvailability(add: [i])
            }
        case .bitfield(let bits):
            guard bits.count <= 1 << 20 else { throw TorrentError.sourceFailed("Bitfield too large.") }
            if peerHas.isEmpty {
                pendingBitfield = bits
            } else {
                peerHas = PieceStore.bools(fromBitfield: bits, count: peerHas.count)
                await host.peerAvailability(add: peerHas.indices.filter { peerHas[$0] })
            }
        case let .request(index, begin, length):
            guard !amChoking, length > 0, length <= PeerMessage.blockSize else { return }
            if let block = await host.uploadBlock(index: index, begin: begin, length: length) {
                try await transport.send(PeerMessage.piece(index: index, begin: begin, block: block).encoded())
            }
        case let .piece(index, begin, block):
            guard index == currentPiece, begin >= 0, begin % PeerMessage.blockSize == 0,
                  begin + block.count <= pieceBuffer.count, !received.contains(begin) else { return }
            pieceBuffer.replaceSubrange(begin..<(begin + block.count), with: block)
            received.insert(begin)
            outstanding = max(outstanding - 1, 0)
            if received.count == Int((pieceBuffer.count + PeerMessage.blockSize - 1) / PeerMessage.blockSize) {
                let data = pieceBuffer
                resetPiece()
                _ = await host.deliver(piece: index, data: data)
            }
        case let .extended(id, payload):
            try await handleExtended(id: id, payload: payload)
        }
    }

    private func resetPiece() {
        currentPiece = nil
        pieceBuffer = Data()
        received = []
        outstanding = 0
        nextBegin = 0
    }

    /// Keeps requests flowing.
    private func pump() async throws {
        guard let host else { return }
        if await host.currentMetainfo == nil {
            try await requestMetadataIfPossible()
            return
        }
        let wantSomething = peerHas.contains(true)
        if wantSomething != amInterested {
            amInterested = wantSomething
            try await transport.send((wantSomething ? PeerMessage.interested : .notInterested).encoded())
        }
        guard !peerChoking, let info = await host.currentMetainfo else { return }
        if currentPiece == nil {
            guard let piece = await host.nextPiece(peerHas: peerHas) else { return }
            currentPiece = piece
            pieceBuffer = Data(count: info.pieceSize(piece))
        }
        guard let piece = currentPiece else { return }
        while outstanding < pipeline, nextBegin < pieceBuffer.count {
            let length = min(PeerMessage.blockSize, pieceBuffer.count - nextBegin)
            try await transport.send(PeerMessage.request(index: piece, begin: nextBegin, length: length).encoded())
            nextBegin += length
            outstanding += 1
        }
    }

    // MARK: Extensions and metadata

    private func sendExtendedHandshake() async throws {
        guard let host else { return }
        var fields: [String: BValue] = [
            "m": .dict(["ut_metadata": .int(Int64(Self.localMetadataID))]),
            "v": .string("CasaPlay 0.1"),
            "reqq": .int(Int64(pipeline))
        ]
        if let info = await host.currentMetainfo {
            fields["metadata_size"] = .int(Int64(info.infoDictionary.count))
        }
        try await transport.send(PeerMessage.extended(id: 0, payload: BencodeEncoder.encode(.dict(fields))).encoded())
    }

    private func handleExtended(id: UInt8, payload: Data) async throws {
        guard let host else { return }
        if id == 0 {
            guard let dict = try? BencodeDecoder().decode(payload) else { return }
            if let remote = dict["m"]?["ut_metadata"]?.int, (1...255).contains(remote) {
                remoteMetadataID = UInt8(remote)
            }
            if let size = dict["metadata_size"]?.int, size > 0, size <= 16 * 1024 * 1024 {
                remoteMetadataSize = Int(size)
            }
            return
        }
        guard id == Self.localMetadataID,
              let (header, used) = try? BencodeDecoder().decodePrefix(payload),
              let type = header["msg_type"]?.int, let piece = header["piece"]?.int, piece >= 0 else { return }
        switch type {
        case 0:  // a request for our metadata
            guard let remoteID = remoteMetadataID else { return }
            if let info = await host.currentMetainfo, Int(piece) * PeerMessage.blockSize < info.infoDictionary.count {
                let start = Int(piece) * PeerMessage.blockSize
                let slice = info.infoDictionary.subdata(in: start..<min(start + PeerMessage.blockSize, info.infoDictionary.count))
                let head = BencodeEncoder.encode(.dict([
                    "msg_type": .int(1), "piece": .int(piece), "total_size": .int(Int64(info.infoDictionary.count))
                ]))
                try await transport.send(PeerMessage.extended(id: remoteID, payload: head + slice).encoded())
            } else {
                let reject = BencodeEncoder.encode(.dict(["msg_type": .int(2), "piece": .int(piece)]))
                try await transport.send(PeerMessage.extended(id: remoteID, payload: reject).encoded())
            }
        case 1:  // metadata data
            guard let size = remoteMetadataSize, Int(piece) < (size + PeerMessage.blockSize - 1) / PeerMessage.blockSize else { return }
            metadataPieces[Int(piece)] = payload.subdata(in: used..<payload.count)
            let count = (size + PeerMessage.blockSize - 1) / PeerMessage.blockSize
            if metadataPieces.count == count {
                let assembled = (0..<count).reduce(into: Data()) { $0.append(metadataPieces[$1] ?? Data()) }
                metadataPieces = [:]
                if assembled.count == size, await host.acceptMetadata(assembled) == false {
                    remoteMetadataID = nil  // this peer sent bad metadata; don't ask again
                }
            }
        default:
            break
        }
    }

    private var requestedMetadata = false

    private func requestMetadataIfPossible() async throws {
        guard !requestedMetadata, let remoteID = remoteMetadataID, let size = remoteMetadataSize else { return }
        requestedMetadata = true
        for piece in 0..<((size + PeerMessage.blockSize - 1) / PeerMessage.blockSize) {
            let message = BencodeEncoder.encode(.dict(["msg_type": .int(0), "piece": .int(Int64(piece))]))
            try await transport.send(PeerMessage.extended(id: remoteID, payload: message).encoded())
        }
    }
}
