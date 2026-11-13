// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Describes what is inside a media file. The playback router uses these
// values to decide which engine can play it.

import Foundation

public enum MediaContainer: String, Codable, Sendable, CaseIterable {
    case mp4, mov, m4v, hls, mkv, avi, ts, webm, other

    public init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "mp4": self = .mp4
        case "mov": self = .mov
        case "m4v": self = .m4v
        case "m3u8": self = .hls
        case "mkv": self = .mkv
        case "avi": self = .avi
        case "ts", "m2ts": self = .ts
        case "webm": self = .webm
        default: self = .other
        }
    }

    /// Containers that AVPlayer opens directly.
    public var isNativeToApplePlayer: Bool {
        switch self {
        case .mp4, .mov, .m4v, .hls:
            return true
        case .mkv, .avi, .ts, .webm, .other:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .other: return "Unknown"
        default: return rawValue.uppercased()
        }
    }
}

public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264, hevc, av1, vp9, mpeg2, vc1, other

    public var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .av1: return "AV1"
        case .vp9: return "VP9"
        case .mpeg2: return "MPEG-2"
        case .vc1: return "VC-1"
        case .other: return "Unknown"
        }
    }
}

public enum HDRFormat: String, Codable, Sendable, CaseIterable {
    case sdr, hlg, hdr10, hdr10Plus, dolbyVision

    public var isHDR: Bool { self != .sdr }
}

public enum AudioCodec: String, Codable, Sendable, CaseIterable {
    case aac, ac3, eac3, eac3Atmos, truehd, dts, dtsHD, flac, alac, opus, mp3, pcm, other

    /// Audio that AVPlayer decodes without help.
    /// FLAC is treated as unsupported until it has been tested inside MP4.
    public var isNativeToApplePlayer: Bool {
        switch self {
        case .aac, .ac3, .eac3, .eac3Atmos, .alac, .mp3, .pcm:
            return true
        case .truehd, .dts, .dtsHD, .flac, .opus, .other:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .aac: return "AAC"
        case .ac3: return "Dolby Digital"
        case .eac3: return "Dolby Digital Plus"
        case .eac3Atmos: return "Dolby Atmos"
        case .truehd: return "TrueHD"
        case .dts: return "DTS"
        case .dtsHD: return "DTS-HD"
        case .flac: return "FLAC"
        case .alac: return "ALAC"
        case .opus: return "Opus"
        case .mp3: return "MP3"
        case .pcm: return "PCM"
        case .other: return "Unknown audio"
        }
    }
}

public enum SubtitleFormat: String, Codable, Sendable, CaseIterable {
    case srt, vtt, ass, pgs, vobsub, tx3g, other

    public init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "srt": self = .srt
        case "vtt": self = .vtt
        case "ass", "ssa": self = .ass
        case "sup": self = .pgs
        case "sub", "idx": self = .vobsub
        default: self = .other
        }
    }

    /// Bitmap subtitles cannot be restyled and need a decoder or a server burn-in.
    public var isImageBased: Bool {
        switch self {
        case .pgs, .vobsub: return true
        default: return false
        }
    }

    /// Formats AVPlayer shows on its own.
    public var isNativeToApplePlayer: Bool {
        switch self {
        case .vtt, .tx3g: return true
        default: return false
        }
    }
}
