// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The Trailer button on a title's page (Apple TV, iPhone and iPad).
//
// Apple's own trailer from the iTunes Store first, for films and series. It plays right here in Apple's
// player, in good quality, like in the Apple TV app. The Canadian store is asked first, then the American
// one. When Apple has none, the official trailer on YouTube that TMDB lists is used. On iPhone and iPad it
// plays inside CasaPlay in YouTube's own embedded player (TrailerScreen). Apple TV has no web view, and
// YouTube's videos can't be played outside YouTube's own player, so there the Trailer button only shows
// when Apple has the trailer: CasaPlay never sends the viewer out to the YouTube app.

import SwiftUI
import AVKit
import CasaPlayKit

/// Where a title's trailer is.
enum TrailerSource: Equatable {
    /// A video file Apple's player plays in the app.
    case apple(URL)
    /// A YouTube video, played in the app on iPhone and iPad. Never offered on Apple TV.
    case youTube(key: String)
}

enum TrailerFinder {
    /// The best trailer for a title, or nil when there is none. Never throws: no trailer just hides the button.
    static func find(for item: MediaItem, tmdb: TMDBClient?) async -> TrailerSource? {
        let isShow = item.tmdbShowID != nil
        if let url = await appleTrailer(title: item.title, year: item.year, isShow: isShow) {
            return .apple(url)
        }
        #if os(tvOS)
        // Apple TV can only play Apple's trailer inside CasaPlay. With none, there is no Trailer button,
        // so the viewer is never sent out to the YouTube app.
        return nil
        #else
        var video: TMDBVideo?
        if let tmdb {
            if let showID = item.tmdbShowID {
                video = try? await tmdb.trailer(showID: showID)
            } else if let movieID = item.tmdbMovieID {
                video = try? await tmdb.trailer(movieID: movieID)
            }
        }
        if let video { return .youTube(key: video.key) }
        // No TMDB key, or TMDB lists none: Cinemeta, which needs no key, knows titles by their IMDb ID.
        guard let imdb = item.imdbID, !imdb.isEmpty else { return nil }
        let listed = (try? await CinemetaTrailers().trailers(imdbID: imdb, isSeries: isShow)) ?? []
        return listed.first.map { .youTube(key: $0.youTubeID) }
        #endif
    }

    // MARK: Apple's trailers

    private struct SearchResult: Decodable {
        let results: [Track]
    }

    private struct Track: Decodable {
        /// A film's name.
        let trackName: String?
        /// A series' name, for a season.
        let artistName: String?
        /// "Severance, Season 1", for a season.
        let collectionName: String?
        let releaseDate: String?
        let previewUrl: String?
    }

    /// The stores asked, in order: the Apple TV's own, then the American one, which has the most trailers.
    private static var stores: [String] {
        let own = (Locale.current.region?.identifier ?? "CA").lowercased()
        return own == "us" ? ["us"] : [own, "us"]
    }

    /// Looks the title up in the iTunes Store and returns its trailer.
    private static func appleTrailer(title: String, year: Int?, isShow: Bool) async -> URL? {
        for store in stores {
            if let url = await appleTrailer(title: title, year: year, isShow: isShow, store: store) { return url }
        }
        return nil
    }

    private static func appleTrailer(title: String, year: Int?, isShow: Bool, store: String) async -> URL? {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: title),
            URLQueryItem(name: "media", value: isShow ? "tvShow" : "movie"),
            URLQueryItem(name: "entity", value: isShow ? "tvSeason" : "movie"),
            URLQueryItem(name: "country", value: store),
            URLQueryItem(name: "limit", value: "50"),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let tracks = try JSONDecoder().decode(SearchResult.self, from: data).results
                .filter { $0.previewUrl?.hasPrefix("https://") == true }
            let wanted = simplified(title)
            let match: Track?
            if isShow {
                // Same series name; the first season's trailer when there is one, otherwise any season's.
                let seasons = tracks.filter { simplified($0.artistName ?? "") == wanted }
                match = seasons.first { ($0.collectionName ?? "").hasSuffix("Season 1") } ?? seasons.first
            } else {
                // Same name, and a year no more than one off.
                match = tracks.first { track in
                    guard simplified(track.trackName ?? "") == wanted else { return false }
                    guard let year, let released = track.releaseDate.flatMap({ Int($0.prefix(4)) }) else { return true }
                    return abs(released - year) <= 1
                }
            }
            return match?.previewUrl.flatMap(URL.init(string:))
        } catch {
            return nil
        }
    }

    /// "Spider-Man: No Way Home" and "Spider Man No Way Home" are the same name.
    private static func simplified(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Playing it

/// Apple's trailer, full screen in Apple's player. It closes by itself when the trailer ends.
struct TrailerPlayer: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        context.coordinator.observe(player)
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        controller.player = nil
    }

    final class Coordinator {
        private let onFinish: () -> Void
        private var token: NSObjectProtocol?

        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func observe(_ player: AVPlayer) {
            token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                           object: player.currentItem, queue: .main) { [weak self] _ in
                self?.onFinish()
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

/// Wraps the trailer's address for `fullScreenCover(item:)`.
struct TrailerPlayback: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The YouTube app's links. Apple TV's YouTube app answers `youtube://watch/<id>`; on iPhone and iPad the web
/// link opens the YouTube app when it's installed, or Safari when it isn't.
enum YouTubeLinks {
    static func candidates(for key: String) -> [URL] {
        #if os(tvOS)
        return [URL(string: "youtube://watch/\(key)"), URL(string: "youtube://www.youtube.com/watch?v=\(key)")]
            .compactMap { $0 }
        #else
        return [URL(string: "https://www.youtube.com/watch?v=\(key)")].compactMap { $0 }
        #endif
    }
}
