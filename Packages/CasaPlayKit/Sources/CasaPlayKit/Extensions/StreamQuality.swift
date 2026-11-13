// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Two separate things are tracked for every stream:
//   advertised – what the provider's label or file name claims ("4K", "2160p", "HDR")
//   verified   – what CasaPlay read from the stream itself (playlist or container metadata,
//                or the picture actually playing)
// Only verified values ever count as verified. Resolution never proves native mastering,
// so CasaPlay never says "native 4K".

import Foundation

public enum ResolutionClass: Int, Codable, Comparable, Sendable {
    case unknown = 0, sd, hd720, fhd1080, uhd2160

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public init(width: Int, height: Int) {
        // Width matters for scope films (3840×1600 is still a 4K-class picture).
        switch (width, height) {
        case _ where width >= 3200 || height >= 2000: self = .uhd2160
        case _ where width >= 1700 || height >= 1000: self = .fhd1080
        case _ where width >= 1200 || height >= 700: self = .hd720
        case _ where width > 0: self = .sd
        default: self = .unknown
        }
    }

    public var label: String {
        switch self {
        case .unknown: return "Unknown"
        case .sd: return "SD"
        case .hd720: return "720p"
        case .fhd1080: return "1080p"
        case .uhd2160: return "2160p"
        }
    }
}

public enum DynamicRange: String, Codable, Sendable {
    case sdr = "SDR", hdr10 = "HDR10", hdr10Plus = "HDR10+", hlg = "HLG", dolbyVision = "Dolby Vision", pq = "HDR (PQ)"
}

/// Claims from the provider's text. Never treated as verified.
public struct AdvertisedQuality: Equatable, Codable, Sendable {
    public var resolution: ResolutionClass = .unknown
    public var dynamicRange: DynamicRange?
    public var codec: String?
    public var audio: String?
    public var sizeBytes: Int64?

    public static func parse(_ text: String, size: Int64? = nil) -> AdvertisedQuality {
        let t = text.lowercased()
        func has(_ pattern: String) -> Bool { t.range(of: pattern, options: .regularExpression) != nil }
        var q = AdvertisedQuality()
        if has(#"\b(2160p|4k|uhd)\b"#) { q.resolution = .uhd2160 }
        else if has(#"\b1080[pi]\b"#) { q.resolution = .fhd1080 }
        else if has(#"\b720p\b"#) { q.resolution = .hd720 }
        else if has(#"\b(480p|576p|sd)\b"#) { q.resolution = .sd }
        if has(#"\b(dv|dovi|dolby[ .]?vision)\b"#) { q.dynamicRange = .dolbyVision }
        else if has(#"hdr10\+|hdr10plus"#) { q.dynamicRange = .hdr10Plus }
        else if has(#"\bhdr10\b|\bhdr\b"#) { q.dynamicRange = .hdr10 }
        else if has(#"\bhlg\b"#) { q.dynamicRange = .hlg }
        if has(#"\b(hevc|h\.?265|x265)\b"#) { q.codec = "HEVC" }
        else if has(#"\b(avc|h\.?264|x264)\b"#) { q.codec = "H.264" }
        else if has(#"\bav1\b"#) { q.codec = "AV1" }
        if has(#"atmos"#) { q.audio = "Atmos" }
        else if has(#"\b(ddp|dd\+|eac3|e-ac-3)"#) { q.audio = "Dolby Digital Plus" }
        else if has(#"truehd"#) { q.audio = "TrueHD" }
        else if has(#"\bdts"#) { q.audio = "DTS" }
        else if has(#"\baac\b"#) { q.audio = "AAC" }
        q.sizeBytes = size
        return q
    }
}

/// What CasaPlay read from the stream. `source` says how it was read.
public struct VerifiedQuality: Equatable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// The HLS master playlist's declared variants (RESOLUTION, CODECS, VIDEO-RANGE).
        case playlist = "stream playlist"
        /// AVFoundation read the container's track metadata.
        case containerMetadata = "file metadata"
        /// Measured from the picture while it played.
        case playback = "playback"
    }
    public var source: Source
    public var width: Int
    public var height: Int
    public var dynamicRange: DynamicRange?
    public var codec: String?
    public var bitrate: Int?
    public var audioFormats: [String]
    /// For adaptive streams, the variants that are available (highest first).
    public var variants: [Variant]

    public struct Variant: Equatable, Codable, Sendable {
        public var width: Int
        public var height: Int
        public var bandwidth: Int?
        public var codecs: String?
        public var dynamicRange: DynamicRange?
    }

    public init(source: Source, width: Int, height: Int, dynamicRange: DynamicRange? = nil, codec: String? = nil,
                bitrate: Int? = nil, audioFormats: [String] = [], variants: [Variant] = []) {
        self.source = source
        self.width = width
        self.height = height
        self.dynamicRange = dynamicRange
        self.codec = codec
        self.bitrate = bitrate
        self.audioFormats = audioFormats
        self.variants = variants
    }

    public var resolution: ResolutionClass { ResolutionClass(width: width, height: height) }
}

public enum VerificationState: Equatable, Sendable {
    case notChecked
    case checking
    case verified(VerifiedQuality)
    /// Couldn't read metadata (format unsupported, protected, or the server refused).
    case unreadable(String)
    /// Won't play with Apple's player on this device.
    case unplayable(String)

    public var verified: VerifiedQuality? {
        if case .verified(let q) = self { return q }
        return nil
    }

    public var isPlayable: Bool {
        if case .unplayable = self { return false }
        return true
    }
}

/// How streams are filtered and ordered.
public enum QualityMode: String, Codable, CaseIterable, Sendable {
    /// Verified 2160p first, then everything else (1080p next), best first.
    case preferUHD
    /// Only streams verified as 2160p are offered.
    case uhdOnly
    /// 2160p first, then 1080p; nothing below 1080p.
    case allowFHDFallback
    /// Only 1080p streams.
    case fhdOnly
    /// Only 720p streams.
    case hd720Only
    /// Only standard-definition streams (below 720p).
    case sdOnly

    /// Order the choices are offered in, highest resolution first.
    public static let menuOrder: [QualityMode] = [.preferUHD, .uhdOnly, .allowFHDFallback, .fhdOnly, .hd720Only, .sdOnly]

    /// The single resolution a one-resolution mode shows, or nil for the mixed modes.
    public var onlyResolution: ResolutionClass? {
        switch self {
        case .preferUHD, .allowFHDFallback: return nil
        case .uhdOnly: return .uhd2160
        case .fhdOnly: return .fhd1080
        case .hd720Only: return .hd720
        case .sdOnly: return .sd
        }
    }

    public var label: String {
        switch self {
        case .preferUHD: return "All resolutions, 4K first"
        case .uhdOnly: return "4K only"
        case .allowFHDFallback: return "4K and 1080p"
        case .fhdOnly: return "1080p only"
        case .hd720Only: return "720p only"
        case .sdOnly: return "SD only"
        }
    }

    public var explanation: String {
        switch self {
        case .preferUHD: return "Verified 2160p streams first, then 1080p and anything else that plays."
        case .uhdOnly: return "Only streams CasaPlay has checked and confirmed as 2160p."
        case .allowFHDFallback: return "Verified 2160p first, then 1080p. Lower resolutions are hidden."
        case .fhdOnly: return "Only 1080p streams. 4K and lower resolutions are hidden."
        case .hd720Only: return "Only 720p streams. Uses less data than 1080p or 4K."
        case .sdOnly: return "Only standard-definition streams, below 720p. Uses the least data."
        }
    }
}

public enum QualityRanking {
    /// 1080p streams verified below this bitrate rank after other 1080p streams and are marked low bitrate.
    public static let lowBitrateFHD = 6_000_000

    public static func isLowBitrate(_ q: VerifiedQuality) -> Bool {
        guard q.resolution == .fhd1080, let bitrate = q.bitrate else { return false }
        return bitrate < lowBitrateFHD
    }

    /// Lower is better. Verified beats advertised within the same resolution, and
    /// high-bitrate 1080p beats heavily compressed 1080p.
    static func tier(_ advertised: AdvertisedQuality, _ state: VerificationState) -> Int {
        switch state {
        case .verified(let q):
            switch q.resolution {
            case .uhd2160: return 0
            case .fhd1080: return isLowBitrate(q) ? 3 : 2
            case .hd720: return 4
            case .sd: return 5
            case .unknown: return 6
            }
        case .unplayable: return 99
        default:
            switch advertised.resolution {
            case .uhd2160: return 1   // claimed 4K, waiting for or unable to verify
            case .fhd1080: return 3
            case .hd720: return 4
            case .sd: return 5
            case .unknown: return 6
            }
        }
    }

    /// Whether a stream may be offered under `mode`.
    public static func admits(_ advertised: AdvertisedQuality, _ state: VerificationState, mode: QualityMode) -> Bool {
        guard state.isPlayable else { return false }
        switch mode {
        case .preferUHD:
            return true
        case .uhdOnly:
            return state.verified?.resolution == .uhd2160
        case .allowFHDFallback:
            if let v = state.verified { return v.resolution >= .fhd1080 }
            return advertised.resolution >= .fhd1080 || advertised.resolution == .unknown
        case .fhdOnly, .hd720Only, .sdOnly:
            // The checked resolution wins; an unchecked stream is judged by what it claims.
            return (state.verified?.resolution ?? advertised.resolution) == mode.onlyResolution
        }
    }
}
