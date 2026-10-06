# OpenRhythm capabilities and current status

As of October 6, 2026. Released baseline: version 0.1.0, TestFlight build 83.

OpenRhythm is a clean-room iOS rhythm-game client for public Sonolus servers
and version 13 play engines. It can browse songs, download them for offline
play, run engine-defined gameplay, and retain detailed results. It is an
operational compatibility milestone, not a complete Sonolus replacement or a
guarantee that every third-party engine works.

Build 83 is available to the existing internal TestFlight group.

## Browsing and managing songs

- Add servers by URL, remove them, and reorder them using drag handles.
  Removing a server does not delete its downloaded songs.
- Browse paginated catalogs with up to two pages prefetched ahead of scrolling.
  Appending pages preserves existing song order instead of moving visible rows.
- Search by title or artist with a 300 ms debounce. Offline search also indexes
  downloaded localized and transliterated names.
- Group chart variants by song and choose a difficulty. Sort preferences and
  the two-handle difficulty range are saved per engine; search text is not.
  Opening a filtered song selects its lowest matching difficulty.
- Browse a combined offline library, a chronological Play History, and a
  deduplicated Played Songs list. Played Songs retains the server/chart
  information needed to load a song again; it is not a substitute for a
  complete offline download.

## Downloads and network behavior

The Download action discovers and downloads all available difficulties for the
selected song, subject to the server's search results and discovery safeguards.
Downloaded songs can be updated or deleted, including swipe deletion. Shared
resources are reused, and failed updates preserve the previous valid download.
Deleting a download retains its play history.

Normal browsing does not crawl the entire server. Catalog responses, details,
and artwork use a shared disk cache with ten-minute freshness, coalesced
requests, and a 256 MB limit. Pull-to-refresh reloads the catalog. Verified
offline assets are stored separately and are not evicted by that cache.

Online play prepares a local copy of the music before starting. Offline play
uses downloaded assets. Both paths therefore use local audio for playback
timing and intro analysis rather than relying on streaming during a song.
The separately authorized, paced development crawl is not app behavior.

## Gameplay

Gameplay uses a full-screen playfield with the navigation bar hidden and a
corner exit/restart menu. The engine supplies the note layout, judgment rules,
score weights, combo multipliers, life rules, HUD placement, judgment/combo
animations, and Early/Late placement and threshold. Where the engine exposes
score modes, those choices are available instead of replacing them with one
app-wide scoring formula.

The runtime supports engine-driven taps, holds, releases, slides, and flicks;
sprite and curved drawing; hit particles; immediate, scheduled, and looped
sounds; and engine-requested haptics. Metal renders the playfield, with a
software fallback. Multitouch and timestamped input paths are implemented;
physical recognition, latency, and frame pacing still need the device checks
listed below.

Results wait for both music completion and input resolution. Chart lead-in is
preserved unless local silence analysis and engine simulation establish a safe
skip. Intro skipping stops for audio, effects, changing visuals, or visible
input-owned notes. Approved unchanged opening scenery can be skipped. If the
probe consumes an unseen input, it restores the original beginning. This is
not semantic recognition of every possible custom graphic.

## Settings and timing controls

Gameplay preferences are stored per engine. Available controls include:

- Note speed and engine-provided options, including sliders, toggles, choices,
  categories, and applicable playback-speed/score-mode settings.
- Score counting up or down, using a 1,000,000 maximum for the app's score
  display and engine scoring data where available.
- Judgment feedback with optional Early/Late labels, including PERFECT hits
  when the engine's threshold calls for them.
- Graphics preference where the engine leaves its skin render mode at default.
- Separate Input Timing and Visual Timing adjustments, each with a ±250 ms
  range, 1 ms increments, and reset. Input Timing adjusts judgment timing;
  Visual Timing changes chart alignment relative to the music. These are
  explicit player overrides, not automatically inferred corrections.
- Optional Record Playback Timing diagnostics. Reports stay local, are saved
  with results, and can be shared explicitly by the player.

Engine-defined options retain their declared defaults. There is no separate
default input-calibration field in Engine Configuration; the app supplies its
calibration before preprocessing and honors the engine's resulting offsets.
The engine audio-offset field's exact numerical units/speed convention still
needs independent confirmation.

## Results and history

New plays retain score, accuracy score, combo, judgment breakdown, life/failure,
recorded gameplay options, and per-note timing. The same detailed analysis is
available immediately after play and when opening a saved result:

- Timing scatterplot across the song, with red vertical lines for misses.
- Continuous Early/Late distribution with narrow, jagged peaks, centered zero,
  and the normal Swift Charts palette rather than copied ITG colors.
- A shared note-type filter, hit rate, early/exact/late counts, mean and median
  timing, mean absolute error, and timing spread.
- Engine result buckets with their own values, units, judgment windows, and
  saved graphics from the selected skin. Bucket values remain separate from
  timing errors measured in seconds.
- Playback diagnostics when recording was enabled for that play.

Known automatic intermediate hold ticks are excluded from the distribution,
not from scoring or the scatterplot. Their identification currently uses known
archetype names; arbitrary engines do not yet have a verified universal
automatic-hold classification.

History no longer automatically discards plays after 500 entries. Older results
show only what their original build recorded; missing timing data or previously
deleted history cannot be reconstructed.

## Engine runtime

Compatibility targets include Love Live! School idol festival, SIF Custom
Charts, Project SEKAI, and 22/7.

Shared runtime support includes lifecycle callbacks, documented play-memory
access rules, control flow, easing, BPM/time-scale conversion, spawning,
resource checks, streams, and exports. Unsupported engine functions are
reported before gameplay, including reachable successful-hit and spawnable
paths. Missing resources do not silently replace the engine with generic lanes.

## Remaining work and limits

1. **Stack API:** fourteen stack functions remain unimplemented. Their
   observable pointer, frame, and memory layout needs authoritative evidence.
   The authorized cached consumer search continues; upstream clarification
   has not been submitted.
2. **Physical validation:** audio/display alignment, close multitouch, dense
   flicks and holds, hit effects, intro behavior, calibration usability,
   interruptions, repeated starts, scrolling, and live frame-time tails remain
   in the deferred device batch.
3. **Audio contract uncertainty:** the public runtime audio-offset convention
   and exact stopped-clock transition precision remain unresolved.
4. **Intermittent startup failure:** simulator audio startup timeouts have been
   observed; their cause has not been established.

No other identified, reproduced defect is currently awaiting a fix. Exact
native-client rendering parity, unrestricted resource/codec support, and
arbitrary-engine compatibility are not promised. Tutorial, watch, and preview
modes, chart editing, and online score submission are outside the current
play-focused scope.

No songs, chart assets, or proprietary Sonolus application code are bundled.
The app includes an attributed, public MIT-licensed English protocol-label
table for offline settings display.

For implementation details and evidence, see [README.md](README.md), the
[request audit](REQUESTS.md), and the
[compatibility checklist](COMPATIBILITY.md#remaining-acceptance-checklist--september-30-2026).
