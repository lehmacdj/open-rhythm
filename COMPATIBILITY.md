# Compatibility is a contract, not a list of working songs

The 22/7 catalog failure was missed because integer-rated LLSIF/SEKAI fixtures
were treated as evidence for an integer protocol field. The public contract
allows a number. Merely adding a third engine would repeat that mistake.

For every public field/function, check its declared type, optionality, legal
callback/mode, value range, ordering, and observable side effects. Test these
independently of downloaded engine graphs. Then use cached real charts as
integration probes, including successful inputs and restart/buffering paths.

## Contract regressions now covered

- Particle subintervals now retain their animated tail across a loop boundary
  and include their exact end point while the parent effect remains alive.
  The independent reference is the official public Studio
  [renderer](https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/particle-renderer.ts)
  and [state construction](https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/particle-state.ts),
  not captured output from the proprietary client. Synthetic tests cover gaps,
  first-cycle wrapped tails, exact interval endpoints, repeated cycles, an
  offset spawn time and non-unit effect duration, non-looped parent expiry,
  animated position/alpha, and all four random/property cache combinations.
  Three focused simulator tests pass. Independent review verified the pinned
  sources and found no interval defect. Studio previews use modulo wall time;
  they do not prove native spawned-effect first-cycle or lifetime behavior.
  Existing one-shot parent expiry remains unchanged.
  Additional source comparison found easing-curve differences (Back/Elastic
  composition and Expo midpoint); these remain to be
  reconciled rather than treating the editor as a universal runtime oracle.
  Verification: September 25 04:16 simulator suite, all 261 tests passed with
  no failures or skips, including six cached-chart probes
  (`RunAllTests/172F14CB-4321-4EDD-A543-BFE46A109EC5.txt`). The observer timed out
  at 300 seconds; the same execution then supplied its full passing summary
  and `TEST FINISHED` marker. The 04:22 normal simulator build passed.
  No real-device tests or song-server requests were used.
- Particle `none` easing now steps from its initial value to its final value
  at phase 1, matching the pinned official Studio
  [easing definition](https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/ease.ts).
  The new regression failed before the fix and passes afterward. It checks
  ascending/descending steps, just-before-end behavior, clamped phases,
  omitted endpoints/easing, and direct versus cached endpoint evaluation.
  Rendered Y coordinates also check the step across the looping/non-looping
  interval matrix above. The 36 numerical engine easing functions do not
  expose `none`; their implementation is unchanged. UI animation already
  returned its final value at elapsed duration and remains consistent.
  Independent review found no defect. Four focused simulator tests passed
  at 04:24 (`RunSomeTests/9234154F-7F17-42B5-8BD0-663EB60B1A3E.txt`), including
  numerical easing and UI animation regressions; the 04:25 normal build passes.
  This is focused verification following the prior 261-test full-suite pass,
  not a new full-suite run or physical check.
- Presentation preparation now rejects unknown primary/secondary metrics,
  judgment-error styles/placements and UI/selected-particle easing names with
  a human-readable error identifying the field and value. This replaces silent
  missing HUD elements, fallback timing labels/positions, and linear animation
  substitutions. The accepted lists follow [Engine Configuration UI](
  https://wiki.sonolus.com/engine-specs/resources/engine-configuration-ui) and
  [Particle Data Effect](
  https://wiki.sonolus.com/particle-specs/resources/particle-data-effect),
  including all 38 easing names. Regressions cover each UI enum, all four UI
  animation channels, all six particle properties and preparation failure before
  gameplay starts. Both unused resource families and unused bad effects beside
  a valid selected effect remain ignored. Omitted optional particle easing
  retains the existing linear behavior. The public schema marks it optional
  without defining a default, but Studio's pinned
  [particle importer](https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/particle.ts)
  supplies linear easing and zero expression coefficients for omitted values
  in all six properties. This independently supports the existing defaults,
  without establishing proprietary native-client parity. Independent review
  found no implementation issue and suggested the same-resource unused-effect
  regression, which was added. Six focused simulator tests passed.
  The September 25 04:02 simulator suite passed all 260 tests, including six
  cached-chart probes, with no failures or skips
  (`RunAllTests/CAAA8DB9-CEC2-4909-8998-34C35BA81FC4.txt`). After the observer's
  300-second timeout, the same run supplied its complete summary and
  `TEST FINISHED` marker. The 04:08 normal simulator build passed. No physical
  testing or music-server requests were used.
- Engine [option categories](
  https://wiki.sonolus.com/engine-specs/resources/engine-configuration-option-category)
  now determine settings section titles and order. Options retain their original
  order within a category, and their original indices in Level Option memory;
  empty categories do not create empty sections. Configurations with no category
  definitions retain their existing layout. Duplicate category names and
  missing/unknown memberships fail clearly instead of dropping controls. Note
  speed and score-mode controls use the existing dedicated per-engine saved
  preferences even when grouped by the engine, with the same engine defaults
  and reset behavior. Independent review found that the legacy uncategorized
  controls could hide generic saved overrides; those now share preference
  resolution/reset with runtime and categorized controls. Follow-up review found
  no further issue. Five focused regressions pass, covering interleaved indices,
  category order, invalid metadata, persistence and resetting both dedicated
  and legacy overrides. The categorized-options Xcode preview was inspected
  at normal iPhone size; all controls and headers were readable and visible.
  Verification: September 25 03:51 simulator suite, 257 passed, zero failures
  or skips (`RunAllTests/486FB278-73E7-4437-B424-6E4A8CF86FA7.txt`), including all
  six cached-chart probes. The 300-second observer timed out, but the same run
  completed with a full summary and `TEST FINISHED` marker. The 03:56 normal
  simulator build also passed. No physical checks or server-resource requests
  were used.
- Initial play-memory conformance now has a table-driven regression independent
  of the sampled engines. It checks complete runtime, level, archetype, ROM,
  entity and array blocks after construction, including identity transforms,
  supplied environment/background/UI/option data, waiting entity identities,
  imported values, zero-filled storage, 1,000 initial/max life, archetype score
  weight 1 and input bucket -1. Nonzero values and block boundaries are also
  exported from inside preprocessing, so engine initialization cannot conceal
  missing host defaults. Mutation followed by restart checks restored state for
  two distinct entities. Public sources include the
  [play-block tables](https://wiki.sonolus.com/engine-specs/play-blocks/overview),
  [skin transform](https://wiki.sonolus.com/engine-specs/play-blocks/runtime-skin-transform),
  [life](https://wiki.sonolus.com/engine-specs/play-blocks/level-life), and
  [input](https://wiki.sonolus.com/engine-specs/play-blocks/entity-input).
  [Temporary Memory](https://wiki.sonolus.com/engine-specs/play-blocks/temporary-memory)
  is deliberately excluded: its initial contents are unpredictable, not
  contractually zero. Independent review caught and corrected that test
  assumption; follow-up review found no further issue. No production default
  needed changing. This is initialization/restart evidence, not stack-function
  support or a claim about all future/dynamic memory values.
  The September 25 03:40 simulator suite passed all 255 tests, with no failures
  or skips (`RunAllTests/E9CBE3FC-C140-46B8-B3B4-8651D6E909C1.txt`), including the
  six cached-chart probes. The observer timed out after 300 seconds; the same
  run then supplied the full summary and `TEST FINISHED` marker. The 03:45
  normal simulator build passes. Physical testing remains deferred.
- Server runtime bundles require the configuration resource declared by
  [EngineItem](https://wiki.sonolus.com/custom-server-specs/misc/engine-item).
  Missing presentation no longer silently selects the basic lane player and
  bypasses engine execution. That internal player now requires explicit local
  opt-in, never decoded from a server payload. Explicit
  [UseItem](https://wiki.sonolus.com/custom-server-specs/misc/level-item)
  overrides require an item and its family-specific resources. Declared ROM
  and all runtime resource locators must resolve to HTTP(S); omitted/null ROM
  remains supported. Missing unused resource families remain tolerated, so
  this is not a claim of exhaustive resource-schema validation. Both online
  and offline playback reject unsupported reachable functions; downloads may
  still archive them. Regressions cover malformed configuration/ROM locators,
  selected-family omissions, rejection before resource fetches, legacy offline
  manifests, model startup, and offline preflight without network access.
  Independent read-only review found no actionable defects. The September 25
  03:28 simulator suite passed all 254 tests, including six cached-chart probes,
  with no failures or skips
  (`RunAllTests/1F96EA5F-AB6E-4A32-870A-EDF0A0132E78.txt`). After the observer's
  300-second timeout, the same run supplied its full result summary and
  `TEST FINISHED` marker. The 03:33 normal simulator build passed. No physical
  checks or music-server requests were used.
- [AddLifeScheduled](
  https://wiki.sonolus.com/engine-specs/functions/add-life-scheduled) now rejects
  calls outside preprocessing, with an error naming both function and callback.
  Runtime regressions cover all eight callback contexts, including spawn-order
  preparation and termination, and verify rejection before any life event is
  queued. Valid preprocessing events apply once at their chart time and replay
  correctly after restart. Schedules are sorted lazily once and consumed with
  a cursor, replacing a sort on every insertion and full-array scans on every
  frame. Equal-time order, partially consumed snapshots and host-side appends
  are tested. This is an algorithmic reduction, not a measured gameplay FPS
  improvement. The two focused simulator tests pass and independent review
  found no actionable issue. The September 25 03:12 simulator suite passed all
  250 tests, including six cached-chart checks, with no failures or skips
  (`RunAllTests/5C0AA9BE-37A6-402B-B043-9FDBB734FFE5.txt`). The observation tool
  timed out at 300 seconds; the same run then provided its complete summary and
  `TEST FINISHED` console marker. The 03:18 normal simulator build also passes.
  No device tests or music-server requests were used.
- [DebugLog](https://wiki.sonolus.com/engine-specs/functions/debug-log) and
  [DebugPause](https://wiki.sonolus.com/engine-specs/functions/debug-pause)
  accept one and zero arguments respectively and return zero. A persistent
  per-engine debug setting seeds RuntimeEnvironment before preprocessing;
  host calls read the resulting flag, including engine preprocessing writes.
  Reachable debug-guarded branches no longer fail unsupported-function preflight.
  Log history is bounded to the latest 256 values (including nonfinite numeric
  diagnostics), shown bottom-right and in the pause panel, and checkpointed
  with preprocessing. Debug output stops intro skipping. Pause takes effect
  at the completed frame/preparation boundary, preserves the runtime and
  pending effects, freezes chart/input and EOF-tail time, and resumes without
  counting the paused wall time. Touch generations prevent stale contacts
  and preserve ID uniqueness within a runtime. Startup seeks may finish while
  paused but cannot start music until resume. Restart restores preprocessing
  logs/requests, and changing debug mode invalidates that prepared runtime.
  Normal play leaves debug effects disabled; results record debug mode when on.
  Public docs specify availability only in debug mode, not out-of-mode call
  behavior, log capacity, or instruction-level suspension. Returning zero
  without the side effect when disabled, bounded retention, and frame-boundary
  pause are explicit client policies, not independently proven native parity.
  Native AVAudioPlayerNode offline rendering verifies sample-continuous pause
  and resume for one-shots and loops. Scheduler regressions cover future starts,
  scheduled stops, and reservations becoming due between display updates.
  Independent review identified that last edge case; the fix and regression
  received a clean follow-up review. These simulator/offline checks do not
  establish physical output latency or interruption behavior.
  Verification: September 25 03:02 simulator suite, 248 passed, zero failed or
  skipped (`RunAllTests/4C3CA1E5-88BE-4230-B25B-BBC9ECEB282D.txt`). The tool's
  300-second observation timed out, but the same run finished and produced
  that complete summary and `TEST FINISHED` console marker; it was not restarted.
  The expanded preprocessing-override test passed at 03:07
  (`RunSomeTests/F36A8A9F-D3DA-4093-9515-1324D2177A30.txt`). Native PCM sample
  continuity is exercised in that full suite as well as the earlier focused
  two-test run. The 03:07 normal simulator build passes without reported errors,
  and the debug pause panel's Xcode preview was visually inspected. No physical
  checks were run.
- Play callbacks establish an explicit memory-access context. Interpreter
  reads and writes validate the public block access table, including direct,
  shifted, pointed, compound, increment/decrement, and Copy paths. Read-only
  blocks cannot be overwritten, and shared writes are restricted to their
  documented phases. Spawned entities have no Entity Data, Shared Memory,
  Info or Input; reads of those absent blocks return zero, while writes are
  rejected. They can still read original entities through arrays. Host
  initialization bypasses callback permissions, but respects block bounds.
  Callback context is cleared even when execution throws. Callback-specific
  availability of host functions remains a separate open check.
  Sources: [play-block access tables](
  https://wiki.sonolus.com/engine-specs/play-blocks/overview) and
  [Spawn restrictions](https://wiki.sonolus.com/engine-specs/functions/spawn).
  The access audit exposed four invalid synthetic fixtures (shared writes in
  shouldSpawn/initialize/updateParallel and a Level Data write in spawnOrder).
  Their counters, loop handles and preparation snapshots now use legal private
  or input memory, and the spawned helper writes shared state sequentially.
  Existing spawn-order, deferred-spawn, restart and scheduled-audio assertions
  remain intact. Eight focused tests pass; the final September 25 02:22
  iPhone 17 Pro simulator suite passed all 237 tests, with no failures,
  skips or unrun tests, including all six cached-chart probes. The normal
  simulator build also passes. Independent review found no actionable defects
  and verified that the fixtures preserve their intent. No physical checks
  were run; these results do not certify live audio/display alignment.
- Memory block lengths follow the declared fixed layouts and the loaded
  level's entity, option, bucket, archetype and ROM counts. The touch-array
  length follows each frame's contact count, so contacts from an older larger
  frame cannot leak through an out-of-range read. Restart restores the layout
  with the prepared state. Out-of-range writes cannot allocate extra slots or
  spill into the next entity's view. As an explicit defensive policy,
  out-of-range writes to existing writable blocks are ignored while returning
  their computed value; native invalid-write behavior is not claimed.
  The [Get contract](https://wiki.sonolus.com/engine-specs/functions/get)
  requires zero for missing blocks and out-of-range reads; this also applies
  through [GetPointed](https://wiki.sonolus.com/engine-specs/functions/get-pointed).
  Reads beyond machine-Int range return zero after evaluating their operands,
  rather than throwing during conversion. RuntimeUpdate retains the metadata's
  fifth `skip` slot, which stays zero; the wiki page's omission and broader
  skip semantics remain documented below.
  This corrects an overrestriction in the first permission-check change:
  reviewing block access tables without cross-checking the function's defined
  fallback had incorrectly made absent-block Get throw. Future conformance
  reviews must check both layers, not independently treat permission tables
  as the whole observable contract.
  Independent review additionally caught machine-integer conversion failures
  for large numeric addresses; those are covered at interpreter level, not
  only by direct memory-object tests. The final bounds table is indexed rather
  than hashed on every read. Its saved/live copies use roughly 160 KB per
  active runtime after the first frame. Scalar Get evaluation avoids a new
  temporary argument-array allocation. These are implementation costs and
  safeguards, not a measured claim of improved physical frame pacing.
  Final verification: the September 25 02:39 simulator run completed despite
  the tool's 300-second response timeout. Its saved report contains 240 passes
  and one obsolete assertion expecting an infinite block ID's Get to throw.
  After changing that assertion to expect zero, the 02:46 five-test rerun
  passed, including the one-MiB interpreter stack and touch-shrink regressions.
  All 241 tests therefore have passing evidence across the final runs, not a
  claimed single 241-pass run. The normal simulator build passes. All six
  cached-chart probes passed; no server requests or physical tests were used.
- Fractional ratings through decoding, filtering, persistence, and display;
  fractional callback orders; icon-only tags and omitted bucket units.
- Quick keyword search and opaque cursor traversal, including two-page
  prefetch, token encoding, cycle/mode-change rejection, refresh, and
  all-difficulty lookup.
- Execute0 and existing arithmetic, easing, memory-addressing, lifecycle,
  score/life, resource, timing, and host-command tests.
- Integer-switch discriminants and JumpLoop targets match exact branch labels.
  Fractional values, nonfinite arithmetic results, and oversized values take
  the no-match/default path instead of truncating to an unrelated branch or
  throwing during integer conversion. Side-effect tests verify the discriminant
  runs once and unselected branches never run; genuine loops remain bounded.
- Despawning is two-phase: all terminating entities retain Active state while
  all terminate callbacks execute, then final inputs are sampled and entities
  despawn. Synthetic linked peers cover same-frame state visibility and later
  Despawned state; other regressions cover absent terminate callbacks and
  exactly-once result handling.
- Restarts restore the prepared runtime instead of rerunning preprocess and
  spawn ordering. Prepared random values and shared/entity data survive retries;
  play state, spawned entities, judgments, life, score, audio/particle handles,
  streams and queued commands return to their preparation snapshot. Effective
  engine-option, playback-speed or viewport/safe-area changes rebuild it;
  host-only display settings and equivalent option values do not reroll it.
- Sequential and touch callback lists retain immutable callback ordering,
  with entity key as a stable tie-breaker. Only entities implementing the
  callback enter its list. Lists sort when participating entities spawn and
  remove retired entities after the full termination phase; restart clears both.
  A synthetic trace covers independent fractional orders, tied level/dynamic
  entities, empty callbacks, expiration-frame touch delivery and repeated runs.
- Reachable unsupported calls in lazy successful-hit branches and dynamically
  spawnable archetypes, not just functions encountered by a no-touch run.
- Separate event and frame timestamps, paused/running/rate-changing clocks,
  queued pre-resume events, startup seek bounds, and surviving audio commands.
- Playfield contact state is scoped to playback generation and model identity.
  Restart discards active contacts and queued releases; stale UIKit move/end
  events cannot recreate inputs in the new chart clock. New contacts get fresh
  IDs. The regression reproduced old 60-second contact timestamps surviving
  into a retry before the reset implementation, and passes after it. Fallback
  lane routing also clears occupancy and requires a fresh begin. That UIKit
  routing was independently code-reviewed, not physically exercised.
- Timing plots with exact-zero taps, automatic hold ticks, interior/outer
  outliers, multiple judgments, and large result payloads.
- All six DrawCurved edge variants, bilinear control coordinates, paired
  controls, corner-coupled skin transforms, captured runtime transforms,
  optional depth keys, and contiguous texture slices. Commands accept 1–1024
  integer segments within a shared 16,384-segment frame budget.
- Metal/software pixel comparisons for nearest/linear sampling, translucent
  textures and draw alpha, mirrored geometry, transparent texels, and genuine
  folded overlap. Software mesh frames share one texture cache and work budget;
  ordinary all-affine frames retain their Core Graphics fast path.
- Generic slider/toggle/select options, malformed defaults/ranges, unknown
  types, dedicated-control routing by type rather than name, and persistence.
  Standard gameplay overrides are retained with results.
- Skin render-mode precedence, legacy preference defaults and per-engine
  persistence. Explicit standard/lightweight overrides user settings; omitted
  and default defer to them. Both ordinary and curved skin patches use the
  selected mesh in GPU/software paths without changing texture filtering,
  transforms or particle policy. Native settings previews and pixel parity
  regressions cover both modes.
- Engine playback speed changes BGM rate and BPM values together; chart and
  event clocks remain in real seconds, including lead-in and audio EOF tails.
- Online preparation caches selected BGM before Ready and pins a separate
  local file for playback, restart, and PCM intro inspection. Shared URLs reuse
  fresh cached bytes across difficulties; cache eviction cannot delete active
  playback files, and this does not create a Downloads entry. Cancelled loads
  and unsupported interpreted engines do not start a music fetch. Basic lane
  fallback charts retain their existing no-interpreter behavior.
- Engine combo animations and judgment animation final-state retention.
- All 13 judgment error styles: None, word pairs, signs, arrows and triangles,
  with positive/negative direction from the public localization descriptions.
  Indicators appear only above the configured minimum error, including on
  PERFECTs; style and display settings do not alter timing or grades. A native
  preview covers every style in both directions.
- Accuracy scoring consumes final EntityInput values, including misses and
  automatic ticks, independently of arcade weights or timing-plot filters.
  Scores persist in history; old miss-free samples do not invent legacy scores.
- Engine-selected error-heatmap HUD metrics render signed, unbinned density
  instead of a placeholder, in either primary or secondary metric slots.
  Zero stays centered; known automatic hold ticks and misses are excluded.
  Every accepted input contributes to bounded multiscale accumulators, avoiding
  history rescans when the range grows. Native preview, sign symmetry, extreme
  range, selection gating and restart regressions cover this host display.
- Spawned entities have no input, even if their archetype declares hasInput;
  they must not introduce a false first-note boundary while skipping silence.
- Silent intro simulation stops for visible non-input graphics and particle
  lifetimes as well as the existing input/audio boundaries. Unknown graphics
  present at media zero preserve the entire opening; unchanged alone is not
  evidence of disposable stage decoration. A narrow exception requires literal
  standard-stage Draw calls from persistent non-input level entities without
  spawn conditions or mutable play callbacks. Custom names, conditional draws,
  ambiguous resource IDs and dynamic spawns cannot establish that exception.
  Changes/removal/reordering of initial decoration, background or visible HUD
  geometry rewind to prepared media zero before retaining runtime side effects.
  Projected sprite bounds respect skin/runtime transforms and screen aspect;
  transparent or offscreen Draw commands alone do not stop skipping. Bounds
  checks are conservative, not pixel-precise texture coverage. Synthetic tests
  cover a new effect at 0.5 s before 2 s audio onset, an initially held stage-named
  effect, particle/transition overlap, duplicate layers and producer provenance.
  A model-level rewind regression verifies that future judgments and queued
  spawns are discarded, but the same events still occur when playback reaches
  their original time afterward.
- Unused skin, effect, and particle families need no placeholder assets.
  Skin-only and particle-only initialization preserve the other family and
  interpolation settings. Declared families still require valid resources.
- Background resources follow engine defaults and per-level overrides, with
  each resource's own source URL. Online and existing offline manifests supply
  the same data/image/configuration. Fit, aspect override, axis scaling, color,
  blur and mask are applied; RuntimeBackground is initialized before preprocess
  and its later coordinates drive a perspective layer beneath the notes.
  Metal foreground pixels preserve alpha, and the software surface is separate
  from the background. Native checkerboard projection and repeated cached SIF
  playback with the selected background are covered; a full moving gameplay
  composite on a physical device remains part of device sign-off.
- Final EntityInput haptic requests are sampled after terminate and consumed
  once. Prebuilt haptics-only players support Light/Medium/Heavy/Long; no-hardware
  hosts remain playable. Reset/stop recovery is bounded and stale callbacks
  cannot affect a restarted session. Physical waveform/latency checks remain open.

## Interpreter performance validation

### Active callback dispatch — September 21, 2026

The runtime previously sorted all active entities separately for sequential
updates and touch dispatch every frame. It now retains sorted participating
lists across stable frames. Callback ordering follows the [sequential update
contract](https://wiki.sonolus.com/engine-specs/play-lifecycle/sequential-update-system).

On the same iPhone 17 Pro / iOS 26.5 simulator, a synthetic stable 512-entity,
300-frame workload measured 1.066 ms/frame before and 0.506 ms/frame after the
change. This isolates sorting overhead; it is not a chart-wide or physical FPS
claim. Its explicit ordering regression passes both before and after the change.
The cached Hikari Hard 18 fixture subsequently resolved all 563 inputs exactly
once and matched 121 restart frames through frame 667. Runtime plus CPU-sprite
time averaged 8.951 ms, with p95 21.068 ms, on that simulator. This remains above
a 60 Hz frame budget in the tail and excludes actual GPU/audio/touch work;
gameplay performance is not signed off.

The complete simulator suite then passed 206 tests with zero failures or
skips, including all four installed offline chart lifecycle/restart fixtures.
Independent read-only review found no ordering or retirement regressions.
Result bundle: `Test-OpenRhythm-2026.09.21_00-27-13--0400.xcresult`.

Particle random expressions now reuse seed-derived values across frames. The
cache retains at most 512 seeds per frame in two generations, never animation
time, quad geometry or runtime transforms. An initial FIFO design passed
correctness checks but independent review prompted an over-capacity probe:
it was 1.5% slower with 1,088 seed visits per frame. The revised admission policy
retains a useful subset instead of evicting it on every miss.

Paired Debug simulator probes of the final version alternated execution order
and matched every sprite's points, matrix, alpha, image and interpolation:
256 sprites over 240 frames took 0.9535 s uncached versus 0.7891 s cached;
2,048 sprites over 70 frames took 2.2126 s versus 2.0454 s. Tests include moving
effects, loop boundaries, restart ID reuse, eviction, aging and caller mutation.
These are synthetic CPU sprite-generation measurements, not GPU submission,
audio or physical-device performance. Seed sharing follows the public
[particle group contract](https://wiki.sonolus.com/particle-specs/resources/particle-data-effect).

Particle property endpoints are also cached now. The `from`/`to` expressions
depend only on the seeded variables; easing, visibility, geometry and runtime
transforms remain live. Keys include effect, group and particle identity as
well as the seed, so different definitions and reused restart handles cannot
share incorrect values. Two generations retain at most 2,048 fixed-size
six-property records. Once the current generation is full, overflow particles
compute directly without failed cache lookups.

Independent review found no correctness issue and prompted distinct-channel
test values to catch x/y/width/height/rotation/alpha wiring errors. Four-mode
comparisons cover caching neither, either, or both random variables and property
endpoints, including animated/moved effects, looping, restart and over-capacity
loads. The first endpoint-cache policy slightly regressed above capacity; the
revised bounded-prefix policy improved the paired 2,048-sprite phone workload
from 4.400 to 4.165 ms and 4.365 to 4.140 ms in two repetitions (~5%). At 256
sprites, it improved from 0.468 to 0.397 ms and 0.470 to 0.400 ms (~15%).

These September 21 measurements used the physical thyme5 Release configuration
with verified `-O` and whole-module optimization. XCTest access and coverage
instrumentation remained enabled, so they are not an uninstrumented TestFlight
benchmark. The temporary scheme/settings are not part of the delivered project.
All five cached chart checks passed before the endpoint optimization. The full
209-test optimized phone suite passed with the initial cache; the final
admission policy then passed the focused cache/equivalence/shake-it tests.
Shake-it Hard 18's repeated-contact workload retained 489 successful inputs and
121 matching restart samples: sprite mean/p95 changed from 1.118/2.418 ms to
0.487/1.024 ms. Combined runtime/sprite mean/p95/p99 were 2.870/5.904/10.157 ms.
The device harness is intentionally throttled and omits live audio/display
pacing; physical curved-follow smoothness and audible alignment remain open.

Final normal Debug verification on September 25 exercised all 209 tests with
no skipped fixtures: 208 passed in the full run, whose Eleventh test was
terminated when the simulator shut down. Xcode's device-state diagnostics
record that shutdown; Eleventh then passed separately without code changes.
The normal app build also succeeded. This is not a claim of an uninterrupted
209-pass run or a new physical-device measurement.

The prepared spawn queue now advances a cursor instead of shifting its entire
remaining array each time entities activate. This removes quadratic queue-copy
work over a long chart without changing the spawning contract. Synthetic tests
cover a blocked head, nontrivial spawn order, exhaustion, restart, and 20,000
entities activating and despawning one per frame. A single paired Debug
simulator probe took 0.473 s before and 0.320 s after for those updates (including
assertions, excluding preparation). This isolates queue overhead; it does not
measure real-chart phone frame pacing. Independent review found no issues.

Literal-address interpreter optimization retains live memory/entity binding,
read-before-operand ordering, truncating address conversion, and the original
operation/depth budgets. Four synthetic tests compare the optimized and ordinary
paths, including malformed/dynamic addresses, nested writes, ROM, temporary
memory and partial side effects when budgets expire.

Physical testing exposed a separate native-stack failure: the former large
recursive dispatch frame overflowed thyme5's 1 MiB main stack before reaching
the interpreter's 256-node limit. Operation-family dispatch and literal-address
evaluation now use separate small frames; argument evaluation uses an explicit
left-to-right loop. Deep trees and cycles cover 20 paths with and without
literal optimization, on the main actor and a dedicated 1 MiB thread. All 193
simulator tests pass. The full post-fix suite also passed on physical thyme5
(iPhone 16 Pro, iOS 27.0): 193 passed, zero failed or skipped, with the device
identity verified in the result bundle. This is not the separate Sonolus
stack-function ABI gap listed below, nor proof of unbounded engine compatibility.

Paired cached 1,800-frame no-touch runs compared every frame's judgments, draw
commands and audio/loop commands exactly. In the Debug iPhone 17 Pro simulator,
Eleventh averaged 16.54 ms unoptimized versus 11.71 ms optimized (p95 24.44 vs
17.14 ms); 22/7 averaged 1.462 vs 1.094 ms (p95 1.780 vs 1.332 ms). Execution
order alternated each frame. These measure runtime updates only, not live audio,
GPU submission, successful touches, Release performance or phone frame pacing.
The address table adds approximately 1.65 MiB for SEKAI's 72,110 nodes on 64-bit
hosts. An independent read-only review found no actionable correctness issues.

## Reproducible cached-chart device checks

`CachedEngineIntegrationTests` uses an opt-in
`Library/Caches/OpenRhythmIntegrationFixtures` directory in the test host's app
container. It never fetches resources. Missing fixture directories skip these
cached integration tests; incomplete installed fixtures fail rather than skip.
Only test code belongs in the repository, not downloaded assets.

The fixture layout has `sekai`, `sif`, and `nanaon` engine directories, each
containing `engine.gz`, `configuration`, `skinData`, `skinTexture`,
`particleData`, `particleTexture`, `effectData`, and `effectAudio`. Include
`rom.bin` when supplied by the engine. Charts are `eleventh.gz`, `hikari.gz`,
`shake-it.gz`, `sif/level.gz`, and `nanaon/level.gz`, relative to the fixture
root. Copy an
already-cached fixture directory with `devicectl device copy to`, using the
`appDataContainer` domain and the installed app's bundle identifier; do not
replace the whole app container or delete user downloads.

The tests simulate from media time zero at 60 Hz through every input's
resolution, checking exactly-once judgments and generating CPU sprites. Restart
replays from the original initial chart time and compares frame zero plus a
bounded window beginning with the first judgment. The harness now also replays
peak frames through offscreen Metal, separately from the timed lifecycle loop.
An extra shake-it Hard 18 run supplies deterministic repeated contacts and
checks successful hold heads, ticks and releases. Neither run plays music,
synthesizes physical touches, or exercises the results-screen UI.

On devices, the offline lifecycle and restart loops suspend for 100 ms between
roughly 100 ms work bursts. A continuous shake-it contact simulation was killed
by iOS for consuming 48 CPU-seconds in 49 seconds (80% over 60 seconds limit).
Pauses are outside the per-frame timing samples and do not change chart time or
skip simulated frames. They avoid artificially pegging a core for the entire
chart, but also change thermal/frequency conditions: these remain throttled
workload measurements, not live frame pacing or proof that production gameplay
avoids CPU-resource pressure. Independent review verified deterministic
sequencing, restart state and cancellation cleanup.

On September 20 at 23:55, the full suite passed on thyme5 (iPhone 16 Pro,
iOS 27.0): 197 passed, zero failed or skipped. Each cached chart resolved every
input exactly once. Restarts matched 121 sampled frames: frame zero plus two
seconds beginning with the first judgment. Independent review found no issues.

| Cached chart | Inputs resolved | Last judgment (chart seconds) | Mean / p95 CPU (ms) |
| --- | --- | --- | --- |
| Eleventh Hard 16, MORE MORE JUMP | 419 / 419 | 92.017 | 7.27 / 12.91 |
| 光 Hard 18, full 25ji | 563 / 563 | 100.433 | 9.39 / 22.39 |
| SIF Custom Charts UNSTOPPABLE | 658 / 658 | 97.550 | 0.52 / 0.69 |
| 22/7 Pro 4.9 | 949 / 949 | 135.117 | 2.01 / 3.09 |

These are instrumented Debug runtime-update plus CPU-sprite timings, with no
real-time pacing. They exclude GPU submission, live touches, music playback and
display latency. They are profiling leads, not Release frame-rate guarantees.
The initial Eleventh attempt failed to connect to the test runner and did not
execute; the successful rerun and final suite have separate result bundles.

## Remaining checks, including engines we have not sampled

- Stack layout/control semantics and native rendering parity. Debug functions
  are now supported as described above; their underdocumented policy choices
  must not be mistaken for independently observed native behavior.
  Paint (tutorial only) and
  Print (preview only) belong to the separately scoped non-play modes, per
  their [Paint](https://wiki.sonolus.com/engine-specs/functions/paint) and
  [Print](https://wiki.sonolus.com/engine-specs/functions/print) contracts.
- An independent audio-offset sign/unit reference: scheduled-audio docs require
  automatic BGM compensation but do not state the convention. Current tests
  establish the client's explicit wall-clock convention and internal timeline
  consistency, not parity with an independently observed native reference.
- Optional/missing resource defaults and host-function callback legality.
  Specified initial play-memory defaults and the known presentation enum lists
  now have dedicated conformance checks above. Underdocumented defaults still
  need independent evidence rather than being inferred from those tests. Memory-block callback
  read/write permissions are now enforced separately from those open checks.
  AddLifeScheduled's explicit preprocessing-only rule is now enforced; no
  undocumented callback exclusions are inferred for other host functions.
  Resource review found and removed a path where an absent presentation bundle
  selected basic lanes and bypassed engine callbacks/preflight. The public
  [EngineItem](https://wiki.sonolus.com/custom-server-specs/misc/engine-item)
  requires configuration; server bundles now require it and always select
  engine playback. Missing explicit `UseItem` overrides and malformed declared
  ROM locators now fail clearly rather than silently selecting defaults.
  Remaining resource/default conformance is not closed by these checks.
  [Option-category definitions](
  https://wiki.sonolus.com/engine-specs/resources/engine-configuration-option-category)
  are now decoded and used to group settings without reordering the runtime's
  option-memory indices; see the conformance entry above. Unknown presentation
  enums now fail explicitly; other resource/default checks remain open.
- Runtime metadata lists a play-mode `skip` slot. The public Python framework
  describes it as a time skip in the current frame, but the play block docs
  omit its seek/resimulation behavior. It remains zero: intro fast-forward
  currently simulates successive frames, rather than jumping the runtime clock.
- Tutorial/watch/preview modes are separate capability sets, not implied by
  play-mode support.
- Expired cursors, changing remote ordering, and sparse filtered results
  without unbounded crawls.
- First-input activation and conservative visual provenance can preserve more
  intro silence than necessary, especially custom/dynamic stage producers.
  Optimal first-visible-pixel skipping across arbitrary engines and physical
  presentation verification remain open. Unknown silence is not inferred from
  bgmOffset.
- Physical device multitouch, rendering/audio latency, performance tails,
  successful flick/hold variants, interruptions, and repeated play. Simulator
  clocks and no-touch lifecycle completion cannot establish those properties.

Public references: [server specifications](https://wiki.sonolus.com/server-specs/)
and [engine specifications](https://wiki.sonolus.com/engine-specs/).
Download probes remain in ignored scratch storage; no third-party charts or
assets belong in the regression fixtures. Avoid catalog crawls: use bounded
pages and cached shared resources, and state exactly which paths were exercised.

Restart preparation follows the [play lifecycle](
https://wiki.sonolus.com/engine-specs/play-lifecycle/overview). Synthetic runtime,
host-snapshot and gameplay-model regressions cover state restoration and cache
invalidation. Cached Eleventh and 22/7 retries matched fresh runs for 600 frames
in drawing, particles, audio/loop commands, score, life and resolved-input count
(51 and 48 respectively). No remote requests were needed. These probes do not
establish audible restart behavior or timing on a phone.

The [despawning contract](
https://wiki.sonolus.com/engine-specs/play-lifecycle/despawning-system) runs all
terminate callbacks before despawning any entity. The old serial implementation
interleaved those operations, making later callbacks observe earlier peers as
already despawned. The regression is synthetic, not dependent on a sampled
engine happening to exercise this legal cross-entity read.

Branch dispatch follows [SwitchInteger](
https://wiki.sonolus.com/engine-specs/functions/switch-integer), its
[default variant](https://wiki.sonolus.com/engine-specs/functions/switch-integer-with-default),
and [JumpLoop](https://wiki.sonolus.com/engine-specs/functions/jump-loop).
The previous implementation reused a truncating memory-address conversion for
branch labels, so -0.25 could select/repeat branch zero. The public
[Sonolus.py reference interpreter](https://github.com/qwewqa/sonolus.py/blob/master/sonolus/backend/interpret.py)
also uses exact matching. The regression failed before the correction and
passes afterward. Future numeric-argument checks must distinguish exact labels,
addresses, ordinary arithmetic and enums instead of sharing one conversion.
After this dispatch change, cached 600-frame no-touch openings for Eleventh,
光, SIF Custom Charts and 22/7 ran without errors or duplicate inputs, resolving
51, 57, 34 and 48 inputs respectively. These bounded openings supplement the
synthetic branch tests; they are not full-chart or physical-device sign-off.

Stack ABI research also checked that public Python interpreter; like the
JavaScript wrappers, it does not implement stack functions. This is not evidence
that an engine using those functions will work. The public
[runtime API](https://github.com/qwewqa/sonolus.py/blob/master/sonolus/script/runtime.py)
supplies the current description of the skip flag.

After the two-phase fix, cached no-touch lifecycle runs resolved each input
exactly once: Eleventh Hard 16 419/419 at 92.017 s; 光 Hard 18 563/563 at
100.433 s; SIF UNSTOPPABLE 658/658 at 97.55 s; 22/7 Pro 4.9 949/949 at
135.117 s. The largest simultaneous batches were respectively 4, 4, 2 and 2.
Initial 60-second snippet runs timed out; extending the execution allowance
returned complete results. These runs omit live audio/rendering and successful
touches. The SEKAI lifecycle probe remains CPU-heavy in Xcode's instrumented
simulator (Hikari 83.3 s for 100.4 s of 60 Hz chart updates), so this is not a
claim that dense-chart phone performance is solved.

OpenRhythm intentionally keeps gameplay preferences per engine, following the
requested settings policy, rather than sharing generic options across engines
by Sonolus `scope` or saving unscoped options per level. Playback speed is
bounded to 0.05–4×; unsupported values fail explicitly before music starts.
The public contracts for [options](
https://wiki.sonolus.com/engine-specs/resources/engine-configuration-option) and
[Spawn](https://wiki.sonolus.com/engine-specs/functions/spawn) inform the tests.
See [the thread request audit](REQUESTS.md) for delivery vs verification status.

Input calibration follows the [input contract](
https://wiki.sonolus.com/engine-specs/essentials/input) and
[Runtime Environment](https://wiki.sonolus.com/engine-specs/play-blocks/runtime-environment).
The host supplies the selected per-engine offset before preprocessing, then
subtracts the resulting environment value from touch `t` and `st` exactly once.
Engines can modify that value during preprocessing; those changes are honored,
including after restart. Raw frame time, velocity and music time are unchanged.
Offsets are real seconds, independent of playback speed. Positive offsets
compensate late inputs; negative offsets compensate early inputs. The ±250 ms
UI range is host policy, not an engine judgment window. Legacy preferences use
zero, and changing settings affects the next play rather than a live gesture.
Audio/display calibration and end-to-end latency measurements remain separate
unfinished work; input calibration does not establish synchronization.
Independent read-only review found no correctness issues. Regressions cover
engine-added offsets, invalid preprocessing writes, both signs, real-second
units at 0.5×/1×/2× speed, unchanged motion/frame clocks, restart invalidation,
fallback hold/miss deadlines, legacy defaults and per-engine persistence.
On September 25, the normal simulator suite passed 211 of 212 tests; a
documented simulator shutdown interrupted shake-it's no-touch test, which
passed separately without code changes. All fixtures ran, with no skips.
The normal app build succeeded with no build warnings. The settings preview
initially timed out; a later iPhone 17 Pro/iOS 27 preview verifies the calibration
controls and explanatory text. Physical input/latency validation remains open.

The result-screen distribution uses narrow continuous Epanechnikov kernels:
bandwidth is max(1 ms, maximum absolute error / 256). This preserves the jagged
peaks requested from the ITG reference without copying its palette. Both result
plots use Swift Charts' default judgment colors; explicitly requested red miss
lines remain red. Sampled polygon areas are normalized per judgment to retain
note counts despite straight-edge approximation. Explicit support boundaries
prevent interpolation through empty gaps. Broader error ranges widen kernels
to bound geometry independently of input count; 10,000-input tests across three
scales remain below 16,384 marks. This is result analysis, not the live HUD
heatmap, whose streaming contract is unchanged. Twenty-one focused result tests
pass; native light/dark, zero-only, empty, dense, outlier and accessibility-size
previews were inspected. No gameplay clocks or judgment windows changed.

Accuracy follows the [public result-screen formula](
https://wiki.sonolus.com/getting-started/explore/result-screen), using absolute
errors from [EntityInput](https://wiki.sonolus.com/engine-specs/play-blocks/entity-input).
The public description does not specify live count-up behavior or rounding:
OpenRhythm normalizes resolved contributions by the full input count, rounds
to an integer, and clamps the display to 0–1,000,000. Countdown reserves perfect
credit for unresolved inputs. These display policies do not adjust touch timing.

Haptic types follow EntityInput. Exact platform waveforms and chord mixing are
host policy: simultaneous requests use the strongest type, and Long is a 150 ms
continuous effect. Unknown type values do not synthesize feedback. Haptics never
replace engine sound effects, and failures do not abort gameplay.

Online BGM preparation can take longer on a slow connection but avoids network
stalls during the song and a separate silence-analysis transfer. It uses the
existing ten-minute response-cache freshness policy. Prepared music is limited
to 128 MiB after downloading; this is not a streaming download-size limit.
Cancelling one consumer does not abort a shared cache request used by others.

Timing style pairs and their sign convention follow the official
[English UI descriptions](https://github.com/Sonolus/i18n/blob/develop/src/localizations/en/Localization.json).
For example, the `early` style intentionally displays Early for positive error,
and Late for negative error. Omitted or unknown style values retain the default
Late/Early pair; `none` hides only the timing indicator, not the judgment grade.

Backgrounds follow the public [data](
https://wiki.sonolus.com/background-specs/resources/background-data),
[configuration](https://wiki.sonolus.com/background-specs/resources/background-configuration),
and [runtime coordinates](https://wiki.sonolus.com/engine-specs/play-blocks/runtime-background).
The protocol defines blur amount, not its pixel radius: this host uses a Gaussian
radius of 5% of the smaller prepared-image dimension at blur=1. Images decode
to at most 2048 pixels per side before blur, preserving original aspect ratio.
Encoded backgrounds over 32 MiB or source images over 128 million pixels / 32768
per side fail explicitly. Degenerate or folded projective quads hide the image
while retaining background color and mask. These policies do not alter skin
sprite interpolation or engine input geometry.

The public UI contract names `errorHeatmap` without prescribing its drawing
algorithm. OpenRhythm uses continuous compact-kernel densities sampled at 129
positions across a symmetric ±25 ms power-of-two range that expands to include
all accepted errors. Nineteen scales retain all inputs with bounded work and
storage; samples are not assigned to histogram bins. Kernel bandwidth is two
grid spacings, at least 1 ms. The label is signed mean error in milliseconds;
accessibility also exposes the range and input count. This is host visualization
policy, not claimed pixel parity with Sonolus. The 10,000-input simulator probe
measured record plus snapshot at mean 0.0223 ms / p95 0.0254 ms / max 0.526 ms;
these numbers do not establish phone frame-time tails.

Skin mode selection follows [EnginePlayData](
https://wiki.sonolus.com/engine-specs/resources/engine-play-data). The public UI
describes lightweight as faster and less accurate without specifying its
algorithm. This host uses two triangles per quad/curved patch for lightweight,
and an adaptive 1–8 subdivision bilinear mesh for standard. These are explicit
host approximations, not a claim of identical native Sonolus pixels. Particles
and background rendering remain independent of the skin mode.

On 1,800 cached Eleventh frames (1800×1000 viewport, up to 75 sprites), paired
mesh-generation probes used 7,808,178 standard versus 370,068 lightweight
vertices. Mean/p95 mesh generation was 0.408/0.716 ms versus 0.170/0.286 ms.
The fixture declared lightweight and retained that mode despite a Standard
user preference. These simulator measurements isolate geometry work; they do
not measure phone frame pacing, GPU completion or successful-hit load.
# Opt-in playback timing diagnostics — September 25, 2026

Gameplay Settings can record local timing summaries alongside a play. The
recorder uses fixed-size signed quarter-millisecond quantile buckets, with
underflow/overflow intervals; means and extrema retain original values. This
is instrumentation storage, not the unbinned result timing distribution.
All samples contribute throughout a play, and callback state belongs to that
play alone. Result snapshots are immutable; late callbacks cannot mutate saved
history or a restarted play. No identifiers for individual audio devices are
retained, only output port types and iOS-reported latency/buffer duration.

Metal uses actual drawable presentation timestamps on device. The simulator
SDK does not expose this API, so it records unavailability instead of inventing
presentation time from GPU completion. The clock sample is timestamped around
the player read; the read span is separately reported. The event/player clock
comparison is restricted to advancing audio, excludes the post-audio tail,
and uses chart-time seconds so playback speed does not rescale the difference.
The other frame metrics include buffering/tail frames after intro preparation.
Reports are not acoustic calibration and do not prove live synchronization.

Independent review found and prompted correction of two measurement biases:
contact-loop processing no longer inflates later fingers' delivery age, and
sprite-recorder overhead no longer appears as Metal encoding duration. Builds
for simulator and thyme5 succeed. Thirty-eight focused tests pass, plus two
reruns after adding final result-snapshot coverage; these cover signed bounds,
nonfinite samples, whole-play retention, concurrent callbacks, restart/setting
isolation, result persistence, clocks and existing result plots. A native
diagnostics preview verifies wrapping, counters, route/latency and share control.
The full 221-test regression run then passed without failures or skips. The
new native-window renderer probe, added during that run, was not included in
its compiled test bundle; it passed separately on simulator and thyme5.
The physical iPhone 16 Pro/iOS 27 probe submitted 12 empty 100×100 Metal frames:
11 had actual presentation timestamps, one was unavailable. Sample-to-present
mean was 23.59 ms, range 17.84–30.82 ms. The simulator correctly reported all
12 presentation timestamps unavailable. This 0.31-second callback-path probe
has no music, engine workload or display-link pacing: its values must not be
used as gameplay latency or a calibration offset. A final device build passed.
Enabled/disabled overhead, startup timing and live gameplay/audio alignment
remain to be measured before drawing synchronization conclusions.

### Live player/event clock regression

`testLivePlayerAndInputClocksAgreeAcrossSpeedsAndRestarts` creates a quiet
four-second CAF in a unique temporary directory, without fetching assets. It
prepares the actual GameplayModel and AVPlayer, advances the engine after intro
preparation, and compares player-derived frame time with the event-clock mapping
at the frame sample's host timestamp. Four short runs cover 0.5×, 1×, 2× and 1×
after restart, with 40 samples each; later delivery must preserve the mapping
of each earlier event timestamp. The test independently checks initial chart
time, runtime speed option and BPM, so both clocks cannot silently agree at an
incorrect default 1×. This assertion was prompted by independent review.

The final tests pass on iPhone 17 Pro/iOS 26.5 simulator and thyme5. The first
phone attempt was cancelled while waiting for unlock; the user's subsequent
unlock allowed actual device execution. The manually advanced test's maximum
observed absolute input/player-clock difference was 0.0201 ms across the four
short phone runs. This is a software-clock check, not acoustic or physical-touch
alignment. Startup's first 100 ms and network buffering remain separate checks.

`testLivePlayfieldCombinesPlayerClockDisplayLinkAndPresentation` uses the same
generated audio with the actual EnginePlayfieldView, CADisplayLink and Metal
layer in a temporary native window. The empty engine isolates infrastructure;
it does not represent a full chart. The 01:37 phone run's mean sample-to-present
age was 33.76–34.12 ms across the four rates/restarts; presentation minus display
target averaged 16.27–16.73 ms. This exposes an additional-refresh presentation
lead to investigate, not permission to apply a guessed offset. The route was
Speaker with iOS-reported output latency 15.35 ms and buffer duration 21.33 ms;
neither is a measured acoustic output delay for this play.

Scheduled audio startup exposed negative raw timebase extrapolation before its
future anchor. The actual input path already clamps to the completed seek's
media position. Diagnostics now retain the raw metric (with its existing stored
key) under an explicitly unclamped title and add a separate effective input-clock
comparison using exactly that same clamp. Effective input/player differences
remained near zero, even when raw startup differences reached approximately
−114 ms. The clamp was extracted unchanged and regression-tested at positive
seek floors, negative raw values and all three speeds. No gameplay timing
behavior, calibration or judgment windows changed. Three focused tests passed
on both simulator and device; the final device build passed without warnings.
Independent review also prompted rejecting repeated reads of a stale frame:
the native test now requires distinct frame timestamps and continued runtime
advancement during observation. All 17 clock/diagnostics tests pass together on
simulator; the strengthened native-playfield and persisted-label tests pass
again on thyme5. No full-suite rerun is claimed for this follow-up.

## Metal display scheduling follow-up (physical comparison pending)

The playfield now uses `CAMetalDisplayLink` on the existing iOS 17 minimum,
with `preferredFrameLatency = 1`. The renderer consumes the drawable supplied
by the update instead of calling `nextDrawable` a second time. Diagnostics
use `targetPresentationTimestamp` (intended display time), not the distinct
Metal submission deadline. Software rendering retains `CADisplayLink`.
Both asset-preparation and drawing failures switch the display driver along
with the renderer. Window removal invalidates the link; reattachment creates
a new one. Chart, input, audio and judgment clocks are unchanged.

This follows Apple's documented
[Metal display-link contract](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink)
and [one/two-frame latency preference](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframelatency).
The initial real-window simulator regression passed on September 25 at 01:46.
The simulator cannot measure drawable presentation timestamps. Physical
before/after comparison was initially held by a locked phone and is now
deliberately deferred under the user's post-API-coverage batch policy. Do not
interpret the API change itself as proof of lower latency. The prior measured
33.76–34.12 ms sample-to-present means are the unchanged-driver baseline.
The display-target difference is not directly comparable between driver APIs;
sample-to-actual-presentation age remains the common end-to-end measurement.

Verification: the September 25 01:47 full simulator run passed 227 tests,
including all six cached-engine lifecycle/stress checks. The software-fallback
test added while that run was active was correctly reported as not run.
At 01:52 it passed in a separate seven-test focused run, together with live
Metal/player clocks, manual player clocks, detach/reattach, native drawable
delivery, upright sprites/translucent connectors and both curved-rendering
backends. Thus all 228 tests have passing evidence, not in a single final
suite run. The final physical-device build at 01:53 passed. Independent
read-only review found no remaining actionable issue; it did not run tests.
The fallback regression exercises the real attached-view driver handoff, not
an injected GPU/encoding failure inside an in-flight frame. The unit is still
local at this checkpoint; the user has since deferred physical verification
until Sonolus API coverage is complete (see REQUESTS.md). Do not resume phone
checks unless that gate is met or the user requests a specific exception.

## Manual visual calibration and scheduled-audio offset contract

Visual Timing defaults to zero and is saved per engine independently of Input
Timing. The control accepts ±250 ms in 1 ms steps and has a reset button.
Positive values delay visual/input timing relative to BGM; negative values
advance it. Both settings are snapshotted per play. Changing either effective
environment input invalidates the prepared-runtime cache; an unchanged restart
restores the engine's preprocessed state. The effective visual value appears
in result options, including engine preprocessing adjustments.

The client's explicit mapping is:

`runtimeTime = (mediaTime - levelBGMOffset) / playbackSpeed - audioOffset`

The inverse preserves media zero and supplies intro/seek/EOF mapping. Offset
seconds are wall-clock seconds, not divided again by playback speed. Hardware
touch time uses the same mapping; the separate input offset is still subtracted
once by the runtime. No latency measurement or histogram bias is automatically
added. `RuntimeEnvironment[2]` receives the user's value before preprocessing;
the model adopts the engine's final finite value before intro analysis/seeking.

The public contracts for
[PlayScheduled](https://wiki.sonolus.com/engine-specs/functions/play-scheduled),
[PlayLoopedScheduled](https://wiki.sonolus.com/engine-specs/functions/play-looped-scheduled)
and [StopLoopedScheduled](https://wiki.sonolus.com/engine-specs/functions/stop-looped-scheduled)
require automatic audio-offset compensation. Scheduled commands subtract the
environment value at invocation to map BGM time into runtime time. Thus their
music position is unchanged by calibration. Immediate commands keep current
runtime time, so user-triggered feedback is not deliberately delayed. These
pages do not independently specify offset sign/units or retroactive behavior
if preprocessing changes the offset after issuing a scheduled command. These
under-specified cases remain compatibility uncertainties; the deterministic
tests are not a native-client oracle.

Verification: five focused simulator tests passed at 02:01 September 25, and
the normal-size iPhone settings preview at 02:02 shows the new control,
explanation and reset without truncation. The 02:04 full simulator run passed
232 tests, including every cached-engine lifecycle check. The fallback
composition test added during that run was reported as not run, then passed
at 02:09 together with three focused regressions. All 233 tests therefore have
passing evidence across those runs, not one uninterrupted final suite. The
new model-level test verifies a preprocess override before intro/seek, retained
media zero, live input clocks and result metadata across speeds/restarts.
Preference decoding, clamping, per-engine persistence and reset are covered.
The 02:09 normal simulator build passed; independent read-only review found no
actionable defects and did not run tests. Physical testing remains deferred by
user instruction until API coverage is complete. Native parity for the
underdocumented offset conventions remains open despite the passing tests.
