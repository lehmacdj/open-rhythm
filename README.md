# OpenRhythm

OpenRhythm is a clean-room iOS client for the public Sonolus server and engine
specifications. The initial compatibility target is the Love Live! School idol
festival server at `https://sonolus.milkbun.org/llsif`.

The project intentionally contains no Sonolus application code, assets, keys,
branding, or reverse-engineered implementation details.

## Current milestone

- Load configured public servers.
- Fetch catalogs one server page at a time, loading more near the scroll end.
- Debounce server title/artist search; index downloaded localizations and
  transliterated forms for offline search.
- Group chart variants by song and switch difficulty.
- Sort and filter the loaded catalog with stock SwiftUI controls.
- Discover and download all song difficulties with verified, shared resources.
- Browse downloaded charts together in a cross-server offline catalog.
- Decode Sonolus v13 compressed engine and level data.
- Run the LLSIF engine's lifecycle, input, skin, particle, and audio commands.
- Render fullscreen GPU sprites with corner exit/restart controls and
  predecoded, pooled hit sounds.
- Persist results with navigable score, combo, and judgement breakdowns.

This is still a compatibility milestone, not a complete Sonolus implementation.

## Network behavior

Public catalog/detail responses and artwork use a shared disk cache (10-minute
freshness for mutable URLs, one year for content-addressed URLs). Identical
in-flight requests are coalesced across client instances. The cache is capped at
256 MB; verified offline downloads live separately and are not evicted by it.
Pull-to-refresh explicitly reloads the first catalog page. Browsing does not
crawl the whole server: scrolling requests subsequent pages as needed, with a
manual retry/load-more fallback. Search waits 300 ms after typing stops.

Difficulty discovery searches for the selected song and pages only that result
set, with a safety limit if a server ignores search. Repeated downloads reuse
valid bundles and shared assets. Development regression tests use mocked servers
and local fixtures, not a full milkbun catalog crawl.

## Building

Open `OpenRhythm.xcodeproj` in Xcode, select an iPhone simulator, and run the
`OpenRhythm` scheme.

## Server configuration

The LLSIF server is built in. To replace the server list without adding UI,
place `servers.json` in the app's Documents directory:

```json
[
  {
    "id": "llsif",
    "name": "Love Live! School idol festival",
    "baseURL": "https://sonolus.milkbun.org/llsif"
  }
]
```

## Compatibility notes

The app parses version 13 engine resources and includes a tested core
interpreter for the operations used by the LLSIF engine, including drawing,
judging, scheduled audio, particles, beat conversion, dynamic spawning, resource
availability, and exports. Metal renders the engine's sprite geometry, with a
software fallback; the simpler chart adapter remains for bundles without
presentation resources. Scores still use the app's fixed judgement point values,
not full engine-defined scoring/life rules. General third-party engine
compatibility is not guaranteed. No music, charts, artwork, or third-party
application code is bundled in this repository.
