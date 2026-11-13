// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Source providers find torrents through documented APIs or feeds the user chooses.
// They only return magnet links or .torrent URLs; the engine does the transfer.
// Providers never log in on the user's behalf or get around access controls: a source
// that refuses a request (401/403) is reported as unavailable.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct TorrentCandidate: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    /// The licence or permission the source states, shown to the user.
    public var license: String?
    public var magnet: String?
    public var torrentURL: URL?
    public var pageURL: URL?

    public init(id: String, title: String, detail: String = "", license: String? = nil,
                magnet: String? = nil, torrentURL: URL? = nil, pageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.license = license
        self.magnet = magnet
        self.torrentURL = torrentURL
        self.pageURL = pageURL
    }
}

public protocol TorrentSourceProvider: Sendable {
    var name: String { get }
    var summary: String { get }
    func search(_ query: String) async throws -> [TorrentCandidate]
}

/// Internet Archive's documented Advanced Search API, limited to films the Archive lists
/// as public domain or under a Creative Commons licence. Every result has an
/// Archive-made torrent with HTTPS web seeds.
public struct InternetArchiveProvider: TorrentSourceProvider {
    public let name = "Internet Archive"
    public let summary = "Public-domain and Creative Commons films from archive.org"
    public var transport: HTTPTransport
    public var rows = 30

    public init(transport: HTTPTransport = URLSessionTransport()) { self.transport = transport }

    func request(for query: String) -> URLRequest {
        let cleaned = query
            .replacingOccurrences(of: #"[^\p{L}\p{N} '\-]"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var q = "mediatype:(movies) AND (licenseurl:*publicdomain* OR licenseurl:*creativecommons*)"
        if !cleaned.isEmpty { q = "(\(cleaned)) AND " + q }
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "year"),
            URLQueryItem(name: "fl[]", value: "licenseurl"),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "rows", value: String(rows)),
            URLQueryItem(name: "output", value: "json")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("CasaPlay/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return request
    }

    public func search(_ query: String) async throws -> [TorrentCandidate] {
        let response = try await transport.send(request(for: query))
        guard response.status == 200 else { throw TorrentError.sourceFailed("Internet Archive answered \(response.status).") }
        return try Self.parse(response.body)
    }

    static func parse(_ data: Data) throws -> [TorrentCandidate] {
        struct Payload: Decodable {
            struct Response: Decodable { let docs: [Doc] }
            struct Doc: Decodable {
                let identifier: String
                let title: FlexibleString?
                let year: FlexibleString?
                let licenseurl: FlexibleString?
            }
            let response: Response
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw TorrentError.sourceFailed("Internet Archive sent an unexpected reply.")
        }
        return payload.response.docs.compactMap { doc in
            // Identifiers are [A-Za-z0-9._-]; anything else is skipped.
            guard doc.identifier.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil,
                  let torrent = URL(string: "https://archive.org/download/\(doc.identifier)/\(doc.identifier)_archive.torrent")
            else { return nil }
            let license = doc.licenseurl?.value.map(Self.licenseName)
            return TorrentCandidate(
                id: "ia:\(doc.identifier)",
                title: doc.title?.value ?? doc.identifier,
                detail: [doc.year?.value, "archive.org"].compactMap { $0 }.joined(separator: " · "),
                license: license,
                torrentURL: torrent,
                pageURL: URL(string: "https://archive.org/details/\(doc.identifier)")
            )
        }
    }

    static func licenseName(_ url: String) -> String {
        let lower = url.lowercased()
        if lower.contains("publicdomain") { return "Public domain" }
        if let range = lower.range(of: #"licenses/([a-z-]+)/([0-9.]+)"#, options: .regularExpression) {
            let parts = lower[range].split(separator: "/")
            if parts.count >= 3 { return "CC \(parts[1].uppercased()) \(parts[2])" }
        }
        return "Creative Commons"
    }
}

/// Some Archive fields are a string or an array of strings.
struct FlexibleString: Decodable, Hashable {
    let value: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([String].self) { value = a.first }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else { value = nil }
    }
}

/// An RSS feed the user adds, e.g. a project's release feed. Items need a torrent
/// enclosure (application/x-bittorrent) or a magnet link.
public struct RSSFeedProvider: TorrentSourceProvider {
    public let name: String
    public let summary: String
    public let feedURL: URL
    public var transport: HTTPTransport

    public init(name: String, feedURL: URL, transport: HTTPTransport = URLSessionTransport()) {
        self.name = name
        self.summary = feedURL.host ?? feedURL.absoluteString
        self.feedURL = feedURL
        self.transport = transport
    }

    public func search(_ query: String) async throws -> [TorrentCandidate] {
        guard feedURL.scheme?.lowercased() == "https" else { throw TorrentError.sourceFailed("Feeds must use HTTPS.") }
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 20
        let response = try await transport.send(request)
        guard response.status == 200, response.body.count < 5 * 1024 * 1024 else {
            throw TorrentError.sourceFailed("The feed answered \(response.status).")
        }
        let items = RSSTorrentParser.parse(response.body)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? items : items.filter { $0.title.lowercased().contains(q) }
    }
}

final class RSSTorrentParser: NSObject, XMLParserDelegate {
    private var items: [TorrentCandidate] = []
    private var title = ""
    private var link = ""
    private var enclosure: String?
    private var inItem = false
    private var text = ""

    static func parse(_ data: Data) -> [TorrentCandidate] {
        let delegate = RSSTorrentParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false  // no XXE
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "item", "entry": inItem = true; title = ""; link = ""; enclosure = nil
        case "enclosure":
            if attributes["type"] == "application/x-bittorrent" || (attributes["url"] ?? "").hasSuffix(".torrent") {
                enclosure = attributes["url"]
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inItem else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": title = value
        case "link": link = value
        case "item", "entry":
            inItem = false
            var candidate = TorrentCandidate(id: "rss:\(items.count):\(title)", title: title.isEmpty ? "Untitled" : String(title.prefix(200)))
            if link.lowercased().hasPrefix("magnet:"), (try? MagnetLink(parsing: link)) != nil {
                candidate.magnet = link
            }
            if let e = enclosure, let url = URL(string: e), url.scheme?.lowercased() == "https" {
                candidate.torrentURL = url
            }
            if candidate.magnet != nil || candidate.torrentURL != nil { items.append(candidate) }
        default: break
        }
    }
}
