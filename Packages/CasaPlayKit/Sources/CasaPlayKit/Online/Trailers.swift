// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Finding a title's trailer. TMDB lists the videos of a film or show, and Cinemeta (the open catalogue that
// needs no key) lists a few as a backup. Both name trailers by their YouTube video ID, so that is what comes
// out of here: an ordered list, best first, for the in-app trailer player to try one after the other.
//
// Nothing is downloaded or run from these answers. A video ID is only accepted when it looks like one
// (11 letters, digits, "-" or "_"), because it ends up inside a web address.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Trailer: Hashable, Identifiable, Sendable {
    public var id: String { youTubeID }
    public let youTubeID: String
    public let name: String

    public init?(youTubeID: String, name: String = "Trailer") {
        guard YouTubeLink.isValidID(youTubeID) else { return nil }
        self.youTubeID = youTubeID
        self.name = name
    }
}

// MARK: - YouTube IDs and links

public enum YouTubeLink {
    public static func isValidID(_ text: String) -> Bool {
        text.count == 11 && text.unicodeScalars.allSatisfy { scalar in
            (scalar.value < 128 && CharacterSet.alphanumerics.contains(scalar)) || scalar == "-" || scalar == "_"
        }
    }

    /// The video ID in a YouTube web address (watch?v=…, youtu.be/…, /embed/…, /shorts/…), or nil for anything else.
    public static func videoID(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var host = url.host?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "music."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        let parts = url.path.split(separator: "/").map(String.init)
        var candidate: String?
        switch host {
        case "youtu.be":
            candidate = parts.first
        case "youtube.com", "youtube-nocookie.com":
            if parts.first == "watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            } else if parts.count >= 2, ["embed", "shorts", "v", "live"].contains(parts[0]) {
                candidate = parts[1]
            }
        default:
            return nil
        }
        guard let id = candidate, isValidID(id) else { return nil }
        return id
    }
}

// MARK: - TMDB videos

struct TMDBVideoList: Decodable {
    let results: [TMDBVideo]?
}

struct TMDBVideo: Decodable {
    let key: String?
    let name: String?
    let site: String?
    let type: String?
    let official: Bool?
    let iso_639_1: String?
}

public enum TrailerPicker {
    /// The YouTube trailers in a TMDB video list, best first: trailers before teasers, official before not,
    /// English before other languages. Clips, featurettes and behind-the-scenes videos are left out.
    static func pick(from videos: [TMDBVideo]) -> [Trailer] {
        func rank(_ video: TMDBVideo) -> Int? {
            guard video.site?.lowercased() == "youtube" else { return nil }
            var score: Int
            switch video.type?.lowercased() {
            case "trailer": score = 0
            case "teaser": score = 4
            default: return nil
            }
            if video.official == false { score += 2 }
            if let language = video.iso_639_1?.lowercased(), language != "en" { score += 1 }
            return score
        }
        let ranked = videos.enumerated().compactMap { index, video -> (Int, Int, Trailer)? in
            guard let score = rank(video), let key = video.key,
                  let trailer = Trailer(youTubeID: key, name: video.name ?? "Trailer") else { return nil }
            return (score, index, trailer)
        }
        var seen = Set<String>()
        return ranked.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map(\.2)
            .filter { seen.insert($0.youTubeID).inserted }
    }
}

public extension TMDBClient {
    func movieTrailers(id: Int) async throws -> [Trailer] {
        try await trailers(at: "/movie/\(id)/videos")
    }

    func showTrailers(id: Int) async throws -> [Trailer] {
        try await trailers(at: "/tv/\(id)/videos")
    }
}

// MARK: - Cinemeta (no key needed)

public struct CinemetaTrailers: Sendable {
    private static let base = URL(string: "https://v3-cinemeta.strem.io/meta")!
    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// The trailers Cinemeta lists for an IMDb title. Empty when it has none or the ID is not an IMDb ID.
    public func trailers(imdbID: String, isSeries: Bool) async throws -> [Trailer] {
        guard IMDb.isValidID(imdbID) else { return [] }
        let url = Self.base
            .appendingPathComponent(isSeries ? "series" : "movie")
            .appendingPathComponent("\(imdbID).json")
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else { throw OnlineServiceError.badStatus(response.status) }
        let meta = try JSONDecoder().decode(Answer.self, from: response.body).meta
        var seen = Set<String>()
        let fromTrailers = (meta?.trailers ?? [])
            .filter { ($0.type ?? "Trailer").lowercased() == "trailer" }
            .compactMap { $0.source.flatMap { Trailer(youTubeID: $0) } }
        let fromStreams = (meta?.trailerStreams ?? [])
            .compactMap { entry in entry.ytId.flatMap { Trailer(youTubeID: $0, name: entry.title ?? "Trailer") } }
        return (fromTrailers + fromStreams).filter { seen.insert($0.youTubeID).inserted }
    }

    private struct Answer: Decodable {
        let meta: Meta?
    }

    private struct Meta: Decodable {
        let trailers: [Entry]?
        let trailerStreams: [StreamEntry]?
    }

    private struct Entry: Decodable {
        let source: String?
        let type: String?
    }

    private struct StreamEntry: Decodable {
        let title: String?
        let ytId: String?
    }
}
