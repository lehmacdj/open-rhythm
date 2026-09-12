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
- Run LLSIF and Project SEKAI engine lifecycle, input, skin, particle, and audio commands.
- Render fullscreen GPU sprites with corner exit/restart controls and
  predecoded, pooled hit sounds.
- Persist results with navigable score, combo, and judgement breakdowns.
- Wait for the music to end before showing results; preserve chart/audio lead-in.
- Save per-engine note speed and count-up/count-down score display settings.
- Use engine-defined score weights, life rules, HUD layout, judgment animation,
  and Early/Late position and threshold. Store life/failure with new results.

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

The app parses version 13 engine resources. Shared runtime support includes
direct/shifted/pointed memory operations, overlapping copies, bounded control
flow, all 36 named easing functions, drawing, judging, scheduled/looped audio,
particles, BPM/time-scale conversion, dynamic spawning, resource availability,
streams, and exports. Metal renders engine sprite geometry with a software
fallback. Engine score and life configuration is consumed after preprocessing.
The simpler chart adapter remains for bundles without presentation resources.
No music, charts, artwork, or third-party application code is bundled here.

Before play, a callback-graph scan reports unsupported functions, including
those in lazy successful-hit branches and dynamically spawnable archetypes.
This is a capability check, not proof of semantic conformance or playability.

General third-party engine compatibility is **not yet guaranteed**. Known gaps
include stack functions, curved drawing, full skin render-mode
semantics, accuracy/error-heatmap HUD metrics, combo animations, timing-indicator
styles beyond Early/Late text, and generic engine-option controls. The native
exit/restart menu remains app-positioned. Unknown metric names display a dash,
not a substituted score. Engines can also contain editor-only entities with no
matching play archetype; these remain non-executing metadata. Resource
optionality, callback access restrictions, and non-play modes need further
conformance work. Paint and Print belong to tutorial and preview modes, not
play-mode runtime gaps. Do not infer arbitrary-engine support from sampled
engine families. See [the conformance checklist](COMPATIBILITY.md).

Bounded compatibility checks on September 10, 2026 used one catalog page and one
chart per candidate server. Both Project SEKAI and SIF Custom Charts returned
version-13 engines. SIF Custom Charts' LLSIF engine ran its first ten seconds
(658 chart inputs, 34 resolved without touches); this is not a complete visual
or audio verification. Project SEKAI's cached `next-sekai` chart now completes
a 240-second no-touch simulation (1,210 inputs resolved, sampled at 10 Hz),
with 70 inputs resolved in a separate first-ten-seconds run at 60 Hz. It uses
the engine's compressed Float32 ROM, bounded streams, BPM lookup, easing, and
moving particles. Later cached checks covered looped audio and successful hold
input separately; none of these simulations establish physical-device touch
latency or audio alignment.

The September 11 conformance pass uses synthetic operation/configuration tests
and cached assets, with no catalog crawl. Both LLSIF (365 inputs) and SEKAI
Hikari Hard 18 (563 inputs) resolve every input in 300-second no-touch runs.
Engine HUD and top/bottom timing-label layouts have Xcode preview coverage.
Independent review caught easing, pointer evaluation-order, and malformed HUD
number defects; regression tests cover the fixes.

The September 12 contract pass adds fractional ratings and callback ordering,
optional tag titles/bucket units, Execute0, quick search, and opaque-cursor
pagination. A single cached 22/7 catalog page exposed Pro 4.9 ratings; its
シャンプーの匂いがした Pro chart resolves 949/949 inputs without touches.
This is decoding/lifecycle coverage, not a claim of verified device playability.

Timing distributions now use continuous density curves with no data bins.
Known automatic hold checkpoints are excluded only from the distribution,
not from scores or the scatterplot. Regression cases cover zero alignment,
judgment-colored mass, narrow isolated modes, and bounded rendering work.

Native and fallback inputs map UIKit event timestamps through the audio
timebase, retaining rate-transition history for queued touches across stalls.
No calibration offset was added. Local songs can skip verified leading silence,
stopping conservatively at the first engine input activation or engine sound.
The exact advanced runtime is retained and audio seeks to the corresponding
media time; streamed intros remain untrimmed when silence cannot be verified.
Cached Hikari starts at chart -2 seconds instead of -9, with first hold inputs
judged Perfect on two runs; physical-device audio/touch alignment is unverified.

Interpreter control flow follows the public [Sonolus function specifications](
https://wiki.sonolus.com/engine-specs/functions/jump-loop), with lazy branches
and per-callback operation limits. Regression fixtures for these operations are
synthetic; the downloaded compatibility chart remains outside version control.
