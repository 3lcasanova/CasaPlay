// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation

public enum SubtitleSelector {
    /// Picks the track to switch on automatically, or nil to leave subtitles off.
    ///
    /// - If the audio is already in the profile's first language, only forced
    ///   subtitles (signs, foreign dialogue) are shown.
    /// - Otherwise the first preferred language that has a track wins.
    ///   Text beats image subtitles, embedded beats files, files beat online.
    public static func defaultTrack(
        from tracks: [SubtitleTrack],
        preferredLanguages: [String],
        audioLanguage: String?,
        preferSDH: Bool = false
    ) -> SubtitleTrack? {
        let preferred = preferredLanguages.map { normalize($0) }

        if let audio = audioLanguage.map({ normalize($0) }),
           let first = preferred.first,
           audio == first {
            return tracks.first { normalize($0.languageCode) == first && $0.isForced }
        }

        for language in preferred {
            let matches = tracks.filter { normalize($0.languageCode) == language && !$0.isForced }
            if let best = matches.min(by: { rank($0, preferSDH: preferSDH) < rank($1, preferSDH: preferSDH) }) {
                return best
            }
        }
        return nil
    }

    /// "fr-CA" -> "fr"
    private static func normalize(_ code: String) -> String {
        let lowered = code.lowercased()
        return lowered.split(separator: "-").first.map { String($0) } ?? lowered
    }

    /// Lower is better.
    private static func rank(_ track: SubtitleTrack, preferSDH: Bool) -> Int {
        var score = 0
        if track.isSDH != preferSDH { score += 10 }
        if track.format.isImageBased { score += 5 }
        switch track.origin {
        case .embedded: break
        case .sidecar: score += 1
        case .online: score += 2
        }
        return score
    }
}
