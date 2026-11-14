// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// VLC can't open CasaPlay's casaplay-torrent:// links: those only work through AVPlayer's
// resource loader. This serves the same SHA-1-verified torrent pieces over HTTP instead.
//
// Safety: the listener only accepts connections on the loopback interface, so nothing else on
// the network can reach it, and every address carries a random token, so other apps on the
// device can't guess one. Each request is a byte range, so VLC can seek anywhere in the file.

import Foundation
import Network
import CasaPlayKit

enum TorrentHTTPError: LocalizedError {
    case badLink
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .badLink: return "This torrent link isn't valid."
        case .serverUnavailable: return "CasaPlay couldn't start its local stream server."
        }
    }
}

final class TorrentHTTPServer: @unchecked Sendable {
    static let shared = TorrentHTTPServer()

    private struct Request {
        var method: String
        var path: String
        /// `Range: bytes=first-last`. Either end can be missing.
        var range: (first: Int64?, last: Int64?)?
    }

    private let queue = DispatchQueue(label: "casaplay.torrent.http")
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private let chunkSize = 512 * 1024

    // Confined to `queue`.
    private var listener: NWListener?
    private var readyPort: UInt16?
    private var waiters: [CheckedContinuation<UInt16, Error>] = []

    private let lock = NSLock()
    private var failure: String?
    /// The engine's own reason for the last failed read ("Paused", "timed out"…). VLC only
    /// reports "can't open", so the player asks here for the real cause.
    var lastFailureMessage: String? { lock.withLock { failure } }

    func clearFailure() { lock.withLock { failure = nil } }
    private func setFailure(_ message: String) { lock.withLock { failure = message } }

    // MARK: - Public

    /// The loopback address VLC can open for a casaplay-torrent:// link.
    func localURL(for torrentURL: URL) async throws -> URL {
        guard let (hash, index) = TorrentResourceLoader.parse(torrentURL) else { throw TorrentHTTPError.badLink }
        let port = try await ensureRunning()
        clearFailure()
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/\(token)/\(hash.hex)/\(index)/\(torrentURL.lastPathComponent)"
        guard let url = components.url else { throw TorrentHTTPError.badLink }
        return url
    }

    // MARK: - Listener

    private func ensureRunning() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            queue.async {
                if let port = self.readyPort {
                    continuation.resume(returning: port)
                    return
                }
                self.waiters.append(continuation)
                if self.listener == nil { self.startListener() }
            }
        }
    }

    /// Runs on `queue`.
    private func startListener() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                // Ignore news from a listener that was already replaced.
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        self.readyPort = port
                        self.finishWaiters(.success(port))
                    } else {
                        self.tearDown()
                        self.finishWaiters(.failure(TorrentHTTPError.serverUnavailable))
                    }
                case .failed, .cancelled:
                    self.tearDown()
                    self.finishWaiters(.failure(TorrentHTTPError.serverUnavailable))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            finishWaiters(.failure(error))
        }
    }

    /// Runs on `queue`. The next `ensureRunning` starts a fresh listener.
    private func tearDown() {
        listener?.cancel()
        listener = nil
        readyPort = nil
    }

    private func finishWaiters(_ result: Result<UInt16, Error>) {
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume(with: result) }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        let task = Task { [weak self] in
            await self?.handle(connection)
            await Self.finish(connection)
        }
        // When VLC closes the connection (it does on every seek), stop reading pieces for it.
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: task.cancel()
            default: break
            }
        }
    }

    private func handle(_ connection: NWConnection) async {
        guard let request = await Self.readRequest(connection) else { return }
        guard request.method == "GET" || request.method == "HEAD" else {
            await Self.respond(connection, status: "405 Method Not Allowed")
            return
        }
        guard let target = resolve(request.path),
              let engine = TorrentResourceLoader.engine,
              let session = await engine.session(target.hash) else {
            await Self.respond(connection, status: "404 Not Found")
            return
        }
        let files = await session.files()
        guard target.index < files.count else {
            await Self.respond(connection, status: "404 Not Found")
            return
        }
        let total = files[target.index].length

        // Work out which bytes were asked for.
        var first: Int64 = 0
        var last: Int64 = max(total - 1, 0)
        var isPartial = false
        if let range = request.range {
            isPartial = true
            if let start = range.first {
                first = start
                if let end = range.last { last = min(end, total - 1) }
            } else if let suffix = range.last {
                first = max(total - suffix, 0)
            }
            if total == 0 || first >= total || first > last {
                await Self.respond(connection, status: "416 Range Not Satisfiable",
                                   headers: ["Content-Range": "bytes */\(total)"])
                return
            }
        }
        let count = total == 0 ? 0 : last - first + 1

        var headers = [
            "Content-Type": "application/octet-stream",
            "Accept-Ranges": "bytes",
            "Content-Length": String(count)
        ]
        if isPartial { headers["Content-Range"] = "bytes \(first)-\(last)/\(total)" }
        do {
            try await Self.sendHead(connection, status: isPartial ? "206 Partial Content" : "200 OK", headers: headers)
        } catch { return }
        guard request.method == "GET", count > 0 else { return }

        var offset = first
        let stop = first + count
        var timeouts = 0
        while offset < stop, !Task.isCancelled {
            let chunk: Data
            do {
                let length = Int(min(stop - offset, Int64(chunkSize)))
                chunk = try await session.read(fileIndex: target.index, offset: offset, length: length, timeout: 30)
            } catch TorrentError.timedOut {
                // Keep waiting while peers are slow; give up after about two minutes.
                timeouts += 1
                if timeouts >= 4 {
                    setFailure("The torrent stopped sending data.")
                    return
                }
                continue
            } catch {
                guard !Task.isCancelled else { return }
                setFailure((error as? LocalizedError)?.errorDescription ?? "The torrent stopped sending data.")
                return
            }
            if chunk.isEmpty { return }
            timeouts = 0
            do { try await Self.send(connection, data: chunk) } catch { return }  // the player went away
            offset += Int64(chunk.count)
        }
    }

    /// `/<token>/<info hash>/<file index>/<name>`
    private func resolve(_ path: String) -> (hash: InfoHash, index: Int)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3,
              String(parts[0]) == token,
              let hash = InfoHash(hex: parts[1].lowercased()),
              let index = Int(parts[2]), index >= 0 else { return nil }
        return (hash, index)
    }

    // MARK: - HTTP helpers

    private static func readRequest(_ connection: NWConnection) async -> Request? {
        let terminator = Data("\r\n\r\n".utf8)
        var buffer = Data()
        while buffer.range(of: terminator) == nil {
            guard buffer.count < 16_384, let chunk = await receive(connection) else { return nil }
            buffer.append(chunk)
        }
        guard let end = buffer.range(of: terminator),
              let text = String(data: buffer[..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count >= 2 else { return nil }

        var request = Request(method: start[0].uppercased(), path: String(start[1]), range: nil)
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "range" { request.range = parseRange(value) }
        }
        return request
    }

    /// "bytes=100-", "bytes=100-199" or "bytes=-500". Only the first range is used.
    private static func parseRange(_ value: String) -> (first: Int64?, last: Int64?)? {
        guard value.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = value.dropFirst("bytes=".count).split(separator: ",").first ?? ""
        let ends = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard ends.count == 2 else { return nil }
        let first = Int64(ends[0].trimmingCharacters(in: .whitespaces))
        let last = Int64(ends[1].trimmingCharacters(in: .whitespaces))
        guard first != nil || last != nil else { return nil }
        return (first, last)
    }

    private static func receive(_ connection: NWConnection) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func send(_ connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func sendHead(_ connection: NWConnection, status: String, headers: [String: String]) async throws {
        var head = "HTTP/1.1 \(status)\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "Connection: close\r\n\r\n"
        try await send(connection, data: Data(head.utf8))
    }

    /// A short answer with no body, for errors.
    private static func respond(_ connection: NWConnection, status: String, headers: [String: String] = [:]) async {
        var all = headers
        all["Content-Length"] = "0"
        try? await sendHead(connection, status: status, headers: all)
    }

    /// Flushes what is queued, then closes.
    private static func finish(_ connection: NWConnection) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
        connection.cancel()
    }
}
