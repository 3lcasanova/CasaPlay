// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// SRT and WebVTT parsing, plus a WebVTT writer so sidecar .srt files can be
// handed to AVPlayer as native WebVTT.

import Foundation

enum TimeParsing {
    /// "00:01:02,500", "00:01:02.500" or "01:02.500" -> seconds.
    /// Anything after the first space (WebVTT cue settings) is ignored.
    static func seconds(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let token = trimmed.split(separator: " ").first else { return nil }
        let normalized = token.replacingOccurrences(of: ",", with: ".")
        let pieces = normalized.split(separator: ":").map { String($0) }
        guard pieces.count == 2 || pieces.count == 3 else { return nil }

        var total = 0.0
        for piece in pieces {
            guard let value = Double(piece) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

enum TextCleaning {
    /// Removes <i>/<b>/<font> tags and {\an8}-style override blocks.
    static func stripMarkup(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CueBlockParser {
    static func parse(_ source: String, skipPrefixes: [String]) -> [SubtitleCue] {
        var normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }

        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0) }
            guard let first = lines.first else { continue }
            if skipPrefixes.contains(where: { first.hasPrefix($0) }) { continue }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }

            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = TimeParsing.seconds(parts[0]),
                  let end = TimeParsing.seconds(parts[1]) else { continue }

            let body = lines[(timingIndex + 1)...].joined(separator: "\n")
            let cueText = TextCleaning.stripMarkup(body)
            if cueText.isEmpty { continue }

            cues.append(SubtitleCue(start: start, end: end, text: cueText))
        }
        return cues.sorted { $0.start < $1.start }
    }
}

public enum SRTParser {
    public static func parse(_ source: String) -> [SubtitleCue] {
        CueBlockParser.parse(source, skipPrefixes: [])
    }
}

public enum WebVTTParser {
    public static func parse(_ source: String) -> [SubtitleCue] {
        CueBlockParser.parse(source, skipPrefixes: ["WEBVTT", "NOTE", "STYLE", "REGION"])
    }
}

public enum WebVTTWriter {
    public static func make(from cues: [SubtitleCue]) -> String {
        var output = "WEBVTT\n\n"
        for cue in cues {
            output += "\(TimeFormat.vtt(cue.start)) --> \(TimeFormat.vtt(cue.end))\n"
            output += "\(cue.text)\n\n"
        }
        return output
    }
}
