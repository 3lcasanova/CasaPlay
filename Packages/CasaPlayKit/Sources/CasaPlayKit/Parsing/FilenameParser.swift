// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Turns file names such as "Night.Ferry.2025.2160p.WEB-DL.HEVC.mkv" or
// "Tidewater.S01E04.1080p.mkv" into a clean title, year and episode numbers
// that can be looked up on TMDB.

import Foundation

public struct ParsedFilename: Equatable, Sendable {
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    public var resolution: String?
    /// IMDb ID written into the name, e.g. "Night Ferry (2025) {imdb-tt1234567}".
    public var imdbID: String?

    public init(
        title: String,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        resolution: String? = nil,
        imdbID: String? = nil
    ) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.resolution = resolution
        self.imdbID = imdbID
    }

    public var isEpisode: Bool { season != nil && episode != nil }
}

public enum FilenameParser {
    private static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "ts", "m2ts", "webm", "wmv", "mpg", "mpeg"
    ]

    // The patterns are constants, so a failure here is a programming error.
    private static let seasonEpisodeRegex = try! NSRegularExpression(
        pattern: #"\bS(\d{1,2})\s?E(\d{1,3})\b"#,
        options: [.caseInsensitive]
    )
    private static let yearRegex = try! NSRegularExpression(
        pattern: #"[\(\[]?\b((?:19|20)\d{2})\b[\)\]]?"#,
        options: []
    )
    private static let resolutionRegex = try! NSRegularExpression(
        pattern: #"\b(2160p|1080p|720p|480p)\b"#,
        options: [.caseInsensitive]
    )
    private static let qualityRegex = try! NSRegularExpression(
        pattern: #"\b(2160p|1080p|720p|480p|4k|uhd|blu-?ray|bdrip|brrip|web-?dl|webrip|hdtv|x26[45]|h\s?26[45]|hevc|remux)\b"#,
        options: [.caseInsensitive]
    )

    private struct Hit {
        let range: Range<String.Index>
        let groups: [String]
    }

    public static func parse(_ filename: String) -> ParsedFilename {
        var name = String(filename.split(separator: "/").last ?? Substring(filename))

        if let dot = name.lastIndex(of: ".") {
            let ext = name[name.index(after: dot)...].lowercased()
            if videoExtensions.contains(ext) {
                name = String(name[..<dot])
            }
        }

        let imdbID = IMDb.extractID(from: name)
        // Drop "{imdb-tt…}", "[tt…]" and bare IMDb IDs so they never end up in the title.
        name = name.replacingOccurrences(
            of: #"[\{\[\(]?\s*(?:imdb(?:id)?[-=_ ]?)?tt\d{7,9}\s*[\}\]\)]?"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        name = name
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        let resolution = hits(resolutionRegex, in: name).first?.groups.first?.lowercased()

        var rawTitle = name
        var year: Int?
        var season: Int?
        var episode: Int?

        if let match = hits(seasonEpisodeRegex, in: name).first {
            season = Int(match.groups[0])
            episode = Int(match.groups[1])
            rawTitle = String(name[..<match.range.lowerBound])
        } else if let match = hits(yearRegex, in: name).last(where: {
            name.distance(from: name.startIndex, to: $0.range.lowerBound) > 0
        }) {
            year = Int(match.groups[0])
            rawTitle = String(name[..<match.range.lowerBound])
        } else if let match = hits(qualityRegex, in: name).first {
            rawTitle = String(name[..<match.range.lowerBound])
        }

        var title = clean(rawTitle)
        if title.isEmpty { title = clean(name) }

        return ParsedFilename(
            title: title,
            year: year,
            season: season,
            episode: episode,
            resolution: resolution,
            imdbID: imdbID
        )
    }

    private static func hits(_ regex: NSRegularExpression, in text: String) -> [Hit] {
        let full = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: full).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            var groups: [String] = []
            if match.numberOfRanges > 1 {
                for index in 1..<match.numberOfRanges {
                    if let groupRange = Range(match.range(at: index), in: text) {
                        groups.append(String(text[groupRange]))
                    } else {
                        groups.append("")
                    }
                }
            }
            return Hit(range: range, groups: groups)
        }
    }

    private static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " -–—([{)]}"))
        return trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
