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
- Despawning is two-phase: all terminating entities retain Active state while
  all terminate callbacks execute, then final inputs are sampled and entities
  despawn. Synthetic linked peers cover same-frame state visibility and later
  Despawned state; other regressions cover absent terminate callbacks and
  exactly-once result handling.
- Reachable unsupported calls in lazy successful-hit branches and dynamically
  spawnable archetypes, not just functions encountered by a no-touch run.
- Separate event and frame timestamps, paused/running/rate-changing clocks,
  queued pre-resume events, startup seek bounds, and surviving audio commands.
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

## Remaining checks, including engines we have not sampled

- Stack layout/control semantics and native rendering parity.
- Optional/missing resources, callback-specific memory access and defaults,
  and unknown enum values.
- Runtime metadata lists a play-mode `skip` slot, while the public play block
  documentation does not explain it. It remains zero pending evidence of the
  intended semantics; intro fast-forward does not assume an undocumented mode.
- Tutorial/watch/preview modes are separate capability sets, not implied by
  play-mode support.
- Expired cursors, changing remote ordering, and sparse filtered results
  without unbounded crawls.
- Engine-generated count-ins and visible non-input intro effects. First-input
  activation is a conservative stopping boundary, not proof that every intro
  animation is preserved. Unknown silence is not inferred from bgmOffset.
- Physical device multitouch, rendering/audio latency, performance tails,
  successful flick/hold variants, interruptions, and repeated play. Simulator
  clocks and no-touch lifecycle completion cannot establish those properties.

Public references: [server specifications](https://wiki.sonolus.com/server-specs/)
and [engine specifications](https://wiki.sonolus.com/engine-specs/).
Download probes remain in ignored scratch storage; no third-party charts or
assets belong in the regression fixtures. Avoid catalog crawls: use bounded
pages and cached shared resources, and state exactly which paths were exercised.

The [despawning contract](
https://wiki.sonolus.com/engine-specs/play-lifecycle/despawning-system) runs all
terminate callbacks before despawning any entity. The old serial implementation
interleaved those operations, making later callbacks observe earlier peers as
already despawned. The regression is synthetic, not dependent on a sampled
engine happening to exercise this legal cross-entity read.

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
