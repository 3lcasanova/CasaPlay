# CasaPlay

A premium 4K media player for Apple TV, iPhone and iPad. It plays movies and shows from a Mac, a NAS or a home media server.

Designed by 𝐂𝓪sΔηⓞשα.

## Status: early build

This is Phase 0 and the start of Phase 1 from the design canvas.

**Real and working in code**
- The shared SwiftUI app for tvOS, iOS and iPadOS: Home, Movies, Favorites, Sources, Profile, Title detail, Settings.
- A native player built on `AVPlayerViewController`, with resume and 5-second progress saving.
- `CasaPlayKit`, a Swift package with the logic that does not depend on the UI:
  - filename parser (`Movie.Name.2025.2160p.mkv`)
  - SRT and WebVTT parsing, subtitle selection and style
  - the playback router that decides Apple engine, server stream or compatibility engine
  - unit tests for all of it

**Sample data for now**
- The 12 movies, 4 profiles and 5 sources are invented. Nothing reads your Mac or NAS yet.
- Artwork is generated colour gradients. Real posters arrive with TMDB in Phase 2.
- In Debug builds, Play streams Apple's public HLS test stream so you can try the player. Release builds show "No source yet".

**Not built yet**
- Source adapters (SMB, NFS, WebDAV, Plex, Jellyfin), library scanning and database
- Custom subtitle overlay, OpenSubtitles
- Compatibility engine (VLCKit or FFmpeg)
- iCloud sync, per-profile watch history

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
5. For a real device, set your Team under Signing & Capabilities. The bundle ID `com.casanova.casaplay` is a placeholder; change `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` if you want another.

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
