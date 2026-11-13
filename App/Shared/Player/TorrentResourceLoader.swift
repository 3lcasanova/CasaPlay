// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Feeds AVPlayer from a torrent. AVFoundation asks for byte ranges through
// AVAssetResourceLoader; each range is answered only with SHA-1-verified pieces.
// When a range hasn't arrived, the read waits (the engine moves those pieces to the
// front) and AVPlayer shows its normal buffering state. Seeking simply produces a
// request at a new offset, which re-prioritises the pieces around it.

import AVFoundation
import UniformTypeIdentifiers
import CasaPlayKit

private final class RequestBox: @unchecked Sendable {
    let request: AVAssetResourceLoadingRequest
    init(_ request: AVAssetResourceLoadingRequest) { self.request = request }
}

final class TorrentResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "casaplay-torrent"
    nonisolated(unsafe) static var engine: TorrentEngine?

    let queue = DispatchQueue(label: "casaplay.torrent.loader")
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// AVPlayer asks for chunks this size at most.
    private let chunkSize = 512 * 1024

    /// casaplay-torrent://<info-hash>/<file index>/<name>
    static func url(hash: InfoHash, fileIndex: Int, fileName: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = hash.hex
        let safeName = fileName.replacingOccurrences(of: "/", with: "_")
        components.path = "/\(fileIndex)/\(safeName)"
        return components.url
    }

    static func parse(_ url: URL) -> (InfoHash, Int)? {
        guard url.scheme == scheme, let host = url.host, let hash = InfoHash(hex: host.lowercased()) else { return nil }
        let parts = url.path.split(separator: "/")
        guard let first = parts.first, let index = Int(first), index >= 0 else { return nil }
        return (hash, index)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url, let parsed = Self.parse(url) else { return false }
        let (hash, index) = parsed
        let box = RequestBox(loadingRequest)
        let key = ObjectIdentifier(loadingRequest)
        let task = Task { [weak self] in
            await self?.serve(box, hash: hash, fileIndex: index)
            self?.lock.withLock { _ = self?.tasks.removeValue(forKey: key) }
        }
        lock.withLock { tasks[key] = task }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let task = lock.withLock { tasks.removeValue(forKey: ObjectIdentifier(loadingRequest)) }
        task?.cancel()
    }

    func cancelAll() {
        let all = lock.withLock { () -> [Task<Void, Never>] in
            let list = Array(tasks.values)
            tasks = [:]
            return list
        }
        all.forEach { $0.cancel() }
    }

    private func serve(_ box: RequestBox, hash: InfoHash, fileIndex: Int) async {
        let request = box.request
        do {
            guard let engine = Self.engine, let session = await engine.session(hash) else {
                throw TorrentError.sourceFailed("This torrent is no longer in CasaPlay.")
            }
            let files = await session.files()
            guard fileIndex < files.count else { throw TorrentError.fileNotSelected }
            let file = files[fileIndex]

            if let info = request.contentInformationRequest {
                let type = UTType(filenameExtension: file.fileExtension) ?? .mpeg4Movie
                queue.sync {
                    info.contentType = type.identifier
                    info.contentLength = file.length
                    info.isByteRangeAccessSupported = true
                }
            }

            if let dataRequest = request.dataRequest {
                var offset = dataRequest.currentOffset
                let end: Int64 = dataRequest.requestsAllDataToEndOfResource
                    ? file.length
                    : min(file.length, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
                var timeouts = 0
                while offset < end, !Task.isCancelled {
                    do {
                        let length = Int(min(end - offset, Int64(chunkSize)))
                        let chunk = try await session.read(fileIndex: fileIndex, offset: offset, length: length, timeout: 30)
                        if chunk.isEmpty { break }
                        guard !Task.isCancelled else { return }
                        queue.sync { dataRequest.respond(with: chunk) }
                        offset += Int64(chunk.count)
                        timeouts = 0
                    } catch TorrentError.timedOut {
                        // Keep waiting while peers are slow; give up after about two minutes.
                        timeouts += 1
                        if timeouts >= 4 { throw TorrentError.timedOut }
                    }
                }
            }
            guard !Task.isCancelled else { return }
            queue.async { request.finishLoading() }
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? "The torrent stopped sending data."
            let nsError = NSError(domain: "CasaPlay.Torrent", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            queue.async { request.finishLoading(with: nsError) }
        }
    }
}
