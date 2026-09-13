# Thread request audit — September 13, 2026

This ledger distinguishes implemented behavior from remaining compatibility
work and device verification. Passing simulator tests does not establish that
phone audio alignment, touch handling, or frame pacing is correct.

## Implemented and regression-covered

| Request | Implementation / evidence |
| --- | --- |
| Cache milkbun requests; respect pagination, avoid whole-catalog downloads | `SonolusClient`, disk freshness/coalescing tests; `CatalogModel` bounded two-page prefetch and cursor tests |
| Debounce title/artist search | 300 ms debounce, generation checks and cached search normalization; per-character input does not persist filters |
| Smooth append without re-sorting existing rows | Append preserves row IDs/order; explicit filter/sort changes re-sort the loaded selection |
| No extra empty cell/footer | Pagination row exists only for work, error, or a filtered-page fallback; zero-page/final-page tests |
| Persistent per-engine filters/sort, but not search | `CatalogFilter` Codable and `UserPreferences`; separate engine keys |
| Two-ended difficulty slider and estimated maximum | `CatalogFilterPanel` range slider, loaded maximum with headroom; lowest matching variant selected |
| All difficulties downloaded; label just Download | `completeSong`, all-difficulty discovery/download tests; shared verified assets reused |
| Update/delete offline songs and swipe deletion | `SongDetailView`, `OfflineCatalogView`, `OfflineStore`; history retained; shared assets preserved |
| Download updates keep a valid difficulty selected | Audit fix preserves the selected chart if retained, otherwise chooses lowest filter match or first available |
| Add server by URL, delete, drag reorder | `ServerStore`, persisted list and validation tests |
| Retain downloads when removing a server | Audit fix resolves re-added aliases by URL, deduplicates offline rows, updates newest copy, deletes all aliases; separate servers remain separate |
| Full-screen gameplay, unobtrusive exit/restart | Navigation bar hidden while playing, engine field expands; corner menu outside game input controls |
| Count-up/count-down display and note speed settings | Per-engine Gameplay Settings; engine arcade score is the source when available; both directions use a 1,000,000 maximum |
| Engine-standard score modes/weights and judgment windows | Runtime reads engine score configuration, note weights and combo multipliers; `Judge` uses supplied signed windows; SEKAI score-mode picker |
| Accuracy HUD and historical accuracy score | Final engine input errors, including misses, feed absolute-error scoring; count-up/down converge to the same result; legacy values are not invented |
| Hit grades and configurable Early/Late | Off/grade/timing setting; engine error threshold includes qualifying PERFECTs; engine position wins over earlier top-only preference |
| Engine-defined HUD and animations | Runtime positions, dimensions, pivot, alpha, rotation, life and supported metrics; judgment and combo animation tweens |
| Expose other engine-provided options | Generic sliders/toggles/choices, validation, named per-engine persistence; type-aware dedicated controls; standard overrides on results |
| Engine playback speed option | BGM rate, BPM imports/lookups, input metadata and event mapping change together; real-second judgment windows preserved |
| Keep playing until music ends | Results wait for audio EOF and resolved inputs; post-audio runtime tail handles trailing notes |
| Preserve lead-in; optionally skip safe silence | No seeking straight to first note/beat zero. Local PCM silence scan advances retained runtime conservatively until input activation, engine sound, or audio onset |
| Complete historical results and chronological plays | `ResultStore`, `ResultDetailView`, global play list, deduplicated played songs retaining replay server/level metadata |
| Timing scatter, miss lines, distribution, note-type filters and statistics | Shared result statistics sections for new/past plays; both plots filtered together |
| Remove automatic hold ticks from histogram and fix zero alignment | Continuous density curves (no histogram bins), known intermediate ticks excluded only from distribution; exact-zero, outlier and bounded-work tests |
| Fill named host-function gaps, including PlayLooped | Draw/Judge/audio scheduling and loops/particles/BPM/Spawn/exports/resource checks implemented; preflight includes lazy and spawnable branches |
| Anticipate compatibility beyond known engines | Fractional protocol fields, optional tags/buckets, cursor modes, curved drawing, lifecycle/memory/easing contract tests and `COMPATIBILITY.md` |
| Independent review after fixes | Independent read-only reviews found the update-selection, alias crash/stale-read, first-page Retry and option-control-routing issues; fixes have regressions |

## Reported search crash: now verified against Apple's log

Apple's report is for `is.devin.OpenRhythm`, version 0.1.0 build 1, on September
10. The signature is `CatalogModel.prefetchNextPages() + 1564`, with a Swift
`Range requires lowerBound <= upperBound` trap. An empty search can have zero
reported pages despite one completed request; the old range was invalid.

The current prefetch guards stop when there are no more pages, including a
shrinking page count. Existing focused tests and the new 30-query repeated
empty/shrinking-search regression pass. The first analytics query mistakenly
used the old bundle ID; the current project ID was verified before retrieving
the actual report. No claim is made about other unreported crash signatures.

Historical detail means the complete payload retained for that play, not
reconstruction of data older builds never recorded. `ResultStore` currently
retains the most recent 500 plays; older summary-only records remain without
per-note timing charts.

## Playback and engine coverage: improvements made, not fully signed off

- **LLSIF:** cached 365-input chart completes; host rendering, score/life and
  presentation regressions exist. Phone hit-effect appearance still needs
  verification on a build containing the renderer fixes.
- **Project SEKAI:** Eleventh Hard 16 full MORE MORE JUMP (419 inputs), and 光
  Hard 18 full 25ji/MEIKO (563 inputs) were the specific follow-up fixtures.
  Looped audio, flick velocity after stationary holds, identity-based multitouch,
  startup clocks and Hikari hold paths were exercised. Cached Hikari repeated
  startup and speed probes were monotonic. The original nondeterministic loop
  and excess Earlies are not declared fixed solely from those probes.
- **22/7:** シャンプーの匂いがした Pro 4.9 (949 inputs) completes no-touch
  lifecycle simulation. Additional native playback judged a slide head, slide
  release and simultaneous tap PERFECT; hit-effect frames were inspected.
  This does not certify every flick/hold variant or a whole physical play.
- **SIF Custom Charts:** its 658-input LLSIF-family chart had a bounded first
  ten seconds exercised. Full native visual/audio/input coverage is still less
  extensive than the three fixtures above.
- **Timing:** touch uptime is mapped through AVPlayer's timebase and rate
  transition history instead of frame/delivery time. No guessed calibration
  offset was added. Simulator event-clock agreement is not output-latency or
  display-latency measurement.
- **Performance:** interpreter, sprite generation, pooled/predecoded audio,
  GPU rendering and bounded software work have been profiled/improved. Phone
  frame-time tails under dense successful hits remain unverified. Apple has
  energy reports for 0.1.0 builds 4–8; build selection was requested. TestFlight
  hang reports are not offered by that Apple API.

## Still unfinished

1. Physical-device verification of close/coincident multitouch, dense flicks
   and holds, hit effects, audible sync, repeated starts, interruptions and
   gameplay frame pacing. These require the relevant device/build or field
   diagnostics; they cannot be certified by invented simulator measurements.
2. General engine compatibility is not complete: stack-function ABI, all skin
   render modes, error-heatmap HUD metrics, alternate timing-indicator
   styles, and resource/callback conformance still need work. Unsupported
   functions are surfaced before music rather than assumed harmless. See the
   separate contract checklist; sampled engines do not prove arbitrary support.
3. Safe intro skipping currently analyzes local audio only. Streamed intros
   remain intact when silence is unknown; `bgmOffset` alone is not evidence
   of silence. First-input activation can be earlier than first visible pixels.
4. More complete SIF Custom Charts and real-device engine integration runs.

## Deliberately not added / superseded requests

- Extra app-owned sound/animation packs and hide-combo switches remain deferred,
  as requested. Engine-defined options and engine-owned animations are separate.
- Early/Late top-only placement was superseded by following engine placement.
- Continuing audio on the results screen was superseded by staying in gameplay
  until music finishes.
- Tutorial/watch/preview execution and online score submission were not requested
  as app features; play-mode support does not imply these separate modes.
- Gameplay options persist per engine by product policy, rather than Sonolus's
  optional cross-engine `scope` / level-local sharing. No hidden cross-engine
  preference migration is performed.

All commits remain local unless the user explicitly asks to push. No third-party
chart/audio/skin resources or diagnostic logs are committed.
