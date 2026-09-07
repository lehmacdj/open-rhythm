# OpenRhythm

OpenRhythm is a clean-room iOS client for the public Sonolus server and engine
specifications. The initial compatibility target is the Love Live! School idol
festival server at `https://sonolus.milkbun.org/llsif`.

The project intentionally contains no Sonolus application code, assets, keys,
branding, or reverse-engineered implementation details.

## Current milestone

- Load configured public servers.
- Fetch and decode level catalogs.
- Search every supplied localization, including transliterated forms.
- Group chart variants by song and switch difficulty.
- Sort and filter the loaded catalog with stock SwiftUI controls.
- Download complete chart bundles with verified, content-addressed resources.
- Browse downloaded charts together in a cross-server offline catalog.
- Decode Sonolus v13 compressed engine and level data.
- Play LLSIF tap, swing, and hold charts with synchronized audio and scoring.
- Persist results and show recent scores for each difficulty.

Full engine-driven rendering, input semantics, and effects remain in progress.

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
interpreter for the operations used by the LLSIF engine. The current playable
adapter renders LLSIF chart entities directly while engine-driven skins,
effects, particles, and arbitrary third-party engine presentation remain in
progress. No music, charts, artwork, or third-party application code is bundled
in this repository.
