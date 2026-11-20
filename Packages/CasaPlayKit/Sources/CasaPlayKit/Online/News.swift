// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// News: headlines from public RSS feeds, grouped so the same story from several outlets shows once.
// Feeds are read as plain text and never executed; links are only ever opened as web pages.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NewsFeedSource: Hashable, Sendable, Identifiable {
    public var id: String { url.absoluteString }
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    public static let defaults: [NewsFeedSource] = [
        ("BBC News", "https://feeds.bbci.co.uk/news/rss.xml"),
        ("NPR", "https://feeds.npr.org/1001/rss.xml"),
        ("The Guardian", "https://www.theguardian.com/world/rss"),
        ("Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml")
    ].compactMap { name, link in URL(string: link).map { NewsFeedSource(name: name, url: $0) } }
}

public struct NewsArticle: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let link: URL?
    public let source: String
    public let published: Date?
    public let imageURL: URL?

    public init(id: String, title: String, summary: String, link: URL?, source: String,
                published: Date?, imageURL: URL?) {
        self.id = id
        self.title = title
        self.summary = summary
        self.link = link
        self.source = source
        self.published = published
        self.imageURL = imageURL
    }
}

/// One story, with every outlet's coverage of it.
public struct NewsStory: Identifiable, Hashable, Sendable {
    public let id: String
    public let headline: String
    public let summary: String
    public let articles: [NewsArticle]

    public var sources: [String] {
        var seen = Set<String>()
        return articles.map(\.source).filter { seen.insert($0).inserted }
    }

    public var latest: Date? { articles.compactMap(\.published).max() }
    public var imageURL: URL? { articles.compactMap(\.imageURL).first }
}

// MARK: - Reading a feed

public enum NewsParser {
    /// Reads RSS (`item`) and Atom (`entry`) feeds. Tolerant: anything it can't read is skipped.
    public static func parse(_ data: Data, source: String) -> [NewsArticle] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        let dates = DateReader()
        var seen = Set<String>()
        var articles: [NewsArticle] = []

        for block in blocks(in: text, tag: "item") + blocks(in: text, tag: "entry") {
            guard let rawTitle = element("title", in: block) else { continue }
            let title = stripHTML(rawTitle)
            guard !title.isEmpty else { continue }

            var linkText: String? = element("link", in: block)
            if linkText?.isEmpty ?? true { linkText = attribute("href", ofTag: "link", in: block) }
            var link: URL?
            if let linkText { link = URL(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let id = link?.absoluteString ?? element("guid", in: block) ?? title
            guard seen.insert(id).inserted else { continue }

            let rawSummary = element("description", in: block) ?? element("summary", in: block) ?? ""
            var summary = stripHTML(rawSummary)
            if summary.count > 400 { summary = String(summary.prefix(400)).trimmingCharacters(in: .whitespaces) + "…" }

            let dateText = element("pubDate", in: block) ?? element("dc:date", in: block)
                ?? element("published", in: block) ?? element("updated", in: block)
            let image = attribute("url", ofTag: "media:thumbnail", in: block)
                ?? attribute("url", ofTag: "media:content", in: block)
                ?? enclosureImage(in: block)

            articles.append(NewsArticle(
                id: id, title: title, summary: summary, link: link, source: source,
                published: dateText.flatMap(dates.read), imageURL: image.flatMap { URL(string: $0) }))
        }
        return articles
    }

    // MARK: Small text helpers

    static func blocks(in text: String, tag: String) -> [String] {
        var result: [String] = []
        var search = text.startIndex..<text.endIndex
        while let start = text.range(of: "<\(tag)", range: search) {
            let after = start.upperBound
            guard after < text.endIndex else { break }
            let next = text[after]
            guard next == ">" || next == " " || next == "\n" || next == "\t" || next == "\r" else {
                search = after..<text.endIndex
                continue
            }
            guard let end = text.range(of: "</\(tag)>", range: after..<text.endIndex) else { break }
            result.append(String(text[after..<end.lowerBound]))
            search = end.upperBound..<text.endIndex
        }
        return result
    }

    /// The text inside `<tag>…</tag>`, with CDATA removed. Nil for a missing or self-closing tag.
    static func element(_ tag: String, in block: String) -> String? {
        var search = block.startIndex..<block.endIndex
        while let open = block.range(of: "<\(tag)", range: search) {
            let after = open.upperBound
            guard after < block.endIndex else { return nil }
            let next = block[after]
            guard next == ">" || next == " " || next == "/" || next == "\n" || next == "\t" else {
                search = after..<block.endIndex
                continue
            }
            guard let close = block.range(of: ">", range: after..<block.endIndex) else { return nil }
            if block[block.index(before: close.lowerBound)] == "/" {
                search = close.upperBound..<block.endIndex
                continue
            }
            guard let end = block.range(of: "</\(tag)>", range: close.upperBound..<block.endIndex) else { return nil }
            return unwrap(String(block[close.upperBound..<end.lowerBound]))
        }
        return nil
    }

    static func attribute(_ name: String, ofTag tag: String, in block: String) -> String? {
        var search = block.startIndex..<block.endIndex
        while let open = block.range(of: "<\(tag)", range: search) {
            guard let close = block.range(of: ">", range: open.upperBound..<block.endIndex) else { return nil }
            let head = String(block[open.upperBound..<close.lowerBound])
            for quote in ["\"", "'"] {
                if let r = head.range(of: "\(name)=\(quote)") {
                    let rest = head[r.upperBound...]
                    if let endQuote = rest.firstIndex(of: Character(quote)) {
                        let value = decodeEntities(String(rest[..<endQuote]))
                        if !value.isEmpty { return value }
                    }
                }
            }
            search = close.upperBound..<block.endIndex
        }
        return nil
    }

    private static func enclosureImage(in block: String) -> String? {
        var search = block.startIndex..<block.endIndex
        while let open = block.range(of: "<enclosure", range: search) {
            guard let close = block.range(of: ">", range: open.upperBound..<block.endIndex) else { return nil }
            let head = String(block[open.upperBound..<close.lowerBound])
            if head.contains("image/"), let url = attribute("url", ofTag: "enclosure", in: block) { return url }
            search = close.upperBound..<block.endIndex
        }
        return nil
    }

    static func unwrap(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("<![CDATA["), s.hasSuffix("]]>") {
            return String(s.dropFirst(9).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return decodeEntities(s)
    }

    static func stripHTML(_ text: String) -> String {
        var out = ""
        var inTag = false
        for ch in text {
            if ch == "<" { inTag = true } else if ch == ">" { inTag = false } else if !inTag { out.append(ch) }
        }
        let decoded = decodeEntities(out)
        return decoded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&", let semi = text[i...].firstIndex(of: ";"), text.distance(from: i, to: semi) <= 10 {
                let name = String(text[text.index(after: i)..<semi])
                if let replacement = entity(name) {
                    out += replacement
                    i = text.index(after: semi)
                    continue
                }
            }
            out.append(text[i])
            i = text.index(after: i)
        }
        return out
    }

    private static func entity(_ name: String) -> String? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        default:
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                if let v = UInt32(name.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { return String(Character(u)) }
            } else if name.hasPrefix("#") {
                if let v = UInt32(name.dropFirst()), let u = Unicode.Scalar(v) { return String(Character(u)) }
            }
            return nil
        }
    }

    /// Reads the date styles feeds use. One reader is made per feed so formatters are reused.
    private final class DateReader {
        private let formats: [DateFormatter]
        private let iso = ISO8601DateFormatter()
        private let isoFractional: ISO8601DateFormatter

        init() {
            func make(_ format: String) -> DateFormatter {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = format
                return f
            }
            formats = [
                make("EEE, dd MMM yyyy HH:mm:ss zzz"),
                make("EEE, dd MMM yyyy HH:mm:ss Z"),
                make("EEE, d MMM yyyy HH:mm:ss Z"),
                make("dd MMM yyyy HH:mm:ss Z")
            ]
            isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        func read(_ text: String) -> Date? {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for f in formats {
                if let d = f.date(from: t) { return d }
            }
            return iso.date(from: t) ?? isoFractional.date(from: t)
        }
    }
}

// MARK: - Grouping

public enum StoryGrouper {
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "after", "over", "into", "says", "said", "has", "have", "had",
        "will", "would", "could", "what", "who", "how", "why", "when", "where", "not", "but", "than", "amid",
        "about", "more", "new", "its", "are", "was", "were", "been", "this", "that", "out", "off", "his",
        "her", "their", "they", "you", "your", "can", "may", "now", "just", "first", "back"
    ]

    static func tokens(_ title: String) -> Set<String> {
        var out = Set<String>()
        var word = ""
        func flush() {
            defer { word = "" }
            guard word.count >= 3, !stopWords.contains(word) else { return }
            if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { word.removeLast() }
            out.insert(word)
        }
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber { word.append(ch) } else { flush() }
        }
        flush()
        return out
    }

    static func similar(_ a: Set<String>, _ b: Set<String>) -> Bool {
        let shared = a.intersection(b).count
        guard shared >= 2 else { return false }
        let smaller = Double(min(a.count, b.count))
        guard smaller > 0 else { return false }
        let overlap = Double(shared) / smaller
        return (shared >= 3 && overlap >= 0.5) || overlap >= 0.66
    }

    /// Groups articles about the same story. Stories covered by more outlets come first, then the newest.
    public static func group(_ articles: [NewsArticle], maxAge: TimeInterval = 48 * 3600,
                             now: Date = Date()) -> [NewsStory] {
        let recent = articles.filter { article in
            guard let date = article.published else { return true }
            return now.timeIntervalSince(date) <= maxAge
        }
        let sorted = recent.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }

        var clusters: [(tokens: [Set<String>], items: [NewsArticle])] = []
        for article in sorted {
            let t = tokens(article.title)
            if !t.isEmpty, let index = clusters.firstIndex(where: { $0.tokens.contains { similar($0, t) } }) {
                clusters[index].tokens.append(t)
                clusters[index].items.append(article)
            } else {
                clusters.append(([t], [article]))
            }
        }

        let stories = clusters.map { cluster -> NewsStory in
            let lead = cluster.items[0]
            let summary = cluster.items.map(\.summary).max { $0.count < $1.count } ?? ""
            return NewsStory(id: lead.id, headline: lead.title, summary: summary, articles: cluster.items)
        }
        return stories.sorted { a, b in
            if a.sources.count != b.sources.count { return a.sources.count > b.sources.count }
            return (a.latest ?? .distantPast) > (b.latest ?? .distantPast)
        }
    }
}

// MARK: - Loading

public struct NewsClient: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func articles(from source: NewsFeedSource) async throws -> [NewsArticle] {
        var request = URLRequest(url: source.url, timeoutInterval: 15)
        request.setValue("CasaPlay/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else { throw OnlineServiceError.badStatus(response.status) }
        return NewsParser.parse(response.body, source: source.name)
    }

    /// Loads every feed at once. A feed that fails is skipped, so one slow outlet never blanks the screen.
    public func stories(from sources: [NewsFeedSource] = NewsFeedSource.defaults) async -> [NewsStory] {
        let all = await withTaskGroup(of: [NewsArticle].self) { group -> [NewsArticle] in
            for source in sources {
                group.addTask { (try? await self.articles(from: source)) ?? [] }
            }
            var out: [NewsArticle] = []
            for await part in group { out += part }
            return out
        }
        return StoryGrouper.group(all)
    }
}
