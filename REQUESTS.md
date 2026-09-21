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
| Engine-selected error-heatmap HUD | Continuous signed-error density and mean in the engine's metric slots; centered zero, judgment colors, no automatic hold ticks, bounded streaming work |
| Hit grades and configurable Early/Late | Off/grade/timing setting; engine error threshold includes qualifying PERFECTs; all 13 engine timing styles supported; engine position wins over earlier top-only preference |
| Engine-defined HUD and animations | Runtime positions, dimensions, pivot, alpha, rotation, life and supported metrics; judgment and combo animation tweens |
| Expose other engine-provided options | Generic sliders/toggles/choices, validation, named per-engine persistence; type-aware dedicated controls; standard overrides on results |
| Engine playback speed option | BGM rate, BPM imports/lookups, input metadata and event mapping change together; real-second judgment windows preserved |
| Keep playing until music ends | Results wait for audio EOF and resolved inputs; post-audio runtime tail handles trailing notes |
| Preserve lead-in; optionally skip safe silence | No seeking straight to first note/beat zero. Selected online BGM is cached and pinned before Ready, so online/offline playback use the same local PCM analysis. Runtime advances conservatively until input activation, engine sound, or audio onset |
| Complete historical results and chronological plays | `ResultStore`, `ResultDetailView`, global play list, deduplicated played songs retaining replay server/level metadata |
| Timing scatter, miss lines, distribution, note-type filters and statistics | Shared result statistics sections for new/past plays; both plots filtered together |
| Remove automatic hold ticks from histogram and fix zero alignment | Continuous density curves (no histogram bins), known intermediate ticks excluded only from distribution; exact-zero, outlier and bounded-work tests |
| Fill named host-function gaps, including PlayLooped | Draw/Judge/audio scheduling and loops/particles/BPM/Spawn/exports/resource checks implemented; preflight includes lazy and spawnable branches |
| Anticipate compatibility beyond known engines | Fractional protocol fields, exact branch-label matching, optional tags/buckets, cursor modes, curved drawing, same-frame termination state visibility, lifecycle/memory/easing contract tests and `COMPATIBILITY.md` |
| Unused presentation resources | Skin-only, particle-only, and no-effect engines do not require unused placeholder textures or audio; required resources still fail explicitly |
| Engine-selected skin rendering | Explicit Standard/Lightweight modes win; default defers to the per-engine Graphics preference. Curved and ordinary sprites share mode-aware GPU/software meshes |
| Engine-selected background and runtime placement | Online/offline resource selection, fit/aspect/scale, color/mask/blur, and perspective RuntimeBackground coordinates supported; bounded image preparation and transparent note layers |
| Engine-requested haptic feedback | Final EntityInput values dispatch None/Light/Medium/Heavy/Long through prebuilt haptics-only players; unsupported hardware is safe; interrupted sessions recover with bounded retries |
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
  ten seconds exercised originally. The follow-up cached UNSTOPPABLE rating 11
  run now resolves all 658 inputs at 97.55 s. Two native 1× starts judged the
  opening hold, release, simultaneous release/tap and paired taps PERFECT,
  with no backward clock jumps; pre-hit and hit-effect frames were inspected.
  A complete native 2× run remained in gameplay at the last input (48.85 s),
  finished at audio EOF (51.192 s), and retained all 658 timings with matching
  live/saved accuracy scores. These are simulator checks, not phone sign-off.
- **Timing:** touch uptime is mapped through AVPlayer's timebase and rate
  transition history instead of frame/delivery time. No guessed calibration
  offset was added. Simulator event-clock agreement is not output-latency or
  display-latency measurement.
- **Lifecycle follow-up:** after fixing same-frame termination state visibility,
  full cached Eleventh, 光, SIF Custom Charts and 22/7 no-touch runs resolved
  419, 563, 658 and 949 inputs respectively, with no duplicate resolutions.
  Generic linked-peer regressions verify the contract even without a real chart
  triggering the original bug. Successful physical inputs remain a separate check.
  Restart now restores prepared state without rerunning preprocessing or
  rerolling random layouts. Synthetic state/cache regressions and paired cached
  SEKAI/22/7 restart probes pass; the original audible loop report remains a
  separate physical-device check.
  A follow-up fix clears held/queued touches across restart in both engine and
  fallback playfields. A regression first reproduced the stale chart timestamps
  and now passes; this is not confirmation of the reported phone loop's cause.
- **Performance:** interpreter, sprite generation, pooled/predecoded audio,
  GPU rendering and bounded software work have been profiled/improved. Literal
  address caching reduced mean runtime-update time in paired Debug simulator
  probes by about 29% for Eleventh and 25% for 22/7; all 1,800 frames matched in
  judgments, draws and audio commands. This is not a Release benchmark. Phone
  frame-time tails under dense successful hits remain unverified. Apple has
  energy reports for 0.1.0 builds 4–8; build selection was requested. TestFlight
  hang reports are not offered by that Apple API.
  The spawn queue now advances without repeatedly shifting every future entity;
  blocked-head, exhaustion, restart and large-queue regressions cover the change.

### Device verification attempt — September 20

The user authorized installing the development build on thyme5 without deleting
app data. Apple's device query reports OpenRhythm 0.1.0 build 13, but that is
not proof that the current development build installed: the local artifact is
build 1, and the user reports build 13 is their working TestFlight version.
The earlier conclusion based on `builtByDeveloper` was incorrect. Xcode built
successfully but did not complete launch;
the direct device launcher reports that SpringBoard denied launch because the
device was locked, even though `passcodeRequired` reported false. The user was
asked to open the app from an unlocked Home Screen. After the user's correction,
an explicit `devicectl device install app` succeeded, and a fresh device query
confirmed build 1 at the new installation path. No uninstall/data deletion was
performed. The subsequent direct launch still failed with SpringBoard's Locked
error (CoreDevice 10002 / FBSOpenApplicationErrorDomain 7). Installation is now
verified; launch and gameplay are not. Xcode's interaction
session tool listed only simulators, so physical UI automation is also not yet
available. This attempt does not count as physical gameplay verification.

## Still unfinished

1. Physical-device verification of close/coincident multitouch, dense flicks
   and holds, hit effects, audible sync, repeated starts, interruptions and
   gameplay frame pacing. These require the relevant device/build or field
   diagnostics; they cannot be certified by invented simulator measurements.
2. General engine compatibility is not complete: stack-function ABI and
   resource/callback conformance still need work. Skin mode selection is now
   honored, but exact native rendering parity is not claimed. Unsupported
   functions are surfaced before music rather than assumed harmless. See the
   separate contract checklist; sampled engines do not prove arbitrary support.
3. Safe intro skipping stops at first-input activation, which can be earlier
   than first visible pixels. Visible non-input intro animations and count-ins
   still need broader checks. Unknown silence is never inferred from bgmOffset.
4. Real-device engine integration runs beyond the cached simulator fixtures.

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
