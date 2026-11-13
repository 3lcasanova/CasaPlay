// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Invented titles and placeholder data so every screen has something to show
// before a real source is connected. None of these are real films.

import Foundation

public enum DevStreams {
    /// Apple's public HLS example stream (fMP4, with subtitles and several audio renditions).
    /// Used only in debug builds so the player can be tried before a real source exists.
    public static let appleBipBop = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    )!
}

public enum SampleData {
    private static func daysAgo(_ days: Double) -> Date {
        Date(timeIntervalSinceNow: -days * 86_400)
    }

    private static func file(
        _ container: MediaContainer,
        _ video: VideoCodec,
        _ hdr: HDRFormat,
        uhd: Bool,
        audio: [AudioCodec],
        subs: [SubtitleFormat] = []
    ) -> MediaFileInfo {
        MediaFileInfo(
            container: container,
            videoCodec: video,
            hdr: hdr,
            width: uhd ? 3840 : 1920,
            height: uhd ? 2160 : 1080,
            audioCodecs: audio,
            subtitleFormats: subs
        )
    }

    private static let placeholderOverview =
        "Placeholder synopsis. Real details arrive from TMDB once a source is connected."

    private static func film(
        _ title: String,
        _ year: Int,
        _ minutes: Int,
        _ rating: String,
        hue: Double,
        media: MediaFileInfo,
        genres: [String] = ["Drama"],
        progress: Double = 0,
        watched: Bool = false,
        favorite: Bool = false,
        added: Double = 30,
        collection: String? = nil
    ) -> MediaItem {
        let runtime = TimeInterval(minutes * 60)
        return MediaItem(
            title: title,
            year: year,
            runtimeSeconds: runtime,
            rating: rating,
            overview: placeholderOverview,
            genres: genres,
            file: media,
            sourceName: "Home NAS",
            collection: collection,
            artHue: hue,
            progressSeconds: runtime * progress,
            isWatched: watched,
            isFavorite: favorite,
            addedAt: daysAgo(added),
            lastPlayedAt: progress > 0 ? daysAgo(added / 4) : nil
        )
    }

    public static let movies: [MediaItem] = {
        var list: [MediaItem] = []

        list.append(MediaItem(
            title: "Night Ferry",
            year: 2025,
            runtimeSeconds: 124 * 60,
            rating: "PG-13",
            overview: "A night ferry crosses a frozen strait with forty strangers and one stolen ledger. When the engines fail halfway, the crew has until dawn to decide who they can trust.",
            genres: ["Drama", "Thriller"],
            file: file(.mp4, .hevc, .dolbyVision, uhd: true, audio: [.eac3Atmos, .aac], subs: [.tx3g]),
            sourceName: "Home NAS",
            tmdbRating: 7.4,
            cast: [
                CastMember(name: "Mara Linden", role: "Capt. Hale"),
                CastMember(name: "Teo Vasquez", role: "Daniel Ruiz"),
                CastMember(name: "Idris Kamau", role: "Chief Engineer"),
                CastMember(name: "Lena Voss", role: "The Courier"),
                CastMember(name: "June Okafor", role: "First Mate"),
                CastMember(name: "Aldo Ferrante", role: "Mr. Brandt"),
                CastMember(name: "Sofia Marchetti", role: "Passenger")
            ],
            artHue: 40,
            progressSeconds: 4328,
            isFavorite: true,
            addedAt: daysAgo(1),
            lastPlayedAt: daysAgo(0.2)
        ))

        list.append(film("Salt & Iron", 2023, 105, "R", hue: 15,
                         media: file(.mkv, .h264, .sdr, uhd: false, audio: [.dts, .ac3], subs: [.srt]),
                         genres: ["Drama", "Crime"], progress: 0.12, added: 3))
        list.append(film("Orbit Nine", 2024, 118, "PG-13", hue: 235,
                         media: file(.mp4, .hevc, .hdr10, uhd: true, audio: [.eac3]),
                         genres: ["Sci-Fi"], progress: 0.72, added: 2))
        list.append(film("The Quiet Mile", 2022, 96, "PG", hue: 130,
                         media: file(.mp4, .h264, .sdr, uhd: false, audio: [.aac]),
                         watched: true, added: 40))
        list.append(film("Cobalt Hour", 2021, 112, "R", hue: 250,
                         media: file(.mkv, .hevc, .hdr10, uhd: true, audio: [.truehd], subs: [.pgs]),
                         genres: ["Thriller"], watched: true, added: 60))
        list.append(film("Wild Meridian", 2019, 128, "PG-13", hue: 85,
                         media: file(.mp4, .hevc, .sdr, uhd: true, audio: [.aac]),
                         genres: ["Adventure"], progress: 0.4, added: 90))
        list.append(film("Last Station", 2020, 101, "R", hue: 260,
                         media: file(.mp4, .h264, .sdr, uhd: false, audio: [.aac]),
                         watched: true, added: 75))
        list.append(film("Paper Moons", 2018, 94, "PG", hue: 300,
                         media: file(.m4v, .h264, .sdr, uhd: false, audio: [.aac, .ac3]),
                         genres: ["Family"], added: 120))
        list.append(film("Harbor Lights", 2024, 109, "PG-13", hue: 55,
                         media: file(.mp4, .hevc, .dolbyVision, uhd: true, audio: [.eac3Atmos]),
                         progress: 0.4, favorite: true, added: 4, collection: "Harbor Lights Collection"))
        list.append(film("Kiln", 2023, 100, "R", hue: 20,
                         media: file(.avi, .h264, .sdr, uhd: false, audio: [.ac3]),
                         watched: true, added: 150))
        list.append(film("Tidewater", 2022, 107, "PG-13", hue: 175,
                         media: file(.mp4, .hevc, .hdr10, uhd: true, audio: [.eac3]),
                         added: 8))
        list.append(film("Northbound", 2017, 99, "PG", hue: 225,
                         media: file(.mp4, .h264, .sdr, uhd: false, audio: [.aac]),
                         watched: true, added: 200))

        return list
    }()

    public static let profiles: [Profile] = [
        Profile(name: "3iAtlas", hue: 65, preferredSubtitleLanguages: ["en", "fr", "ht"]),
        Profile(name: "Family", hue: 200),
        Profile(name: "Kids", hue: 150, isKids: true),
        Profile(name: "Guest", hue: 290)
    ]

    public static let sources: [MediaSource] = [
        MediaSource(name: "This Mac", detail: "Movies folder · macOS File Sharing", kind: .mac, status: .connected),
        MediaSource(name: "Home NAS", detail: "SMB · Movies and Shows folders", kind: .nas, status: .connected),
        MediaSource(name: "Plex Media Server", detail: "Home server · signed in with Plex", kind: .plex, status: .connected),
        MediaSource(name: "Jellyfin", detail: "Home server · jellyfin.local", kind: .jellyfin, status: .scanning),
        MediaSource(name: "Network share", detail: "WebDAV or NFS folder", kind: .network, status: .notSetUp)
    ]

    public static let subtitleTracks: [SubtitleTrack] = [
        SubtitleTrack(id: "en-emb", languageCode: "en", displayName: "English", origin: .embedded, format: .tx3g),
        SubtitleTrack(id: "en-sdh", languageCode: "en", displayName: "English SDH", origin: .sidecar, format: .srt, isSDH: true),
        SubtitleTrack(id: "fr-emb", languageCode: "fr-CA", displayName: "Français (Canada)", origin: .embedded, format: .tx3g),
        SubtitleTrack(id: "ht-web", languageCode: "ht", displayName: "Kreyòl ayisyen", origin: .online, format: .srt),
        SubtitleTrack(id: "es-emb", languageCode: "es", displayName: "Español", origin: .embedded, format: .tx3g)
    ]
}
