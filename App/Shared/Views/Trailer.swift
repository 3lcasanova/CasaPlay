// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The Trailer button on a title's page (Apple TV, iPhone and iPad).
//
// Films: Apple's own trailer from the iTunes Store first. It plays right here in Apple's player, in good
// quality, like in the Apple TV app. When Apple has none (and for series), the official trailer on
// YouTube that TMDB lists opens in the YouTube app.

import SwiftUI
import AVKit
import CasaPlayKit

/// Where a title's trailer is.
enum TrailerSource: Equatable {
    /// A video file Apple's player plays in the app.
    case apple(URL)
    /// A YouTube video, opened in the YouTube app.
    case youTube(key: String)
}

enum TrailerFinder {
    /// The best trailer for a title, or nil when there is none. Never throws: no trailer just hides the button.
    static func find(for item: MediaItem, tmdb: TMDBClient?) async -> TrailerSource? {
        if item.tmdbShowID == nil, let url = await appleTrailer(title: item.title, year: item.year) {
            return .apple(url)
        }
        guard let tmdb else { return nil }
        let video: TMDBVideo?
        if let showID = item.tmdbShowID {
            video = try? await tmdb.trailer(showID: showID)
        } else if let movieID = item.tmdbMovieID {
            video = try? await tmdb.trailer(movieID: movieID)
        } else {
            video = nil
        }
        return video.map { .youTube(key: $0.key) }
    }

    // MARK: Apple's trailers

    private struct SearchResult: Decodable {
        let results: [Track]
    }

    private struct Track: Decodable {
        let trackName: String?
        let releaseDate: String?
        let previewUrl: String?
    }

    /// Looks the film up in the iTunes Store and returns its trailer. Same name, and a year no more than one off.
    private static func appleTrailer(title: String, year: Int?) async -> URL? {
        let country = (Locale.current.region?.identifier ?? "US").lowercased()
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: title),
            URLQueryItem(name: "media", value: "movie"),
            URLQueryItem(name: "entity", value: "movie"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: "25"),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let tracks = try JSONDecoder().decode(SearchResult.self, from: data).results
            let wanted = simplified(title)
            let match = tracks.first { track in
                guard let name = track.trackName, simplified(name) == wanted,
                      let preview = track.previewUrl, preview.hasPrefix("https://") else { return false }
                guard let year, let released = track.releaseDate.flatMap({ Int($0.prefix(4)) }) else { return true }
                return abs(released - year) <= 1
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
