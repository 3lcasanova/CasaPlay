// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Finds subtitle files that sit next to a video, the way media servers name them:
//   Night.Ferry.2025.mkv
//   Night.Ferry.2025.srt            -> unknown language
//   Night.Ferry.2025.en.srt         -> English
//   Night.Ferry.2025.fr.forced.srt  -> French, forced
//   Night.Ferry.2025.en.sdh.srt     -> English SDH (also "cc" or "hi")

import Foundation

public struct SidecarSubtitle: Equatable, Sendable {
    public var fileName: String
    public var track: SubtitleTrack
}

public enum SidecarSubtitles {
    static let subtitleExtensions: Set<String> = ["srt", "vtt", "ass", "ssa", "sup", "sub", "idx"]

    private static let languageAliases: [String: String] = [
        "eng": "en", "english": "en",
        "fre": "fr", "fra": "fr", "french": "fr", "francais": "fr", "français": "fr",
        "spa": "es", "spanish": "es", "espanol": "es", "español": "es",
        "ger": "de", "deu": "de", "german": "de",
        "ita": "it", "italian": "it",
        "por": "pt", "portuguese": "pt",
        "hat": "ht", "kreyol": "ht", "creole": "ht",
        "jpn": "ja", "japanese": "ja",
        "kor": "ko", "korean": "ko",
        "chi": "zh", "zho": "zh", "chinese": "zh",
        "ara": "ar", "arabic": "ar",
        "rus": "ru", "russian": "ru",
        "dut": "nl", "nld": "nl", "dutch": "nl"
    ]

    /// Picks the subtitle files that belong to `videoFileName` from the names in the same folder.
    public static func match(videoFileName: String, siblings: [String]) -> [SidecarSubtitle] {
        let videoStem = stem(of: videoFileName).lowercased()
        return siblings.compactMap { name -> SidecarSubtitle? in
            let ext = fileExtension(name)
            guard subtitleExtensions.contains(ext) else { return nil }
            let subStem = stem(of: name)
            guard subStem.lowercased().hasPrefix(videoStem) else { return nil }

            let rest = subStem.dropFirst(videoStem.count)
            guard rest.isEmpty || rest.first == "." || rest.first == "_" || rest.first == " " else { return nil }

            let tags = rest
                .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " })
                .map { $0.lowercased() }

            var language = "und"
            var isSDH = false
            var isForced = false
            for tag in tags {
                switch tag {
                case "forced", "foreign": isForced = true
                case "sdh", "cc", "hi": isSDH = true
                case "default": break
                default:
                    if let code = languageCode(tag) { language = code }
                }
            }

            let format = SubtitleFormat(fileExtension: ext)
            var displayName = language == "und" ? "Subtitles" : LanguageNames.displayName(language)
            if isSDH { displayName += " SDH" }
            if isForced { displayName += " (forced)" }

            let track = SubtitleTrack(
                id: "file-\(name)",
                languageCode: language,
                displayName: displayName,
                origin: .sidecar,
                format: format,
                isSDH: isSDH,
                isForced: isForced
            )
            return SidecarSubtitle(fileName: name, track: track)
        }
        .sorted { $0.fileName < $1.fileName }
    }

    /// "en", "en-US", "pt_BR", "eng" or "English" -> "en" / "en-us" / "pt-br"
    static func languageCode(_ tag: String) -> String? {
        let lowered = tag.lowercased()
        if let alias = languageAliases[lowered] { return alias }
        let parts = lowered.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard let first = parts.first, first.count == 2, first.allSatisfy({ $0.isLetter }) else { return nil }
        if parts.count == 1 { return String(first) }
        guard parts.count == 2, parts[1].count == 2 else { return nil }
        return "\(first)-\(parts[1])"
    }

    private static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    private static func stem(of name: String) -> String {
        let last = String(name.split(separator: "/").last ?? Substring(name))
        guard let dot = last.lastIndex(of: ".") else { return last }
        return String(last[..<dot])
    }
}
