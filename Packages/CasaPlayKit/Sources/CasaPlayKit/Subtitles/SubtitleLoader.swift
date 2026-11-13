// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Turns subtitle file bytes into cues, whatever the text encoding.

import Foundation

public enum SubtitleLoader {
    /// Decodes and parses SRT or WebVTT. Other formats return no cues.
    /// When `format` is nil it is guessed from the content.
    public static func cues(from data: Data, format: SubtitleFormat? = nil) -> [SubtitleCue] {
        let text = decode(data)
        switch format ?? guessFormat(text) {
        case .vtt: return WebVTTParser.parse(text)
        case .srt: return SRTParser.parse(text)
        default:
            // Some sites label WebVTT as SRT or the other way round.
            let guessed = guessFormat(text)
            return guessed == .vtt ? WebVTTParser.parse(text) : SRTParser.parse(text)
        }
    }

    public static func guessFormat(_ text: String) -> SubtitleFormat {
        let head = text.drop(while: { $0 == "\u{FEFF}" || $0.isWhitespace }).prefix(6)
        return head.hasPrefix("WEBVTT") ? .vtt : .srt
    }

    /// UTF-8 first (most files), then UTF-16 with a byte order mark,
    /// then Windows-1252, which older European subtitle files use.
    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        if isValidUTF8(data) {
            return String(decoding: data, as: UTF8.self)
        }
        return decodeWindows1252(data)
    }

    /// Strict check. Some Foundation versions quietly replace bad bytes instead of failing.
    static func isValidUTF8(_ data: Data) -> Bool {
        var iterator = data.makeIterator()
        var decoder = UTF8()
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue: continue
            case .emptyInput: return true
            case .error: return false
            }
        }
    }

    /// Windows-1252 is Latin-1 except for 0x80–0x9F, which hold curly quotes, dashes, € and so on.
    static func decodeWindows1252(_ data: Data) -> String {
        let high: [UInt32] = [
            0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
            0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
            0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
            0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178
        ]
        var scalars = String.UnicodeScalarView()
        for byte in data {
            let value = (0x80...0x9F).contains(byte) ? high[Int(byte) - 0x80] : UInt32(byte)
            scalars.append(Unicode.Scalar(value) ?? "\u{FFFD}")
        }
        return String(scalars)
    }
}
