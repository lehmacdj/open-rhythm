# Compatibility is a contract, not a list of working songs

The 22/7 catalog failure was missed because integer-rated LLSIF/SEKAI fixtures
were treated as evidence for an integer protocol field. The public contract
allows a number. Merely adding a third engine would repeat that mistake.

For every public field/function, check its declared type, optionality, legal
callback/mode, value range, ordering, and observable side effects. Test these
independently of downloaded engine graphs. Then use cached real charts as
integration probes, including successful inputs and restart/buffering paths.

## Contract regressions now covered

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

- Stack layout/control semantics and native rendering parity.
- Optional/missing resources, callback-specific memory access and defaults,
  and unknown enum values.
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
