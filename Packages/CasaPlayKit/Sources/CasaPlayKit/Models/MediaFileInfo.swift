// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation

public struct MediaFileInfo: Codable, Hashable, Sendable {
    public var container: MediaContainer
    public var videoCodec: VideoCodec
    public var hdr: HDRFormat
    public var width: Int
    public var height: Int
    public var audioCodecs: [AudioCodec]
    public var subtitleFormats: [SubtitleFormat]
    public var sizeBytes: Int64?

    public init(
        container: MediaContainer,
        videoCodec: VideoCodec,
        hdr: HDRFormat = .sdr,
        width: Int = 1920,
        height: Int = 1080,
        audioCodecs: [AudioCodec] = [.aac],
        subtitleFormats: [SubtitleFormat] = [],
        sizeBytes: Int64? = nil
    ) {
        self.container = container
        self.videoCodec = videoCodec
        self.hdr = hdr
        self.width = width
        self.height = height
        self.audioCodecs = audioCodecs
        self.subtitleFormats = subtitleFormats
        self.sizeBytes = sizeBytes
    }

    public var is4K: Bool { width >= 3200 || height >= 1800 }

    /// Short labels for the badges shown on posters and the detail screen.
    public var badges: [String] {
        var labels: [String] = []
        if is4K { labels.append("4K") }
        switch hdr {
        case .dolbyVision: labels.append("DOLBY VISION")
        case .hdr10Plus: labels.append("HDR10+")
        case .hdr10: labels.append("HDR10")
        case .hlg: labels.append("HLG")
        case .sdr: break
        }
        if audioCodecs.contains(.eac3Atmos) { labels.append("ATMOS") }
        return labels
    }
}
