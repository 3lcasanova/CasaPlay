// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The small frosted pieces that float over the video: the buffering status, the subtitle button, the close button.

import SwiftUI

extension View {
    /// A frosted capsule that floats over the video.
    func playerPill() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

/// A round frosted button face for the player: close and subtitles.
struct PlayerGlassIcon: View {
    let systemName: String
    var tint: Color = .white
    var size: CGFloat = 46

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
