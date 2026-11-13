// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// OpenSubtitles.com REST API (v1). Needs a free API key from
// opensubtitles.com/consumers. Without signing in, an API key allows a few
// downloads a day; a username and password raise that limit.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One subtitle file found online.
public struct OnlineSubtitle: Identifiable, Hashable, Sendable {
    public var id: Int { fileID }
    public var fileID: Int
    public var languageCode: String
    public var release: String
    public var fileName: String
    public var downloadCount: Int
    public var isSDH: Bool
    public var isForced: Bool
    public var isMachineTranslated: Bool
    public var fromTrusted: Bool

    public init(
        fileID: Int,
        languageCode: String,
        release: String,
        fileName: String = "",
        downloadCount: Int = 0,
        isSDH: Bool = false,
        isForced: Bool = false,
        isMachineTranslated: Bool = false,
        fromTrusted: Bool = false
    ) {
        self.fileID = fileID
        self.languageCode = languageCode
        self.release = release
        self.fileName = fileName
        self.downloadCount = downloadCount
        self.isSDH = isSDH
        self.isForced = isForced
        self.isMachineTranslated = isMachineTranslated
        self.fromTrusted = fromTrusted
    }

    public var track: SubtitleTrack {
        var name = LanguageNames.displayName(languageCode)
        if isSDH { name += " SDH" }
        if isForced { name += " (forced)" }
        return SubtitleTrack(
            id: "os-\(fileID)",
            languageCode: languageCode,
            displayName: name,
            origin: .online,
            format: .srt,
            isSDH: isSDH,
            isForced: isForced
        )
    }
}

public struct OpenSubtitlesClient: Sendable {
    public var apiKey: String
    /// Optional session token from `login`. Raises the daily download limit.
    public var token: String?
    public var transport: HTTPTransport
    public var baseURL = URL(string: "https://api.opensubtitles.com/api/v1/")!
    public var userAgent = "CasaPlay v0.1.0"

    public init(apiKey: String, token: String? = nil, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.token = token
        self.transport = transport
    }

    // MARK: Search

    public enum Query: Equatable, Sendable {
        case imdb(String)
        case title(String, year: Int?)
    }

    /// Finds subtitles and returns them best first: preferred language order,
    /// human-made before machine-translated, trusted uploaders, then popularity.
    public func search(_ query: Query, languages: [String]) async throws -> [OnlineSubtitle] {
        let request = try searchRequest(query, languages: languages)
        let response = try await transport.send(request)
        try check(response)
        let results = try Self.parseSearch(response.body)
        return Self.rank(results, languages: languages)
    }

    func searchRequest(_ query: Query, languages: [String]) throws -> URLRequest {
        var items: [URLQueryItem] = []
        switch query {
        case .imdb(let id):
            // The API wants the number without "tt" and without leading zeros.
            let digits = id.lowercased().replacingOccurrences(of: "tt", with: "")
            items.append(URLQueryItem(name: "imdb_id", value: String(Int(digits) ?? 0)))
        case .title(let title, let year):
            items.append(URLQueryItem(name: "query", value: title.lowercased()))
            if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
        }
        let codes = languages.map { $0.lowercased() }.filter { !$0.isEmpty }
        if !codes.isEmpty {
            items.append(URLQueryItem(name: "languages", value: codes.sorted().joined(separator: ",")))
        }
        // The API asks for parameters in alphabetical order to make caching work.
        items.sort { $0.name < $1.name }

        var components = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        return try authorized(URLRequest(url: components.url!))
    }

    static func parseSearch(_ data: Data) throws -> [OnlineSubtitle] {
        struct Payload: Decodable {
            struct Item: Decodable {
                struct Attributes: Decodable {
                    struct File: Decodable {
                        let file_id: Int
                        let file_name: String?
                    }
                    let language: String?
                    let release: String?
                    let download_count: Int?
                    let hearing_impaired: Bool?
                    let foreign_parts_only: Bool?
                    let machine_translated: Bool?
                    let ai_translated: Bool?
                    let from_trusted: Bool?
                    let files: [File]?
                }
                let attributes: Attributes
            }
            let data: [Item]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw OnlineServiceError.invalidResponse
        }
        return payload.data.compactMap { item in
            let a = item.attributes
            guard let file = a.files?.first, let language = a.language else { return nil }
            return OnlineSubtitle(
                fileID: file.file_id,
                languageCode: language,
                release: a.release ?? file.file_name ?? "",
                fileName: file.file_name ?? "",
                downloadCount: a.download_count ?? 0,
                isSDH: a.hearing_impaired ?? false,
                isForced: a.foreign_parts_only ?? false,
                isMachineTranslated: (a.machine_translated ?? false) || (a.ai_translated ?? false),
                fromTrusted: a.from_trusted ?? false
            )
        }
    }

    static func rank(_ results: [OnlineSubtitle], languages: [String]) -> [OnlineSubtitle] {
        let order = languages.map { LanguageNames.base($0) }
        func languageRank(_ s: OnlineSubtitle) -> Int {
            order.firstIndex(of: LanguageNames.base(s.languageCode)) ?? order.count
        }
        return results.sorted { a, b in
            if languageRank(a) != languageRank(b) { return languageRank(a) < languageRank(b) }
            if a.isMachineTranslated != b.isMachineTranslated { return !a.isMachineTranslated }
            if a.fromTrusted != b.fromTrusted { return a.fromTrusted }
            return a.downloadCount > b.downloadCount
        }
    }

    // MARK: Download

    /// Asks for a download link, fetches the file and parses it into cues.
    public func download(_ subtitle: OnlineSubtitle) async throws -> [SubtitleCue] {
        let linkResponse = try await transport.send(try downloadRequest(fileID: subtitle.fileID))
        try check(linkResponse)
        let link = try Self.parseDownloadLink(linkResponse.body)
        let file = try await transport.send(URLRequest(url: link))
        guard file.status == 200 else { throw OnlineServiceError.badStatus(file.status) }
        let cues = SubtitleLoader.cues(from: file.body, format: .srt)
        guard !cues.isEmpty else { throw OnlineServiceError.invalidResponse }
        return cues
    }

    func downloadRequest(fileID: Int) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("download"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileID, "sub_format": "srt"])
        return try authorized(request)
    }

    static func parseDownloadLink(_ data: Data) throws -> URL {
        struct Payload: Decodable { let link: String? }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let raw = payload.link, let url = URL(string: raw) else {
            throw OnlineServiceError.invalidResponse
        }
        return url
    }

    // MARK: Login

    /// Signs in and returns a token to store and pass as `token`.
    public func login(username: String, password: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let response = try await transport.send(try authorized(request))
        try check(response)
        struct Payload: Decodable { let token: String? }
        guard let token = (try? JSONDecoder().decode(Payload.self, from: response.body))?.token else {
            throw OnlineServiceError.invalidResponse
        }
        return token
    }

    // MARK: Helpers

    private func authorized(_ request: URLRequest) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OnlineServiceError.missingAPIKey(service: "OpenSubtitles") }
        var request = request
        request.setValue(key, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func check(_ response: HTTPResponse) throws {
        switch response.status {
        case 200: return
        case 401, 403: throw OnlineServiceError.missingAPIKey(service: "OpenSubtitles")
        case 406, 429:
            struct Payload: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Payload.self, from: response.body))?.message
            throw OnlineServiceError.quotaReached(
                message: message ?? "The OpenSubtitles download limit for today has been reached."
            )
        default: throw OnlineServiceError.badStatus(response.status)
        }
    }
}

public enum LanguageNames {
    /// "fr-CA" -> "fr", "pt-BR" -> "pt"
    public static func base(_ code: String) -> String {
        let lowered = code.lowercased()
        return lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? lowered
    }

    /// "fr" -> "French" (in the device language), unknown codes are shown upper-cased.
    public static func displayName(_ code: String) -> String {
        let known: [String: String] = ["ht": "Haitian Creole"]
        if let name = Locale.current.localizedString(forLanguageCode: base(code)), name.lowercased() != base(code) {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return known[base(code)] ?? code.uppercased()
    }
}
