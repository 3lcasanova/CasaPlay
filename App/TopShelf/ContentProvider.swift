// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Apple TV Top Shelf. When CasaPlay sits in the top row of the Home Screen and is highlighted,
// the screen above the app row shows what is trending right now, full screen, like the Apple TV app.
// Choosing one opens its page inside CasaPlay (casaplay://title/movie/603 or /tv/1396).
//
// This runs in its own small process, away from the app. It reads the TMDB key that is built into
// its own Info.plist and asks TMDB directly. It never touches your library, keys or profiles.
// With no key, no network or no answer it returns nothing, and tvOS shows the still Top Shelf picture.

import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task {
            let titles = await TopShelfFeed.trending()
            guard !titles.isEmpty else {
                completionHandler(nil)
                return
            }
            let items = titles.map(Self.carouselItem(for:))
            completionHandler(TVTopShelfCarouselContent(style: .details, items: items))
        }
    }

    private static func carouselItem(for title: TopShelfTitle) -> TVTopShelfCarouselItem {
        let item = TVTopShelfCarouselItem(identifier: title.id)
        item.title = title.name
        item.summary = title.summary
        item.genre = title.genre
        // TMDB backdrops are 16:9, the same shape as the full-screen Top Shelf, so nothing is cropped.
        item.setImageURL(TopShelfFeed.imageURL(title.backdropPath, size: "w1280"), for: .screenScale1x)
        item.setImageURL(TopShelfFeed.imageURL(title.backdropPath, size: "original"), for: .screenScale2x)
        if let link = URL(string: "casaplay://title/\(title.kind)/\(title.tmdbID)") {
            item.displayAction = TVTopShelfAction(url: link)
        }
        return item
    }
}

/// One trending film or show, trimmed to what the Top Shelf needs.
struct TopShelfTitle {
    /// "movie" or "tv", as TMDB names them. Also used in the link back into the app.
    let kind: String
    let tmdbID: Int
    let name: String
    let summary: String
    let genre: String?
    let backdropPath: String

    var id: String { "\(kind)-\(tmdbID)" }
}

enum TopShelfFeed {
    private static let maxTitles = 10

    private struct Page: Decodable {
        let results: [Row]
    }

    private struct Row: Decodable {
        let id: Int
        let media_type: String?
        let title: String?
        let name: String?
        let overview: String?
        let backdrop_path: String?
        let genre_ids: [Int]?
    }

    /// This week's trending films and shows that have a wide picture. Empty on any failure.
    static func trending() async -> [TopShelfTitle] {
        let key = apiKey
        guard !key.isEmpty, var parts = URLComponents(string: "https://api.themoviedb.org/3/trending/all/week") else {
            return []
        }
        // Same rule as the app: a 32-character hex string is an API key, anything longer is a read token.
        let usesBearer = !(key.count == 32 && key.allSatisfy(\.isHexDigit))
        var query = [URLQueryItem(name: "language", value: "en-US")]
        if !usesBearer { query.append(URLQueryItem(name: "api_key", value: key)) }
        parts.queryItems = query
        guard let url = parts.url else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 10)
        if usesBearer { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let page = try? JSONDecoder().decode(Page.self, from: data) else {
            return []
        }

        var found: [TopShelfTitle] = []
        for row in page.results {
            guard let kind = row.media_type, kind == "movie" || kind == "tv",
                  let backdrop = row.backdrop_path,
                  let name = row.title ?? row.name, !name.isEmpty else { continue }
            found.append(TopShelfTitle(kind: kind,
                                       tmdbID: row.id,
                                       name: name,
                                       summary: trimmed(row.overview ?? ""),
                                       genre: genre(for: row.genre_ids ?? [], kind: kind),
                                       backdropPath: backdrop))
            if found.count == maxTitles { break }
        }
        return found
    }

    static func imageURL(_ path: String, size: String) -> URL? {
        URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    /// The key copied into this extension's Info.plist from Config/Secrets.xcconfig at build time.
    private static var apiKey: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting can arrive as the literal "$(NAME)".
        return raw.hasPrefix("$(") ? "" : raw
    }

    private static func trimmed(_ text: String) -> String {
        let limit = 260
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }

    /// The first two genre names, as "Action · Thriller". TMDB sends numbers; these are its fixed ones.
    private static func genre(for ids: [Int], kind: String) -> String? {
        let table = kind == "tv" ? tvGenres : movieGenres
        let names = ids.compactMap { table[$0] }.prefix(2)
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    private static let movieGenres: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance",
        878: "Science Fiction", 10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western",
    ]

    private static let tvGenres: [Int: String] = [
        10759: "Action & Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 10762: "Kids", 9648: "Mystery",
        10763: "News", 10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap",
        10767: "Talk", 10768: "War & Politics", 37: "Western",
    ]
}
