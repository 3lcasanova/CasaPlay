// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The playback router looks at what is inside a file and picks an engine:
//   1. Apple engine (AVPlayer + AVKit) whenever the file can play natively.
//   2. A media server (Plex or Jellyfin) that remuxes or transcodes to HLS.
//   3. The compatibility engine (VLCKit or FFmpeg-based), once it exists.

import Foundation

public struct DeviceCapabilities: Sendable, Equatable {
    public var supportsHEVC: Bool
    public var supportsAV1: Bool
    public var supportsDolbyVision: Bool
    public var supportsHDR10: Bool
    public var supportsAtmos: Bool

    public init(
        supportsHEVC: Bool,
        supportsAV1: Bool,
        supportsDolbyVision: Bool,
        supportsHDR10: Bool,
        supportsAtmos: Bool
    ) {
        self.supportsHEVC = supportsHEVC
        self.supportsAV1 = supportsAV1
        self.supportsDolbyVision = supportsDolbyVision
        self.supportsHDR10 = supportsHDR10
        self.supportsAtmos = supportsAtmos
    }

    /// Apple TV 4K. AV1 is left off because the chip has no hardware decoder.
    public static let appleTV4K = DeviceCapabilities(
        supportsHEVC: true,
        supportsAV1: false,
        supportsDolbyVision: true,
        supportsHDR10: true,
        supportsAtmos: true
    )

    /// A recent iPhone or iPad. Refine per model later.
    public static let iPhoneOrIPad = DeviceCapabilities(
        supportsHEVC: true,
        supportsAV1: false,
        supportsDolbyVision: true,
        supportsHDR10: true,
        supportsAtmos: true
    )

    public static var current: DeviceCapabilities {
        #if os(tvOS)
        return .appleTV4K
        #else
        return .iPhoneOrIPad
        #endif
    }
}

public enum PlaybackEngine: String, Codable, Sendable {
    case apple
    case appleViaServerStream
    case compatibility
    case unsupported
}

public struct PlaybackDecision: Equatable, Sendable {
    public let engine: PlaybackEngine
    /// Why the Apple engine cannot play the file directly. Empty for direct play.
    public let reasons: [String]
    /// Things worth telling the viewer even when playback works.
    public let notes: [String]

    public init(engine: PlaybackEngine, reasons: [String] = [], notes: [String] = []) {
        self.engine = engine
        self.reasons = reasons
        self.notes = notes
    }

    public var isDirectPlay: Bool { engine == .apple }
    public var isPlayable: Bool { engine != .unsupported }

    public var badgeText: String {
        switch engine {
        case .apple: return "Direct Play · Apple engine"
        case .appleViaServerStream: return "Server stream · Apple engine"
        case .compatibility: return "Compatibility engine"
        case .unsupported: return "Not playable yet"
        }
    }
}

public struct PlaybackRouter: Sendable {
    public var capabilities: DeviceCapabilities
    /// Stays false until Phase 4 ships the compatibility engine.
    public var compatibilityEngineEnabled: Bool

    public init(
        capabilities: DeviceCapabilities = .current,
        compatibilityEngineEnabled: Bool = false
    ) {
        self.capabilities = capabilities
        self.compatibilityEngineEnabled = compatibilityEngineEnabled
    }

    public func decide(for file: MediaFileInfo, serverCanStream: Bool = false) -> PlaybackDecision {
        var blockers: [String] = []
        var notes: [String] = []

        if !file.container.isNativeToApplePlayer {
            blockers.append("\(file.container.displayName) container")
        }

        if !isVideoPlayable(file.videoCodec) {
            blockers.append("\(file.videoCodec.displayName) video")
        }

        let nativeAudio = file.audioCodecs.filter { $0.isNativeToApplePlayer }
        let otherAudio = file.audioCodecs.filter { !$0.isNativeToApplePlayer }
        if !file.audioCodecs.isEmpty && nativeAudio.isEmpty {
            blockers.append("\(otherAudio[0].displayName) audio")
        } else {
            for codec in otherAudio {
                notes.append("\(codec.displayName) track is skipped; a supported track will play")
            }
        }

        if file.hdr == .dolbyVision && !capabilities.supportsDolbyVision {
            notes.append("Dolby Vision will play as HDR10 or SDR on this device")
        }
        if file.subtitleFormats.contains(where: { $0.isImageBased }) {
            notes.append("Image subtitles (PGS) need the compatibility engine or a server")
        }

        if blockers.isEmpty {
            return PlaybackDecision(engine: .apple, reasons: [], notes: notes)
        }
        if serverCanStream {
            return PlaybackDecision(engine: .appleViaServerStream, reasons: blockers, notes: notes)
        }
        if compatibilityEngineEnabled {
            return PlaybackDecision(engine: .compatibility, reasons: blockers, notes: notes)
        }
        return PlaybackDecision(engine: .unsupported, reasons: blockers, notes: notes)
    }

    private func isVideoPlayable(_ codec: VideoCodec) -> Bool {
        switch codec {
        case .h264: return true
        case .hevc: return capabilities.supportsHEVC
        case .av1: return capabilities.supportsAV1
        case .vp9, .mpeg2, .vc1, .other: return false
        }
    }
}
