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
- Engine playback speed changes BGM rate and BPM values together; chart and
  event clocks remain in real seconds, including lead-in and audio EOF tails.
- Engine combo animations and judgment animation final-state retention.
- Accuracy scoring consumes final EntityInput values, including misses and
  automatic ticks, independently of arcade weights or timing-plot filters.
  Scores persist in history; old miss-free samples do not invent legacy scores.
- Spawned entities have no input, even if their archetype declares hasInput;
  they must not introduce a false first-note boundary while skipping silence.
- Unused skin, effect, and particle families need no placeholder assets.
  Skin-only and particle-only initialization preserve the other family and
  interpolation settings. Declared families still require valid resources.
- Final EntityInput haptic requests are sampled after terminate and consumed
  once. Prebuilt haptics-only players support Light/Medium/Heavy/Long; no-hardware
  hosts remain playable. Reset/stop recovery is bounded and stale callbacks
  cannot affect a restarted session. Physical waveform/latency checks remain open.

## Remaining checks, including engines we have not sampled

- Stack layout/control semantics and all skin render modes.
- Optional/missing resources, callback-specific memory access and defaults,
  and unknown enum values.
- Error-heatmap HUD metrics and alternate timing
  indicator styles; tutorial/watch/preview modes are separate capability sets.
- Expired cursors, changing remote ordering, and sparse filtered results
  without unbounded crawls.
- Engine-generated count-ins and visible non-input intro effects. First-input
  activation is a conservative stopping boundary, not proof that every intro
  animation is preserved. Streaming silence is not inferred from bgmOffset.
- Physical device multitouch, rendering/audio latency, performance tails,
  successful flick/hold variants, interruptions, and repeated play. Simulator
  clocks and no-touch lifecycle completion cannot establish those properties.

Public references: [server specifications](https://wiki.sonolus.com/server-specs/)
and [engine specifications](https://wiki.sonolus.com/engine-specs/).
Download probes remain in ignored scratch storage; no third-party charts or
assets belong in the regression fixtures. Avoid catalog crawls: use bounded
pages and cached shared resources, and state exactly which paths were exercised.

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
