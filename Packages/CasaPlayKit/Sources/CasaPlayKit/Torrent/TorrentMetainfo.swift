// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// BitTorrent v1 metadata (BEP 3), with web seeds (BEP 19) and tracker tiers (BEP 12).
// Everything here comes from untrusted input, so it is validated and size-limited.

import Foundation

public struct InfoHash: Hashable, Codable, Sendable, CustomStringConvertible {
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == 20 else { return nil }
        self.bytes = bytes
    }

    public init?(hex: String) {
        guard hex.count == 40, let data = Data(hex: hex) else { return nil }
        self.bytes = data
    }

    public var hex: String { bytes.hexString }
    public var description: String { hex }
}

public struct TorrentFile: Hashable, Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int
    /// Display path, already cleaned (see `TorrentPaths`). Never used to write files.
    public let path: String
    /// Path components exactly as the torrent declared them, for building web seed URLs.
    let rawComponents: [String]
    public let length: Int64
    /// Byte offset of this file inside the torrent's concatenated data.
    public let offset: Int64

    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
    public var fileExtension: String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}

public struct TorrentMetainfo: Sendable {
    public let infoHash: InfoHash
    public let name: String
    public let pieceLength: Int
    public let pieceHashes: [Data]
    public let files: [TorrentFile]
    public let totalLength: Int64
    public let isSingleFile: Bool
    /// Tracker announce URLs, tiers flattened in order. Only http, https and udp are kept.
    public let trackers: [URL]
    /// BEP 19 web seeds. Only https and http are kept.
    public let webSeeds: [URL]
    public let comment: String?
    /// The raw bencoded info dictionary, used to answer peers' metadata requests.
    public let infoDictionary: Data

    public var pieceCount: Int { pieceHashes.count }

    public func pieceSize(_ index: Int) -> Int {
        guard index == pieceCount - 1 else { return pieceLength }
        let rest = Int(totalLength - Int64(pieceLength) * Int64(pieceCount - 1))
        return rest
    }

    public struct Limits: Sendable {
        public var maxTorrentFileBytes = 16 * 1024 * 1024
        public var maxFiles = 20_000
        public var maxTotalLength: Int64 = 1 << 42  // 4 TiB
        public var maxPathComponents = 64

        public init() {}
    }

    public enum ParseError: Error, Equatable, LocalizedError {
        case tooLarge
        case malformed(String)

        public var errorDescription: String? {
            switch self {
            case .tooLarge: return "The torrent file is too large to be real."
            case .malformed(let why): return "This torrent file is damaged or not supported (\(why))."
            }
        }
    }

    /// Parses a .torrent file.
    public static func parse(torrentFile data: Data, limits: Limits = Limits()) throws -> TorrentMetainfo {
        guard data.count <= limits.maxTorrentFileBytes else { throw ParseError.tooLarge }
        let decoder = BencodeDecoder()
        let root = try wrap { try decoder.decode(data) }
        guard let info = try wrap({ try decoder.rawValue(forKey: "info", in: data) }) else {
            throw ParseError.malformed("no info dictionary")
        }
        var trackers: [URL] = []
        if let tiers = root["announce-list"]?.list {
            for tier in tiers {
                for entry in tier.list ?? [] {
                    if let url = entry.string.flatMap(URL.init(string:)) { trackers.append(url) }
                }
            }
        }
        if let single = root["announce"]?.string.flatMap(URL.init(string:)) {
            trackers.insert(single, at: 0)
        }
        var seeds: [URL] = []
        if let list = root["url-list"]?.list {
            seeds = list.compactMap { $0.string.flatMap(URL.init(string:)) }
        } else if let one = root["url-list"]?.string.flatMap(URL.init(string:)) {
            seeds = [one]
        }
        return try parse(
            infoDictionary: info,
            trackers: trackers,
            webSeeds: seeds,
            comment: root["comment"]?.string,
            limits: limits
        )
    }

    /// Parses an info dictionary, e.g. one received from peers for a magnet link.
    public static func parse(
        infoDictionary info: Data,
        trackers: [URL] = [],
        webSeeds: [URL] = [],
        comment: String? = nil,
        limits: Limits = Limits()
    ) throws -> TorrentMetainfo {
        guard info.count <= limits.maxTorrentFileBytes else { throw ParseError.tooLarge }
        let dict = try wrap { try BencodeDecoder().decode(info) }
        guard let hash = InfoHash(bytes: SHA1.hash(info)) else { throw ParseError.malformed("hash") }

        guard let pieceLength = dict["piece length"]?.int,
              pieceLength >= 16 * 1024, pieceLength <= 64 * 1024 * 1024 else {
            throw ParseError.malformed("piece length")
        }
        guard let pieces = dict["pieces"]?.data, !pieces.isEmpty, pieces.count % 20 == 0 else {
            throw ParseError.malformed("piece hashes")
        }
        let rawName = dict["name.utf-8"]?.string ?? dict["name"]?.string ?? ""
        let name = TorrentPaths.cleanComponent(rawName) ?? "Torrent"

        var files: [TorrentFile] = []
        var total: Int64 = 0
        let singleFile: Bool
        if let length = dict["length"]?.int {
            guard length > 0, length <= limits.maxTotalLength else { throw ParseError.malformed("length") }
            singleFile = true
            files = [TorrentFile(index: 0, path: name, rawComponents: [rawName], length: length, offset: 0)]
            total = length
        } else if let list = dict["files"]?.list, !list.isEmpty {
            guard list.count <= limits.maxFiles else { throw ParseError.malformed("too many files") }
            singleFile = false
            for (i, entry) in list.enumerated() {
                guard let length = entry["length"]?.int, length >= 0 else {
                    throw ParseError.malformed("file length")
                }
                let components = (entry["path.utf-8"]?.list ?? entry["path"]?.list ?? []).compactMap(\.string)
                guard !components.isEmpty, components.count <= limits.maxPathComponents else {
                    throw ParseError.malformed("file path")
                }
                let display = TorrentPaths.cleanPath(components) ?? "file-\(i)"
                files.append(TorrentFile(index: i, path: display, rawComponents: components, length: length, offset: total))
                total += length
                guard total <= limits.maxTotalLength else { throw ParseError.tooLarge }
            }
        } else {
            throw ParseError.malformed("no files")
        }

        let hashes = stride(from: 0, to: pieces.count, by: 20).map { pieces.subdata(in: $0..<($0 + 20)) }
        let expected = (total + pieceLength - 1) / pieceLength
        guard Int64(hashes.count) == expected else { throw ParseError.malformed("piece count does not match size") }

        return TorrentMetainfo(
            infoHash: hash,
            name: name,
            pieceLength: Int(pieceLength),
            pieceHashes: hashes,
            files: files,
            totalLength: total,
            isSingleFile: singleFile,
            trackers: trackers.filter { ["http", "https", "udp"].contains($0.scheme?.lowercased() ?? "") },
            webSeeds: webSeeds.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") },
            comment: comment,
            infoDictionary: info
        )
    }

    /// Pieces that hold any byte of `range` (torrent-wide byte offsets, upper bound exclusive).
    public func pieces(covering range: Range<Int64>) -> ClosedRange<Int>? {
        guard !range.isEmpty, range.lowerBound >= 0, range.lowerBound < totalLength else { return nil }
        let upper = min(range.upperBound, totalLength) - 1
        return Int(range.lowerBound / Int64(pieceLength))...Int(upper / Int64(pieceLength))
    }

    public func pieces(of file: TorrentFile) -> ClosedRange<Int>? {
        pieces(covering: file.offset..<(file.offset + file.length))
    }

    private static func wrap<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch let error as ParseError { throw error } catch {
            throw ParseError.malformed("bencode")
        }
    }
}

/// Cleans names from torrents before they are shown. CasaPlay never creates files from these
/// names (data is stored in one file named by info-hash), but they are still treated as hostile.
public enum TorrentPaths {
    private static let reserved: Set<String> = [
        "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "lpt1", "lpt2", "lpt3"
    ]

    /// Returns nil for components that must never be used: "", ".", ".." and similar.
    public static func cleanComponent(_ raw: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.value {
            case 0..<0x20, 0x7F, 0x202A...0x202E, 0x2066...0x2069:
                continue  // control characters and bidi overrides that can disguise extensions
            case 0x2F, 0x5C, 0x3A:
                scalars.append("_")  // "/", "\" and ":" would split or redirect paths
            default:
                scalars.append(scalar)
            }
        }
        var name = String(scalars).trimmingCharacters(in: .whitespaces)
        while name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty, name != ".", name != "..", !name.allSatisfy({ $0 == "." }) else { return nil }
        if reserved.contains(name.lowercased().split(separator: ".").first.map(String.init) ?? "") {
            name = "_" + name
        }
        if name.utf8.count > 200 {
            name = String(name.prefix(200))
        }
        return name
    }

    /// Joins cleaned components with "/". Unusable components are dropped; nil if none remain.
    public static func cleanPath(_ components: [String]) -> String? {
        let cleaned = components.compactMap(cleanComponent)
        return cleaned.isEmpty ? nil : cleaned.joined(separator: "/")
    }
}
