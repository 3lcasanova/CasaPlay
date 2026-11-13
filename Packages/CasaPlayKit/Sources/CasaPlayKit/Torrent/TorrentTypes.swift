// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation

public enum TorrentError: Error, Equatable, LocalizedError {
    case metadataUnavailable
    case metadataMismatch
    case noSources
    case storageFull(neededBytes: Int64)
    case storageLimitReached(limitBytes: Int64)
    case cancelled
    case paused
    case timedOut
    case fileNotSelected
    case unsafeLocation
    case sourceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .metadataUnavailable:
            return "Couldn't get this torrent's details. No peer or source answered. Check the link or try again later."
        case .metadataMismatch:
            return "A source sent details that don't match this magnet link, so they were rejected."
        case .noSources:
            return "No peers or web seeds are available for this torrent right now."
        case .storageFull(let needed):
            return "Not enough free space on this device. Free about \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) or clear the torrent cache."
        case .storageLimitReached(let limit):
            return "The torrent cache reached its limit of \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)). Raise it in Settings or remove old torrents."
        case .cancelled: return "The torrent was cancelled."
        case .paused: return "The torrent is paused."
        case .timedOut: return "No data arrived in time. Peers may be slow or unavailable."
        case .fileNotSelected: return "Choose a file first."
        case .unsafeLocation: return "Refused to use a storage location outside CasaPlay's torrent folder."
        case .sourceFailed(let why): return why
        }
    }
}

/// User-controlled transfer settings.
public struct TorrentSettings: Codable, Equatable, Sendable {
    /// Upload to peers while this device is downloading. BitTorrent peers expect some upload in return.
    public var uploadWhileDownloading: Bool = true
    /// Keep uploading after a file is complete. Off by default.
    public var seedAfterDownload: Bool = false
    /// Bytes per second. 0 means no upload at all.
    public var uploadLimit: Int = 100 * 1024
    /// Bytes per second. 0 means unlimited.
    public var downloadLimit: Int = 0
    /// Total size of the torrent cache.
    public var storageLimit: Int64 = 20 * 1024 * 1024 * 1024
    /// Space to always leave free on the device.
    public var reserveFreeSpace: Int64 = 2 * 1024 * 1024 * 1024
    /// Read-ahead while streaming.
    public var streamingWindow: Int64 = 24 * 1024 * 1024
    public var maxPeers: Int = 30

    public init() {}

    public var uploadsAllowed: Bool { uploadLimit > 0 && (uploadWhileDownloading || seedAfterDownload) }
}

public enum TorrentState: Equatable, Sendable {
    case fetchingMetadata
    case ready
    case downloading
    case paused
    case completed
    case failed(String)

    public var label: String {
        switch self {
        case .fetchingMetadata: return "Getting details"
        case .ready: return "Ready"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Downloaded"
        case .failed: return "Error"
        }
    }
}

/// A snapshot for the UI, refreshed about once a second.
public struct TorrentStats: Equatable, Sendable {
    public var state: TorrentState = .fetchingMetadata
    public var name: String = ""
    public var selectedFileIndex: Int?
    /// 0…1 of the selected file (or the whole torrent when nothing is selected).
    public var progress: Double = 0
    public var downloadedBytes: Int64 = 0
    public var uploadedBytes: Int64 = 0
    public var downloadRate: Double = 0
    public var uploadRate: Double = 0
    public var connectedPeers: Int = 0
    public var knownPeers: Int = 0
    public var activeWebSeeds: Int = 0
    /// Bytes ready after the current playback position.
    public var bufferedAhead: Int64 = 0
    public var isBuffering: Bool = false
    public var lastError: String?

    public init() {}
}

/// Measures throughput over a short sliding window.
struct RateMeter {
    private var samples: [(time: TimeInterval, bytes: Int)] = []
    private let window: TimeInterval = 5

    mutating func add(_ bytes: Int, at now: TimeInterval = Date().timeIntervalSince1970) {
        samples.append((now, bytes))
        trim(now)
    }

    mutating func rate(at now: TimeInterval = Date().timeIntervalSince1970) -> Double {
        trim(now)
        guard !samples.isEmpty else { return 0 }
        return Double(samples.reduce(0) { $0 + $1.bytes }) / window
    }

    private mutating func trim(_ now: TimeInterval) {
        samples.removeAll { now - $0.time > window }
    }
}

/// Token bucket for upload and download limits.
actor RateLimiter {
    private var bytesPerSecond: Int
    private var tokens: Double
    private var last = Date()

    init(bytesPerSecond: Int) {
        self.bytesPerSecond = bytesPerSecond
        self.tokens = Double(max(bytesPerSecond, 0))
    }

    func setLimit(_ value: Int) { bytesPerSecond = value }

    /// Waits until `bytes` may be sent. Returns false when the limit is 0 (not allowed at all).
    func acquire(_ bytes: Int, unlimitedWhenZero: Bool) async -> Bool {
        if bytesPerSecond <= 0 { return unlimitedWhenZero }
        while true {
            let now = Date()
            tokens = min(Double(bytesPerSecond), tokens + now.timeIntervalSince(last) * Double(bytesPerSecond))
            last = now
            if tokens >= Double(bytes) || tokens >= Double(bytesPerSecond) {
                tokens -= Double(bytes)
                return true
            }
            let wait = (Double(bytes) - tokens) / Double(bytesPerSecond)
            try? await Task.sleep(nanoseconds: UInt64(min(max(wait, 0.01), 1) * 1_000_000_000))
            if Task.isCancelled { return false }
        }
    }
}
