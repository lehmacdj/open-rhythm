# OpenRhythm

OpenRhythm is a clean-room iOS client for the public Sonolus server and engine
specifications. The initial compatibility target is the Love Live! School idol
festival server at `https://sonolus.milkbun.org/llsif`.

The project intentionally contains no Sonolus application code, assets, keys,
branding, or reverse-engineered implementation details.

## Current milestone

- Load configured public servers.
- Fetch paginated catalogs, preloading at most two pages ahead of scrolling.
- Debounce server title/artist search; index downloaded localizations and
  transliterated forms for offline search.
- Group chart variants by song and switch difficulty.
- Save per-engine sort and difficulty filters, with a two-handle rating slider.
- Discover and download all song difficulties with verified, shared resources.
- Browse downloaded charts together in a cross-server offline catalog.
- Update or delete all downloaded difficulties from song details.
- Decode Sonolus v13 compressed engine and level data.
- Run the LLSIF engine's lifecycle, input, skin, particle, and audio commands.
- Render fullscreen GPU sprites with corner exit/restart controls and
  predecoded, pooled hit sounds.
- Persist results with navigable score, combo, and judgement breakdowns.
- Keep music playing through the results screen until the audio ends or you exit.
- Save per-engine note speed and count-up/count-down score display settings.

This is still a compatibility milestone, not a complete Sonolus implementation.

## Network behavior

Public catalog/detail responses and artwork use a shared disk cache (10-minute
freshness for all URLs). Only offline assets with verified content hashes are
reused indefinitely. The URLSession cache is bypassed so it cannot silently
extend the disk cache's freshness. Prefetching is limited to two pages ahead;
expired page sets restart from page one to avoid mixing catalog generations.
Identical in-flight requests are coalesced across client instances. The cache is
capped at 256 MB; verified offline downloads live separately and are not evicted
by it. Pull-to-refresh reloads the catalog and subsequent prefetched pages.
Browsing does not crawl the whole server: scrolling requests pages as needed, with a
manual retry/load-more fallback. Search waits 300 ms after typing stops.

Difficulty discovery searches for the selected song and pages only that result
set, with a safety limit if a server ignores search. Repeated downloads reuse
valid bundles and shared assets. Development regression tests use mocked servers
and local fixtures, not a full milkbun catalog crawl.

## Building

Open `OpenRhythm.xcodeproj` in Xcode, select an iPhone simulator, and run the
`OpenRhythm` scheme.

## Server configuration

The LLSIF server is built in. Add servers by URL using the Add button; use Edit
to remove servers or drag their reorder handles. Removing a server keeps its
offline songs. The list persists in `servers.json` in the app's Documents
directory, and can also be configured there:

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

Bounded compatibility checks on September 10, 2026 used one catalog page and one
chart per candidate server. Both Project SEKAI and SIF Custom Charts returned
version-13 engines. SIF Custom Charts' LLSIF engine ran its first ten seconds
(658 chart inputs, 34 resolved without touches); this is not a complete visual
or audio verification. Project SEKAI's `next-sekai` engine currently stops at
the unsupported `JumpLoop` instruction and is not yet playable.
