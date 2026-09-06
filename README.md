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

Gameplay and durable offline bundles are the next milestones.

## Building

Open `OpenRhythm.xcodeproj` in Xcode, select an iPhone simulator, and run the
`OpenRhythm` scheme.

