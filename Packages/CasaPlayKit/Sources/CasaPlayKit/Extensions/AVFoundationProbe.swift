// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Reads a progressive file's real track metadata with AVFoundation: picture size,
// codec, transfer function (HDR), data rate and audio formats, and whether Apple's
// player can open it at all. Available on iOS, iPadOS, tvOS and macOS.

#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation

public struct AVFoundationProbe: StreamProbe {
    public let timeout: TimeInterval
    /// True when the app bundles a compatibility player (VLC). A file Apple's player can't open
    /// is then still playable, so it isn't marked "can't play".
    public let compatibilityPlays: Bool

    public init(timeout: TimeInterval = 15, compatibilityPlays: Bool = false) {
        self.timeout = timeout
        self.compatibilityPlays = compatibilityPlays
    }

    /// Options for AVURLAsset. `AVURLAssetHTTPHeaderFieldsKey` is widely used but not formally
    /// documented by Apple; it is the only way to send an add-on's required headers.
    public static func assetOptions(headers: [String: String]) -> [String: Any] {
        headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
    }

    public func probe(_ candidate: StreamCandidate) async -> VerificationState {
        guard case .http(let url, let headers) = candidate.location else {
            return .unreadable("Checked during playback.")
        }
        let asset = AVURLAsset(url: url, options: Self.assetOptions(headers: headers))
        do {
            let state = try await withTimeout(timeout) { try await Self.read(asset) }
            if compatibilityPlays, case .unplayable = state { return .unreadable(StreamCandidate.compatibilityNote) }
            return state
        } catch ExtensionError.timedOut {
            asset.cancelLoading()
            return .unreadable("The file didn't answer in time.")
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, [NSURLErrorUserAuthenticationRequired, NSURLErrorNoPermissionsToReadFile].contains(ns.code) {
                return .unplayable("The link was refused; it may have expired.")
            }
            // A network failure (404, no route) is a dead link. Anything else means AVFoundation
            // doesn't understand the file, which VLC may.
            if compatibilityPlays, ns.domain != NSURLErrorDomain { return .unreadable(StreamCandidate.compatibilityNote) }
            return .unplayable("Apple's player can't open this stream (\(ns.localizedDescription)).")
        }
    }

    static func read(_ asset: AVURLAsset) async throws -> VerificationState {
        guard try await asset.load(.isPlayable) else {
            return .unplayable("Apple's player can't play this format on this device.")
        }
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            return .unreadable("No video track metadata (common for live or adaptive streams); checked during playback.")
        }
        let (size, transform, rate, formats) = try await video.load(.naturalSize, .preferredTransform, .estimatedDataRate, .formatDescriptions)
        let shown = size.applying(transform)
        var codec: String?
        var range: DynamicRange? = .sdr
        if let desc = formats.first {
            let subtype = CMFormatDescriptionGetMediaSubType(desc)
            codec = fourCCName(subtype)
            let dolby = [fourCC("dvh1"), fourCC("dvhe"), fourCC("dva1"), fourCC("dvav")].contains(subtype)
            if let transfer = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
                if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) { range = dolby ? .dolbyVision : .hdr10 }
                else if transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) { range = .hlg }
            } else if dolby {
                range = .dolbyVision
            }
        }
        var audio: [String] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            for desc in try await track.load(.formatDescriptions) {
                if let name = audioName(CMFormatDescriptionGetMediaSubType(desc)), !audio.contains(name) { audio.append(name) }
            }
        }
        let q = VerifiedQuality(source: .containerMetadata, width: Int(abs(shown.width)), height: Int(abs(shown.height)),
                                dynamicRange: range, codec: codec, bitrate: rate > 0 ? Int(rate) : nil, audioFormats: audio)
        return .verified(q)
    }

    static func fourCC(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    static func fourCCName(_ code: FourCharCode) -> String {
        switch code {
        case fourCC("hvc1"), fourCC("hev1"): return "HEVC"
        case fourCC("dvh1"), fourCC("dvhe"): return "HEVC (Dolby Vision)"
        case fourCC("avc1"), fourCC("avc3"): return "H.264"
        case fourCC("av01"): return "AV1"
        case fourCC("ap4h"), fourCC("apcn"), fourCC("apch"): return "ProRes"
        default:
            let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
            return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }
    }

    static func audioName(_ code: FourCharCode) -> String? {
        switch code {
        case fourCC("ec-3"): return "Dolby Digital Plus"
        case fourCC("ac-3"): return "Dolby Digital"
        case fourCC("mp4a"), kAudioFormatMPEG4AAC: return "AAC"
        case fourCC("alac"): return "ALAC"
        case fourCC("fLaC"): return "FLAC"
        case fourCC("opus"): return "Opus"
        case fourCC(".mp3"): return "MP3"
        default: return nil
        }
    }
}
#endif
