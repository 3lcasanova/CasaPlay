// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Reads an HLS master playlist's declared variants. This is metadata from the stream
// itself (not a provider label), but it is still a declaration: the actual picture is
// confirmed only during playback.

import Foundation

public enum HLSPlaylist {
    public static func isMaster(_ text: String) -> Bool { text.contains("#EXT-X-STREAM-INF") }

    public static func variants(_ text: String) -> [VerifiedQuality.Variant] {
        var out: [VerifiedQuality.Variant] = []
        for line in text.split(whereSeparator: \.isNewline).prefix(5000) where line.hasPrefix("#EXT-X-STREAM-INF:") {
            let attrs = attributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            guard let res = attrs["RESOLUTION"]?.lowercased().split(separator: "x"), res.count == 2,
                  let w = Int(res[0]), let h = Int(res[1]), w > 0, h > 0, w < 20000, h < 20000 else { continue }
            let range: DynamicRange?
            switch attrs["VIDEO-RANGE"]?.uppercased() {
            case "PQ": range = (attrs["CODECS"] ?? "").contains("dvh") || (attrs["CODECS"] ?? "").contains("dvh1") ? .dolbyVision : .pq
            case "HLG": range = .hlg
            case "SDR": range = .sdr
            default: range = nil
            }
            out.append(.init(width: w, height: h, bandwidth: attrs["BANDWIDTH"].flatMap { Int($0) },
                             codecs: attrs["CODECS"], dynamicRange: range))
        }
        return out.sorted { ($0.height, $0.bandwidth ?? 0) > ($1.height, $1.bandwidth ?? 0) }
    }

    /// Verified quality from the playlist: the best declared variant, with all variants listed.
    public static func quality(_ text: String) -> VerifiedQuality? {
        let all = variants(text)
        guard let best = all.first else { return nil }
        return VerifiedQuality(source: .playlist, width: best.width, height: best.height,
                               dynamicRange: best.dynamicRange, codec: codecName(best.codecs),
                               bitrate: best.bandwidth, audioFormats: audioNames(best.codecs), variants: all)
    }

    static func codecName(_ codecs: String?) -> String? {
        guard let c = codecs?.lowercased() else { return nil }
        if c.contains("dvh1") || c.contains("dvhe") { return "HEVC (Dolby Vision)" }
        if c.contains("hvc1") || c.contains("hev1") { return "HEVC" }
        if c.contains("avc1") || c.contains("avc3") { return "H.264" }
        if c.contains("av01") { return "AV1" }
        return nil
    }

    static func audioNames(_ codecs: String?) -> [String] {
        guard let c = codecs?.lowercased() else { return [] }
        var out: [String] = []
        if c.contains("ec-3") { out.append("Dolby Digital Plus") }
        if c.contains("ac-3") { out.append("Dolby Digital") }
        if c.contains("mp4a") { out.append("AAC") }
        return out
    }

    /// Parses KEY=VALUE,KEY="quoted, value" lists.
    static func attributes(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var key = "", value = "", inKey = true, quoted = false
        for ch in text {
            if inKey {
                if ch == "=" { inKey = false } else if ch != "," { key.append(ch) }
            } else if ch == "\"" {
                quoted.toggle()
            } else if ch == ",", !quoted {
                out[key.trimmingCharacters(in: .whitespaces)] = value
                key = ""; value = ""; inKey = true
            } else {
                value.append(ch)
            }
        }
        if !key.isEmpty { out[key.trimmingCharacters(in: .whitespaces)] = value }
        return out
    }
}
