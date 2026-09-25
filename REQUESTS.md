# Thread request audit — September 13, 2026

This ledger distinguishes implemented behavior from remaining compatibility
work and device verification. Passing simulator tests does not establish that
phone audio alignment, touch handling, or frame pacing is correct.

## Current verification order — September 25, 2026

Per the user's latest direction, postpone real-device testing until Sonolus
API coverage is complete, then perform the outstanding physical checks in one
large batch. Do not request phone unlocks, install or launch development builds
on physical devices, or run incremental device checks before that gate unless
the user explicitly asks for a specific device issue to be investigated sooner.
The previous pending unlock request is superseded; a connected or unlocked
phone alone does not reopen device testing.

Prioritize the API contract checklist, implementation gaps and synthetic
conformance tests, using simulator tests and builds while that work proceeds.
The gate is closure of the API contract gaps tracked in COMPATIBILITY.md, not
merely passing the sampled engines or the current test suite. Collect remaining
physical checks into the batch as implementation proceeds.
Keep the physical checks below open and label them deferred, not passed or
blocked on an immediate phone unlock. Existing device evidence remains useful
but does not substitute for the eventual batch. The stable-build push
authorization is unchanged; deferred physical validation must be disclosed,
and no unmeasured latency improvement should be claimed.

Intro follow-up: input activation alone no longer ends silent-intro simulation.
An offscreen active note can advance to its first visible frame, while music,
engine sounds, debug output and visual effects retain their existing stopping
conditions. If an input resolves before playback starts, discard the skip and
restore the original beginning instead of consuming an invisible note. Life
changes also restore the beginning, preserving scheduled life events; the time
HUD intentionally follows the skipped timeline. Eleven focused model/visual
guard tests pass, including BGM-first, hidden-input rollback, held graphics,
visual-only spawn rollback, and initial judgment plus DebugPause. Independent
review caught the restored debug-pause ordering issue; it is fixed and final
review found no further issue. The September 25 04:50 full simulator run passed
269 tests; the subsequently added life test had no result in that run. All 11
focused checks passed on the final code at 04:56, and the 04:57 normal simulator
build passed. Conservative initial-stage classification remains open below.

Resource-loading follow-up: server playback now requires engine configuration
and defaults explicitly to engine execution. Missing presentation cannot
silently select the internal basic lane player. Explicit overrides require
their family-specific files; declared ROM and all runtime locators must resolve
to HTTP(S), while absent ROM remains valid. Unsupported-function preflight now
also runs on offline playback, including the downloaded route through the main
loader. Downloads may archive unsupported engines; playback rejects them.
Independent review found no actionable issue. The September 25 03:28 simulator
suite passed all 254 tests, including six cached-chart probes, with no failures
or skips. The 03:33 normal simulator build passes. No device testing was used;
the broader API-coverage gate remains open.

Presentation-value follow-up: unknown UI metrics, judgment-error styles and
placements, and UI/selected-particle easing names now fail during preparation
with a field/value diagnostic instead of silently changing presentation. The
documented enum lists and all 38 easing names are accepted; unused particle
families/effects remain ignored. Independent review found no implementation
issue and suggested an additional unused-effect regression, which was added.
Omitted particle easing still uses the existing linear behavior. The public
Studio importer independently confirms linear easing and zero expression
defaults; proprietary native parity is not certified by these tests.
The September 25 04:02 simulator suite passed all 260 tests with no failures
or skips; the 04:08 normal simulator build passes. Physical checks remain
deferred under the API-coverage gate.

Particle interval follow-up: looped subparticles now continue across the
effect's cycle boundary instead of disappearing early, and their exact end
point remains visible while the parent effect is alive. Three focused
simulator tests pass, including animated geometry/alpha and all cache modes.
Independent review verified the official public Studio reference and found no
interval defect. This is editor-renderer conformance, not native first-spawn
or lifetime proof. Further easing discrepancies are recorded in
COMPATIBILITY.md. The September 25 04:16 simulator suite passed all 261 tests,
with no failures or skips; the 04:22 normal build passed. Physical checks
remain deferred.

Particle easing follow-up: `none` now reaches the final value at its exact
endpoint instead of holding the starting value forever. A failing-before-fix
regression now passes, including rendered positions across loop boundaries.
Four focused simulator checks and the 04:25 normal build pass; independent
review found no defect. Numerical engine easing is unchanged; remaining curve
differences are addressed by the particle-specific follow-up below.

Particle curve follow-up: particle properties now use the public Studio
Back/Elastic composition and Expo/Elastic midpoint behavior without changing
numerical engine easing or HUD animations. The regression failed before the
initial correction; independent review identified an additional Elastic
midpoint case, which is also corrected and covered. Native presentation parity
still needs the later physical batch; this does not close general API coverage.
Independent re-review found no remaining curve mismatch. The 04:37 full
simulator run passed 264 tests; it built before the final review correction.
Seven focused regressions then passed on the final code at 04:42, along with
the normal simulator build. The verification sequence is in COMPATIBILITY.md.

Particle geometry follow-up: removed an extra width/height halving that made
effects smaller than the official public Studio reference. A synthetic corner
regression failed before the fix and now passes, including rotation,
reflection, animation and parent aspect scaling. Four focused simulator tests
pass; independent review found no issue. The reported phone hit effects and
the performance impact of the corrected larger area still belong to the
deferred physical batch, not a claimed device fix.
The September 25 04:27 simulator suite passed all 263 tests with no failures
or skips; the 04:33 normal simulator build passed.

Option-category follow-up: engine-provided section titles/order now organize
settings without changing Level Option memory indices. Dedicated note-speed
and score-mode preferences remain compatible, and resetting either also clears
legacy generic overrides. Older uncategorized configurations retain their
layout but now resolve those overrides consistently with playback. Invalid
category references fail rather than silently hiding controls. Five focused
tests and the categorized iPhone preview passed inspection; independent review
found the legacy override inconsistency, which was fixed and re-reviewed.
The September 25 03:51 simulator suite passed all 257 tests with no failures or
skips; the 03:56 normal simulator build passes. Physical testing stays deferred.

Initial-memory follow-up: an engine-independent regression checks complete
defined play-memory blocks, samples their defaults from inside preprocessing,
and verifies restoration after mutation/restart for two entities. Independent
review corrected one test assumption: Temporary Memory's initial contents are
unpredictable by contract and must not be asserted as zero. No production
default required changing. The September 25 03:40 simulator run passed all
255 tests with no failures or skips, and the 03:45 normal build passes. This
does not close stack-layout, resource-configuration, or physical validation
gaps; see COMPATIBILITY.md for the exact scope and evidence.

Memory API checkpoint: callback permissions, declared block bounds and Get's
zero-read fallback are implemented and independently reviewed. The September
25 02:39 simulator run passed 240 tests (including six cached-chart probes);
one stale invalid-Get assertion was corrected, then passed in the five-test
02:46 rerun. All 241 registered tests are covered across those runs. The normal
simulator build passes. This does not close the broader API gate; the remaining
gaps are listed below and in COMPATIBILITY.md.

Debug-function follow-up: `DebugLog` and `DebugPause` now have host and app
support behind a persistent per-engine Engine Debug Mode setting (off by
default). Logs appear at the bottom right and in a resumable pause panel.
Startup does not skip debug output; pause freezes chart/input time and active
effect samples, keeps future audio commands, and discards stale contacts
without reusing touch IDs within the same runtime. Debug plays are marked in
result options. The September 25 03:02 simulator suite passed all 248 tests,
with no failures or skips, including the six cached-chart probes. An expanded
preprocessing-override test passed separately at 03:07; the final normal
simulator build passes. The debug pause panel was rendered and inspected.
Independent review found a scheduled sound that could start between frames
and then incorrectly restart on resume. That case is fixed and regression
tested; final review found no further actionable issue. Physical checks stay
deferred under the API-coverage gate above.

Callback follow-up: AddLifeScheduled's preprocessing-only contract is enforced
through all eight real runtime callback contexts. Its queue now sorts once and
advances a cursor instead of repeatedly sorting/scanning. Equal-time ordering,
restart and partial-snapshot regressions pass; independent review found no
actionable issue. The September 25 03:12 simulator suite passed all 250 tests
(no failures or skips), including the six cached-chart checks; the final normal
build passes. The resource audit
also found a silent basic-lane fallback when the whole presentation bundle is
missing; removing that engine bypass is the next concrete resource gap.

## Live-play follow-up — September 25, 2026

Status of the live-play follow-ups; offline probes do not certify live sync:

- Investigate the reported audio/animation timing difference thoroughly across
  engines. Trace audio presentation, chart/render timestamps, display delivery
  and touch timestamps, including startup, speed changes and interruptions.
  Distinguish clock bugs from output/display latency; do not guess a default
  correction from the reported excess Earlies. Prioritize this alongside live
  frame-pacing checks, not only particle or curved-hold CPU benchmarks.
  Initial September 25 source trace: `engineFrame` samples the AVPlayer-derived chart
  clock before runtime work; sprite generation/Metal encoding follows, and
  presentation is queued as soon as possible. The display-link target and
  drawable's actual presentation timestamp were not recorded at that point.
  This left a measurable render-age gap, not a proven cause or correction value.
  Measure sample-to-present age and audio-route/output latency together before
  changing display prediction or applying audio compensation. Touch timestamps
  already use the player's timebase rather than delayed event delivery time.
  Opt-in per-engine Record Playback Timing now records engine/sprite/encoding
  work, drawable wait/GPU execution, chart sample-to-presentation age, display
  deadline difference, clock-read duration, event/player clock difference and
  OS-touch delivery age. It saves a bounded whole-play summary with results,
  including output port type and iOS-reported output latency/buffer duration;
  result details expose the report and a user-operated share action. Disabled
  by default, local only, no automatic offset changes. Recording starts after
  intro preparation; actual presentation timestamps require a device, because
  the simulator SDK omits that API. Startup correlation, acoustic alignment,
  live device measurements and calibration remain open. Independent review
  corrected per-contact delivery-age inflation and diagnostics overhead being
  attributed to Metal encoding; output port-type changes are labeled precisely.
  The 221-test regression run passed; a newly added native-window callback
  probe passed separately on simulator and thyme5. The device delivered actual
  drawable timestamps; simulator reports them unavailable. This validates the
  instrumentation path only: the probe has no music or engine workload and
  does not supply a gameplay correction. Final device build passes.
  A generated-local-audio regression now exercises GameplayModel's real
  AVPlayer/timebase path at 0.5×, 1×, 2× and 1× after restart. It verifies the
  selected speed independently, real-time chart advancement and delayed reads
  of historical event timestamps. The strengthened test passes in simulator
  and on thyme5. A companion test runs the actual playfield, display link and
  Metal alongside the generated audio; it also passes on both destinations.
  These probes revealed a roughly one-refresh presentation delay beyond the
  display-link target even with an empty engine, while effective input/player
  clocks agreed. Raw timebase extrapolation during scheduled audio startup is
  now labeled separately from the seek-clamped input clock. This is a concrete
  rendering investigation lead, not an acoustic correction or dense-chart
  performance sign-off; no gameplay timing offset was changed.
  The next rendering change uses `CAMetalDisplayLink` with one-frame preferred
  latency and the update's supplied drawable/presentation target. It does not
  predict or shift chart/input time. The initial live-window simulator probe
  passes. All 227 tests in the full simulator run passed; the added live
  software-fallback test and six focused regressions passed afterward.
  Detach/reattach is covered, the device build passes, and independent review
  found no further issue after centralizing both software-fallback paths.
  Physical before/after latency comparison is deferred to the post-API batch.
  This scheduling change is simulator-verified, not claimed to improve device
  sync; its physical comparison remains deferred under the current policy.
- Add persistent manual timing overrides in Gameplay Settings so the player
  can compensate for observed bias. Define adjustment direction and units
  clearly, provide a neutral default/reset, and distinguish visual alignment
  from input judgment adjustment. Preserve engine judgment windows and test
  persistence, restart and playback-speed behavior. This is newly requested
  configuration, not evidence that the underlying synchronization is correct.
  Input calibration is now implemented: per-engine ±250 ms, 1 ms slider/stepper,
  reset to zero, and the selected adjustment is retained in result details.
  Positive subtracts from input timestamps to compensate late inputs; negative
  compensates early inputs. Music and frame clocks stay unchanged. The value
  is supplied before engine preprocessing, and the engine's resulting offset
  is honored for touch times. Engine-defined options retain their own defaults;
  there is no separate default-input-offset field in Engine Configuration.
  Visual Timing is now implemented alongside Input Timing: a separate per-engine
  ±250 ms slider/stepper/reset, default zero, snapshotted for the next play.
  Positive delays chart/input relative to music; negative advances them.
  The adjustment uses wall-clock seconds at every playback speed, does not
  seek past supplied audio, and appears in saved result options. The runtime
  receives it as audio offset before preprocessing and honors the engine's
  resulting value before intro analysis and seeking. Scheduled effects and
  loop starts/stops compensate once to stay on the BGM timeline; immediate
  hit sounds remain immediate. All 232 tests in the full simulator run passed;
  the added fallback-composition test and three focused regressions passed
  afterward. A model-level engine-preprocess override covers initial timing,
  preserved media-zero seek, live input mapping and restarts. The normal build
  and final independent read-only review passed. Physical synchronization and
  calibration usability are deferred to the post-API device batch. Independent
  review found no arithmetic inconsistency, but the public scheduled-audio
  docs do not independently specify offset sign/units; that parity check
  remains an explicit API-contract uncertainty, not a demonstrated correction.
  Independent review found no calibration correctness issue. All 212 tests
  passed across the full run and a rerun of shake-it's no-touch test after a
  simulator shutdown; this was not an uninterrupted suite. The normal build
  passed without warnings. The settings preview initially timed out; a later
  iPhone 17 Pro/iOS 27 render now verifies the offset, slider, stepper, explanatory
  text and reset control without truncation. Physical interaction remains open.
- Redesign the results timing distribution using the supplied ITG evaluation
  photo as the visual reference for jagged peaks, not its colors. Use Swift
  Charts' default palette and normal light/dark appearance, a clear centered
  zero and Early/Late labels. Retain shared note-type
  filtering and exclusion of automatic intermediate hold ticks. Prefer a
  continuous representation where practical; verify sparse, dense, zero-only
  and outlier cases plus light/dark appearance. The photo is a design reference,
  not a source for this app's judgment windows or score rules.
  Implemented with narrow continuous kernels (1 ms, widened only for very broad
  ranges to bound drawing work). The sampled polygon is normalized per judgment
  so its area retains all note contributions without filling support gaps.
  Twenty-one result/statistics tests pass, including direct kernel-shape, gap,
  mass, nearby-peak, outlier, hold-exclusion and bounded-work regressions.
  Native previews verify dense, exact-zero, empty and outlier states in both
  appearances; an accessibility-size preview prompted scaling chart height so
  enlarged labels do not consume the plot. Independent review found no
  correctness issue; its additional explicit support-gap regression was added.

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
| Preserve lead-in; optionally skip safe silence | No seeking straight to first note/beat zero. Online/offline playback use the same pinned local PCM analysis. Advance until engine sound, audio onset or a visual boundary, including offscreen active inputs; restore the original beginning if simulation consumes an input |
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
  version entries for 0.1.0 builds 4–8. A follow-up query of the sole listed
  version failed to download processor-usage logs and suggested connecting the
  app in Xcode Organizer; available entries do not prove usable report data.
  TestFlight hang reports are not offered by that Apple API.
  The spawn queue now advances without repeatedly shifting every future entity;
  blocked-head, exhaustion, restart and large-queue regressions cover the change.
  Particle random expressions are now cached with bounded frame retention;
  paired synthetic sprite-generation probes improved about 17% at 256 sprites
  and 8% at 2,048 sprites with identical outputs. Neither establishes phone
  performance under real successful hits.
  Active sequential/touch callback lists now retain their ordering across
  stable frames instead of sorting all entities every frame. A 512-entity
  synthetic simulator workload improved from 1.066 to 0.506 ms/frame, with
  explicit lifecycle/order regressions and independent review. Full cached
  Hikari input resolution and restart comparison passed; its 21.068 ms p95
  runtime-plus-sprite CPU time still leaves gameplay performance work open.
  The final simulator suite passed all 206 tests, including all four cached
  chart lifecycle/restart fixtures, with zero failures or skips.

### Curved-hold performance follow-up — September 21

The reported **shake it! Hard 18, full MORE MORE JUMP / Kagamine Rin** is now
a cached regression fixture (`sekai-best-550-2070-hard`, 544 inputs). Its
currently supplied next-sekai-2.9.0 engine emits curved connectors as ordinary
`Draw` quads, not `DrawCurved`; optimizing only `DrawCurved` would miss this
workload. The user's affected build is unknown, so matching the chart does not
establish that it is the same engine revision they played.

The full lifecycle harness now separates runtime and sprite CPU measurements,
records p95/p99, and replays peak runtime/draw/particle/curve frames through
Metal to measure encoding and GPU work. It still covers Eleventh, 光, SIF
Custom Charts and 22/7. A second full shake-it run supplies eight deterministic
periodic contacts, exercising successful hold heads/ticks/releases and hit
effects, with exactly-once resolution and restart checks. These are synthetic
contacts, not a captured curved-hold gesture or physical frame-pacing proof.

The original contact run resolved 544 inputs, including 489 successes, and
peaked at 55 simultaneous effects. Debug simulator CPU means were 8.640 ms for
runtime and 2.738 ms for sprites (combined p95 20.242 ms). Particle rendering
now reads its frame-wide matrix once, reuses rotation trig values per particle,
and avoids reparsing colors when tinted images are already cached. An attempted
dense VM-memory optimization was rejected: it failed to improve this workload
and independent review found a sparse-layout memory-cost risk.

The final simulator suite passed **208 tests, zero failures/skips**, including
all five cached charts and the extra contact run. The final contact run again
had 489 successes, including 25 normal hold heads, 17 normal ticks and 23
normal releases. Mean sprite CPU decreased from 2.738 to 2.419 ms (~12%);
combined runtime/sprite p95 was 19.140 ms and p99 24.874 ms. This before/after
Debug simulator comparison is not a Release or device frame-rate guarantee.
The peak-effects frame had 304 sprites / 3,522 vertices, with offscreen Metal
encoding averaging 0.907 ms and GPU execution 0.047 ms on the simulator host.
Independent review found no remaining actionable issue in the retained diff.
The reported phone slowdown remains open, not declared resolved by these tests.

Only a bounded search and the exact chart data were fetched; shared engine,
ROM and presentation assets were reused. No catalog crawl or music download
was needed. Assets remain in ignored local caches. Physical verification is
still open: thyme5 reported `passcodeRequired: true` during this follow-up.

### Resumed device check and push — September 21, afternoon

`main` was pushed to the verified configured `origin` at `75a0d485` after the
208-test simulator suite and another successful Xcode build. The phone then
became available. The first new full shake-it contact test was killed for CPU
resource use (48 CPU-seconds over 49 seconds), not a memory-access exception.
The tight offline loop was running continuously rather than at display cadence.

The test harness now yields between bounded work bursts on physical devices,
outside all per-frame timing samples. No production timing or runtime behavior
was changed. Independent review found no correctness issue. The rerun passed
on thyme5: 544 inputs resolved, 489 successful judgments, hold heads/ticks/
releases and 121 restart snapshots verified. It also replayed peak frames
through the phone's offscreen Metal renderer. Xcode completed successfully after
the tool's five-minute response timeout; the completed result bundle confirms
the device ID and zero failures. A simulator SIF lifecycle/restart test also
passed after the async harness change.

The throttled Debug phone run measured runtime mean/p95 17.955/36.792 ms and
sprite mean/p95 4.370/8.653 ms. The peak-effects frame (55 effects, 304 sprites)
encoded in 1.446 ms and executed on the GPU in 0.854 ms on average. Pauses alter
thermal conditions, and Debug timings are not Release timings: these numbers
identify further interpreter and particle work, not live FPS or proof of a
stable physical play. Release profiling, real touches, audio/display latency,
and the original curved-hold slowdown remain open.

### Optimized-build profiling and particle endpoints — September 21

Five cached chart checks passed on thyme5 with Release `-O`/whole-module
optimization. Coverage instrumentation and temporary XCTest access were still
enabled; these are not uninstrumented TestFlight measurements. Shake-it's
contact workload initially spent 1.118 ms on average generating sprites.
Caching only the seed-dependent property endpoints reduced that to 0.487 ms,
with identical successful-input counts and restart snapshots. Animation time,
easing, transforms and geometry are not frozen by the cache.

The cross-engine tests remain in scope. Four-mode paired renderer comparisons
also exercise 256 and 2,048 sprites, including overflow beyond the fixed cache
budget. An initial overflow slowdown was corrected before delivery; the final
policy was ~15% faster at 256 sprites and ~5% faster at 2,048 sprites versus
the prior random-variable cache alone. Independent review found no correctness
issues and its additional distinct-channel coverage was added. See
`COMPATIBILITY.md` for timings, test scope and limitations. All temporary build
setting/scheme changes were restored, and the async device harness now awaits
Metal completion without blocking the main actor.

Normal Debug validation on September 25 passed 208 tests; a simulator shutdown
terminated Eleventh, which passed on a separate rerun without code changes.
All 209 tests were exercised with no skips, and the normal app build succeeded.
This interrupted suite is not recorded as an uninterrupted full-suite pass.

### Device verification — September 20

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
error (CoreDevice 10002 / FBSOpenApplicationErrorDomain 7).

Subsequently, launch and XCTest execution succeeded on the actual iPhone 16 Pro
(thyme5, iOS 27.0). Seven selected particle, Metal framebuffer and synthetic
touch tests passed. The full physical suite then passed 189 of 191 tests and
crashed in two interpreter depth-limit tests. Both crash reports explicitly
reported `Thread stack size exceeded`: the large recursive dispatcher exhausted
the phone's approximately 1 MiB main stack before its 256-node depth guard.

The dispatcher is now divided into smaller non-inlined operation families;
literal-address handling has its own frame and argument evaluation avoids map
closure frames. Evaluation order, side effects and the 256-node limit remain
unchanged. Independent review found no semantic changes and prompted broader
stress cases. All 193 simulator tests pass, including deep valid trees and
cycles across 20 execution paths in both optimization modes, tested on the main
actor and a dedicated 1 MiB thread. After thyme5 was unlocked, the full suite
passed on the physical iPhone: 193 passed, zero failed or skipped. The result
bundle identifies thyme5's UDID, iPhone 16 Pro and iOS 27.0; both previously
crashing tests and the expanded depth tests passed. The September 20 23:48:03
Xcode test result is retained in local ActionArtifacts, not committed.

Xcode's interaction session tool listed only simulators. Physical test execution
and framebuffer checks are verified, but real-finger interaction, audible sync
and full-chart device gameplay are not.

The subsequent 23:55 physical suite passed all 197 tests, including opt-in
cached-chart integration tests for Eleventh Hard 16, 光 Hard 18, SIF Custom
Charts UNSTOPPABLE and 22/7 Pro 4.9. These resolved 419, 563, 658 and 949 inputs
exactly once and generated CPU sprites across the complete charts. Restart
samples also match after the first input resolves, not just during lead-in.
No server requests were made. Tests and measurements were independently
reviewed; the cached assets remain outside version control. See
`COMPATIBILITY.md` for scope and timing measurements. This does not establish
full interactive gameplay or audible synchronization on the phone.

## Intro visual boundary follow-up — September 21, 2026

The additional stopping condition is implemented and covered by seven new
regressions, including real GameplayModel startup with a generated local audio
file. The simulator suite passed 200 tests with zero failures; the four opt-in
cached-chart tests were skipped because their fixtures are not installed in
that simulator. No server requests were made. The phone reported locked during
this follow-up, so the earlier physical-device results do not certify this new
visual-boundary change. Independent review found no remaining correctness
issues; its additional rollback-coverage recommendation is now exercised at
model level, checking that future judgments and spawned entities do not leak.

## Still unfinished

1. Physical-device verification of close/coincident multitouch, dense flicks
   and holds, hit effects, audible sync, repeated starts, interruptions and
   gameplay frame pacing. These require the relevant device/build or field
   diagnostics; they cannot be certified by invented simulator measurements.
   Deferred until Sonolus API coverage is complete, then tested together with
   the Metal scheduling before/after comparison and calibration controls.
2. General engine compatibility is not complete: stack-function ABI and
   resource/callback conformance still need work. DebugLog/DebugPause now have
   opt-in logging and resumable pause support; this does not resolve the
   separately listed native/API ambiguities. Memory-block callback
   permissions are now enforced across all interpreter access paths, including
   spawned-entity restrictions. Declared block lengths are implemented, with
   zero reads for missing/out-of-range addresses as required by Get; the
   initial overrestriction on missing-block reads has been corrected.
   AddLifeScheduled's preprocessing-only rule is now enforced; remaining
   host-function and resource conformance stay open. Server playback now
   requires engine configuration and cannot silently bypass callbacks via the
   basic lane fallback. Explicit resource overrides and declared optional ROM
   must have usable HTTP(S) locators; absent ROM remains supported. Both online
   and offline playback perform unsupported-function preflight. Downloads may
   still archive an unsupported engine, but cannot play it through basic lanes.
   Engine option categories are now decoded and rendered in their declared
   order, with runtime option indices and per-engine persistence unchanged.
   Dedicated note-speed/score preferences work inside those categories, and
   legacy controls now resolve/reset generic saved overrides consistently.
   Skin mode selection is now
   honored, but exact native rendering parity is not claimed. Unsupported
   functions are surfaced before music rather than assumed harmless. See the
   separate contract checklist; sampled engines do not prove arbitrary support.
3. Intro skipping now preserves visible non-input effects and held opening
   graphics, with synthetic gameplay-model and renderer regressions. Unknown
   initial graphics stop skipping immediately; only narrowly proven persistent
   literal stage draws are exempt. Consequently custom/dynamic stage producers
   can retain more silence than necessary. First-input activation no longer
   ends skipping; unseen input resolution instead restores the original start.
   Broader safe stage classification and
   physical visual verification remain open, not an unresolved product choice.
   Unknown silence is never inferred from bgmOffset.
4. Full-chart no-touch runtime integration now passes on the physical device
   for four cached charts. Interactive playback, audio and display integration
   beyond those probes still need verification in the deferred device batch.
5. Physically verify the implemented manual visual/audio alignment control,
   independently of input-judgment adjustment. Passing simulator regressions
   and explicit sign/unit documentation do not certify acoustic alignment.
   Check calibration usability and alignment in the deferred device batch;
   resolve the public API's underdocumented audio-offset sign/unit convention
   without guessing a correction from the user's early/late distribution.

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
