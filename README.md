# CasaPlay

A premium 4K media player for Apple TV, iPhone and iPad. It plays movies and shows from a Mac, a NAS or a home media server.

Designed by 𝐂𝓪sΔηⓞשα.

## Status: early build

This is Phase 0 and the start of Phase 1 from the design canvas.

**Real and working in code**
- The shared SwiftUI app for tvOS, iOS and iPadOS: Home, Movies, Series, IPTV (live channels from your Stremio add-ons), Extensions, Servers, Profile, Title detail, Settings.
- A native player built on `AVPlayerViewController`, with resume and 5-second progress saving.
- `CasaPlayKit`, a Swift package with the logic that does not depend on the UI:
  - filename parser (`Movie.Name.2025.2160p.mkv`)
  - SRT and WebVTT parsing, subtitle selection and style
  - the playback router that decides Apple engine, server stream or compatibility engine
  - IMDb: IDs read from file names, links, and ratings through OMDb
  - OpenSubtitles search, download and sign-in
  - subtitle files next to a video (`Movie.fr.forced.srt`), with any text encoding
  - unit tests for all of it, using a fake network
- **IMDb** rating badge on Home and Detail, and a link to the IMDb page on iPhone and iPad.
- **Subtitles** drawn by CasaPlay over the video in the viewer's style (size, colour, background, position, delay). Choose a track on the Detail screen or in the player: the transport bar menu on Apple TV, the captions button on iPhone and iPad. "Find subtitles online" searches OpenSubtitles.
- **Online services** (Profile › Online services): enter an OMDb key for IMDb ratings and an OpenSubtitles API key. Both are free. Keys stay on the device.

**Sample data for now**
- The 12 movies, 4 profiles and 5 sources are invented. Nothing reads your Mac or NAS yet.
- Artwork is generated colour gradients. Real posters arrive with TMDB in Phase 2.
- In Debug builds, Play streams Apple's public HLS test stream so you can try the player, with a short English demo subtitle track. Release builds show "No source yet".
- The sample titles are invented, so they have sample IMDb ratings but no IMDb IDs or pages.

**Not built yet**
- Source adapters (SMB, NFS, WebDAV, Plex, Jellyfin), library scanning and database
- ASS/SSA styling and image subtitles (PGS, VobSub) in the overlay
- Compatibility engine (VLCKit or FFmpeg)
- iCloud sync, per-profile watch history

## BitTorrent (experimental)

The **Torrents** tab adds magnet links and `.torrent` files, fetches the metadata, lists the files, and streams a chosen MP4/MOV/M4V while it downloads. Seeking jumps the download to the new position.

- **Engine:** a small Swift BitTorrent v1 client in `CasaPlayKit/Torrent` (BEP 3 peers, BEP 9/10 metadata for magnets, BEP 19 HTTPS web seeds, BEP 23 HTTP trackers). Every piece is SHA-1 checked before it is stored or played. Peer connections use Apple's Network framework.
- **Player:** `AVAssetResourceLoader` serves byte ranges from verified pieces (`App/Shared/Player/TorrentResourceLoader.swift`). Missing ranges wait while those pieces are fetched first, so AVPlayer shows its normal buffering state.
- **Sources** are separate from transfers: Internet Archive search (public-domain and Creative Commons films only) and RSS feeds the user adds. Sources only hand over magnet links or `.torrent` files.
- **Storage:** one sparse file per torrent, named by info-hash, inside CasaPlay's container. Names from torrents are never used as paths, and downloaded files are never opened or executed. Apple TV uses Caches (tvOS may purge it); iPhone and iPad use Application Support, excluded from backup. There is a cache limit and a free-space reserve.
- **Privacy:** trackers and peers see the device's IP address. Uploading while downloading is on (100 KB/s) and can be turned off; seeding after download is off. There is no listening port.
- **Background:** iOS, iPadOS and tvOS suspend apps, so transfers stop in the background and resume when CasaPlay is open again.
- **Not yet:** DHT, peer exchange, UDP trackers, uTP, BitTorrent v2, MKV/AVI playback (the "compatibility engine").
- **App Store:** Apple's guideline 5.2.3 forbids apps that facilitate illegal file sharing or download media from third-party sources without authorization. Torrent clients have historically been rejected, so distribution through the App Store is not assured even for lawful use. Development builds, TestFlight review and (for iOS/iPadOS in the EU) alternative distribution are separate questions.

Live check against an openly licensed torrent (Big Buck Bunny, CC BY 3.0):

```
cd Packages/CasaPlayKit
CASAPLAY_LIVE_TORRENT=1 swift test --filter LiveTorrentTests
```

## Build status

GitHub Actions builds every push on a Mac (`.github/workflows/build.yml`):
- **CasaPlay-iOS** (iPhone and iPad) for the iOS Simulator
- **CasaPlay-tvOS** (Apple TV) for the tvOS Simulator
- the CasaPlayKit unit tests

## Build it

You need a Mac with Xcode 15 or newer.

1. Install XcodeGen once: `brew install xcodegen`
2. In this folder run: `xcodegen generate`
3. Open `CasaPlay.xcodeproj`.
4. Pick the **CasaPlay-tvOS** or **CasaPlay-iOS** scheme and a simulator.
5. For a real device, set your Team under Signing & Capabilities. The bundle ID `com.casanova.CasaPlay` is a placeholder; change `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` if you want another.

### API keys

IMDb ratings (OMDb) and OpenSubtitles need API keys. Put them in `Config/Secrets.xcconfig`, which git ignores, so the keys never reach GitHub:

1. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`.
2. Fill in `OMDB_API_KEY` and `OPENSUBTITLES_API_KEY`.
3. Run `xcodegen generate` again and build.

The build copies the keys into the app. Keys typed in Profile › Online services take priority. Without the file the app still builds and asks for keys there.

Run the package tests without Xcode's UI:

```
cd Packages/CasaPlayKit
swift test
```

### Without XcodeGen

1. In Xcode choose File > New > Project > Multiplatform > App and name it CasaPlay.
2. Add the folder `Packages/CasaPlayKit` with File > Add Package Dependencies > Add Local.
3. Drag the files from `App/Shared` into the project and add the `App/Resources` asset catalog.
4. Set the deployment target to 17.0 and set `NSLocalNetworkUsageDescription` and `NSBonjourServices` as in `project.yml`.

## Layout

```
project.yml                  XcodeGen spec (iOS + iPadOS target, tvOS target)
App/Shared/                  SwiftUI app, shared by all three platforms
  Design/                    colours, sizes, poster cards, chips
  Views/                     Home, Library, Detail, Sources, Profile, Settings
  Player/                    PlayerScreen and the AVKit wrapper
App/Resources/               asset catalog (accent colour)
Packages/CasaPlayKit/        models, parsers, subtitles, playback router, tests
```

## Before App Store

- App icons exist: `AppIcon` for iPhone and iPad, and `App Icon & Top Shelf Image` for Apple TV (three-layer parallax icon plus Top Shelf and Top Shelf Wide). `Scripts/make_tv_assets.py` regenerates the Apple TV set.
- Check the licence of any playback library you add. VLCKit is LGPL.
- TMDB requires its attribution and logo. OpenSubtitles needs an API key.
