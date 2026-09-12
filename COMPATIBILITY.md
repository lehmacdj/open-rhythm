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

## Remaining checks, including engines we have not sampled

- Stack layout/control semantics and all skin render modes.
- Optional/missing resources, callback-specific memory access and defaults,
  dynamically spawned inputs, generic options, and unknown enum values.
- Accuracy/error-heatmap HUD metrics, combo animations, alternate timing
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
