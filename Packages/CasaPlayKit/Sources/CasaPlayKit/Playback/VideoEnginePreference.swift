// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Which engine plays the files Apple's player can't open (MKV, WebM, AVI and so on).
//   Auto   – the Aether engine first (HDR10 and Dolby Vision on the TV, real MKV playback), VLC if Aether can't open the file.
//   Aether – the Aether engine only.
//   VLC    – the VLC engine only, the way CasaPlay played these files before.
// Files Apple's player can open never come here; they always use Apple's player.

import Foundation

public enum VideoEnginePreference: String, CaseIterable, Codable, Sendable {
    case auto, aether, vlc

    /// Where the choice is saved (UserDefaults).
    public static let storageKey = "videoEnginePreference"

    public var label: String {
        switch self {
        case .auto: return "Auto"
        case .aether: return "Aether"
        case .vlc: return "VLC"
        }
    }

    public var detail: String {
        switch self {
        case .auto: return "Aether first, for HDR10 and Dolby Vision on MKV files. VLC takes over if Aether can't open a file."
        case .aether: return "Aether only. If it can't open a file, you see the error."
        case .vlc: return "VLC only, as before. No Dolby Vision switching."
        }
    }

    /// True when Aether should be tried for a file that Apple's player can't open.
    public var prefersAether: Bool { self != .vlc }

    /// True when VLC should step in after Aether fails to open a file.
    public var fallsBackToVLC: Bool { self == .auto }
}
