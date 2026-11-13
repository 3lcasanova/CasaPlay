// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// BEP 19 web seeds: plain HTTPS servers that hold the same files. Internet Archive
// torrents rely on them. Each piece is fetched with HTTP range requests and then
// checked against the torrent's SHA-1 like any piece from a peer.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct WebSeedClient: Sendable {
    let base: URL
    let transport: HTTPTransport

    /// URL of one file on this web seed, following BEP 19.
    func url(for file: TorrentFile, in metainfo: TorrentMetainfo) -> URL? {
        var text = base.absoluteString
        guard text.hasSuffix("/") else {
            // A URL without a trailing slash names the file itself (single-file torrents only).
            return metainfo.isSingleFile ? base : nil
        }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#;"))
        func enc(_ s: String) -> String? { s.addingPercentEncoding(withAllowedCharacters: allowed) }
        // Raw components are only percent-encoded into a URL path; ".." would be harmless
        // to us but is refused anyway.
        let raw = metainfo.isSingleFile ? [] : metainfo.files[file.index].rawComponents
        let rootName = metainfo.isSingleFile ? metainfo.files[0].rawComponents[0] : metainfo.name
        let parts = [rootName] + raw
        guard !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { return nil }
        let encoded = parts.compactMap(enc)
        guard encoded.count == parts.count else { return nil }
        text += encoded.joined(separator: "/")
        return URL(string: text)
    }

    /// Downloads one piece. The caller verifies the hash.
    func fetch(piece index: Int, metainfo: TorrentMetainfo) async throws -> Data {
        let start = Int64(index) * Int64(metainfo.pieceLength)
        let end = start + Int64(metainfo.pieceSize(index))
        var out = Data()
        out.reserveCapacity(metainfo.pieceSize(index))
        for file in metainfo.files where file.length > 0 {
            let fileStart = file.offset, fileEnd = file.offset + file.length
            let lo = max(start, fileStart), hi = min(end, fileEnd)
            guard lo < hi else { continue }
            guard let url = url(for: file, in: metainfo) else {
                throw TorrentError.sourceFailed("Web seed URL could not be built.")
            }
            var request = URLRequest(url: url)
            request.setValue("bytes=\(lo - fileStart)-\(hi - fileStart - 1)", forHTTPHeaderField: "Range")
            request.setValue("CasaPlay/0.1", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30
            let response = try await transport.send(request)
            let expected = Int(hi - lo)
            if response.status == 206, response.body.count == expected {
                out.append(response.body)
            } else if response.status == 200, Int64(response.body.count) == file.length {
                // Server ignored the range and sent the whole (small) file.
                out.append(response.body.subdata(in: Int(lo - fileStart)..<Int(hi - fileStart)))
            } else {
                throw TorrentError.sourceFailed("Web seed answered \(response.status) with \(response.body.count) bytes.")
            }
        }
        return out
    }
}
