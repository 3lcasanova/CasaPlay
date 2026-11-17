# Native playlist provider

This first native adapter reads Extended M3U directly in Swift and returns HTTP
streams through CasaPlay's existing source aggregator. It does not contact Stremio
or execute downloaded scripts. No anime service or videos are bundled.

## Connect a playlist

Open **Servers → Add Server → M3U Playlist**. Enter a name and the full catalog URL.
HTTPS is required except on a local network. A link with a query
(`?username=…&password=…`) is accepted: the query is stored in Keychain, and the saved
server list keeps only the address without it. An optional bearer token is stored
in Keychain too and authenticates only the playlist request. Video URLs must work
without that token (signed HTTPS video URLs are supported).

The playlist can be a static file; it needs no custom API server. A source must
provide the actual video URLs and title/episode mapping. This is not a scraper
for arbitrary streaming websites, and ordinary channel playlists without matching
title IDs will not populate the movie/episode stream picker.

## Catalog format

```m3u
#EXTM3U
#EXTINF:-1 tvg-id="tt1234567",Example movie 1080p
https://media.example.com/movie.mp4
#EXTINF:-1 tvg-id="tt7654321" season="1" episode="2",Example anime S01E02 1080p
https://media.example.com/episode-2/master.m3u8
```

These URLs and IDs are illustrative, not playable content. `tvg-id` must exactly
match CasaPlay's requested title ID (normally IMDb for its TMDB discovery screens).
`season` and `episode` are CasaPlay's matching attributes, not universal M3U tags.
Both are required for episodes; season zero is allowed for specials. Absolute
anime episode numbers must be mapped by the catalog producer. No title guessing
or automatic season-number conversion is performed. Relative video URLs resolve
against the catalog URL. The catalog must be UTF-8 and at most 5 MB; HLS manifests
must be listed as video URLs, not entered as the catalog itself.

## Scope and migration

This adds a native playback source alongside existing providers. It does not yet
replace Stremio's IPTV catalogs, add-on subtitles or extension settings. It does
not add anime discovery, import a library from the playlist, or provide a general
anime-site adapter. Plex/Jellyfin and existing add-ons remain available.

Verification covers strict ID/episode matching, malformed catalog rejection,
relative URLs, unsupported URL schemes and credential separation. Actual playback
must still be tested on iPhone and Apple TV with a provider's working media URLs
before retiring any existing source.
