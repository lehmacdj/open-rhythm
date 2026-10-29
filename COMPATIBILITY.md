# Engine and server compatibility

This is the current contract checklist for OpenRhythm's Sonolus support: what is implemented, what is unsupported, and what is still unverified. Evidence (test runs, measurements, reviews and the reasoning behind each decision) is in the [compatibility archive](docs/archive/COMPATIBILITY-2026-10.md) and the [request archive](docs/archive/REQUESTS-2026-10.md), which record work through October 6, 2026. Open owner requests are in [REQUESTS.md](REQUESTS.md); the user-facing summary is [APP_STATUS.md](APP_STATUS.md).

## How compatibility is judged

Compatibility is a contract, not a list of songs that happen to work. The 22/7 catalog failure was missed because integer-rated LLSIF and SEKAI fixtures were treated as evidence that a numeric protocol field was an integer. For every public field or function, check its declared type, optionality, legal callback and mode, value range, ordering and observable side effects, and test these independently of downloaded engines. Then use real engines and charts as integration probes, including successful inputs and restart and buffering paths.

Keep three claims separate: documented API coverage, fixture coverage, and parity with the native Sonolus client. Passing sampled engines does not prove arbitrary-engine support. Do not treat a normalized-unit description as a hard validation bound without checking executable reference behavior (the public [Sonolus Studio](https://github.com/Sonolus/studio) source is the usual reference); an earlier `0...1` particle-interval restriction rejected real SEKAI effects.

Public references: [server specifications](https://wiki.sonolus.com/server-specs/), [engine specifications](https://wiki.sonolus.com/engine-specs/), and the pinned [runtime metadata](https://github.com/Sonolus/runtime-metadata/blob/8da7fab2580701fdff82e10224f428db05add4bc/Runtime/Functions.json).

## Server and resource protocol

- Version 13 engine and level data. Fractional ratings and other numeric fields keep their full values through decoding, filtering, persistence and display.
- Quick keyword search, numbered pages and opaque-cursor pagination. A changing server's numbered pages are not an atomic snapshot: deduplication avoids duplicate rows, but only a server-side snapshot or cursor contract could rule out omissions during concurrent changes.
- [SRL](https://wiki.sonolus.com/custom-server-specs/misc/srl) resources keep optional URLs and per-role SHA-1 hashes. Hash-only resources are served from verified caches, a changed hash never reuses stale bytes at the same URL, and different hashes can share one URL without mixing content. Missing hash-only content fails without inventing a URL. Leading-slash paths resolve against the server address, as the SRL contract says.
- Relative artwork and music resolve against the level's declared source.
- Localized text uses Sonolus locale codes (`zhs`, `zht`) and falls back to the first language written.
- Gzip resources decode all concatenated members, with a cumulative output budget of 64 MiB (16 MiB for ROM).
- Effect ZIPs support stored and deflate entries, ZIP64 metadata, and UTF-8, legacy CP437 and CRC-checked Unicode Path filenames. Limits: 64 MiB encoded and total decoded, 16 MiB per entry, 1,024 entries. Other compression methods are unsupported.
- Server playback requires the engine configuration resource and always runs the engine; there is no non-engine fallback player. Explicit `UseItem` overrides need their family's files, and a declared ROM must resolve. An absent ROM is valid.
- Downloads fetch only the selected runtime resources and the level cover. Song grouping across difficulties uses known music URL/hash aliases within an engine; it is app policy, not a protocol song ID, and title equality alone never joins charts.

## Engine runtime

- Function coverage: 191 names in the pinned metadata. 175 are implemented and pass smoke calls against the production registry; 14 stack functions are unimplemented; Paint and Print belong to non-play modes. Smoke calls are not full semantic conformance.
- Before play, both online and offline, a callback-graph scan rejects reachable unsupported functions, including lazy successful-hit branches and dynamically spawnable archetypes. Debug-guarded branches do not fail the scan. Downloads may store an unsupported engine; playback rejects it.
- Play-memory callback read/write permissions, declared block lengths and zero reads for missing addresses (per `Get`) are enforced. Temporary Memory's initial contents are unpredictable by contract and are not assumed to be zero.
- Lifecycle: two-phase despawning (all terminate callbacks run before any entity despawns), deferred `Spawn` with no input and no level-backed blocks for spawned entities, stable callback ordering, NaN spawn order queued last, and restart from the prepared post-preprocessing state without rerunning preprocessing or rerolling randomness.
- `AddLifeScheduled` is limited to preprocessing. A review of all 39 implemented host-function pages and nine lifecycle pages at [wiki revision e5317da](https://github.com/Sonolus/wiki/tree/e5317da7228fd83346baa0e036c5784061ac3918/src/en/engine-specs) found no other documented callback exclusion; none is inferred.
- Control flow: integer switches and `JumpLoop` match exact branch labels; loops are bounded by per-callback operation limits. All named easing functions are implemented.
- Streams accept any finite numeric ID, including negative and fractional IDs. Skin, effect and particle IDs may be fractional.
- `Random` accepts reversed bounds; `RandomInteger` with an empty range returns its lower bound.
- `DebugLog` and `DebugPause` work behind a per-engine Engine Debug Mode setting, off by default.
- Playback speed is limited to 0.05–4×; music rate, BPM and time-scale lookups change together, and judgment windows stay in real seconds.
- Engine score weights, combo multipliers, score modes, life rules, judgment windows, result buckets (value, unit, windows and skin graphic) and export values are consumed as supplied.

## Presentation

- Skin render modes: an engine's explicit Standard or Lightweight wins; default defers to the player's Graphics preference. The two mesh algorithms are host approximations, not native pixel parity.
- Sprites: only requested sprites are cropped; fractional atlas bounds keep exact sampling regions. All six `DrawCurved` variants follow the public Bézier contract, with a shared 16,384-segment frame budget (host policy, not an API limit).
- Particles follow the public Studio importer and renderer for defaults (zero coefficients, linear easing), sizes, curves and loop intervals. Selected effects are validated before play; unselected ones are ignored. Random variables are seed-mixed with SplitMix64 so repeated spawns differ; native random realization is not claimed.
- UI configuration: HUD positions, metrics, judgment and combo animations, all 13 timing-indicator styles and Early/Late placement follow the engine. Unknown enum values fail before play. Option categories group settings without changing option-memory indices. Omitted UI sections use app defaults (host policy, not a documented default).
- The `errorHeatmap` metric and the results distribution use continuous, unbinned densities (host visualization policy).
- Backgrounds follow the public data, configuration and runtime-coordinate contracts. The blur radius is host policy, since the protocol does not define it.
- Metal renders the playfield through `CAMetalDisplayLink` with one-frame latency; a software renderer takes over on any Metal failure, including asynchronous GPU errors. Its pixel-work budget scales with frame size (at least 64 million pixels).

## Audio, input and timing

- Immediate, scheduled and looped effect sounds play on a native PCM renderer with sample-accurate scheduled starts and stops; buffering pauses voices without restarting them. At most 256 voices: when all are busy, the new sound is dropped. Clips that decode to zero frames are rejected. A zero minimum distance never suppresses a play.
- Touch times map UIKit timestamps through the music timebase, with rate-change history for queued touches. Velocity uses consecutive OS samples, including coalesced touches. Stationary contacts keep receiving `touch` callbacks every frame. A contact whose release was missed is ended before its ID is reused.
- While the music clock is stopped or waiting, engine frames freeze; existing contacts keep their movement and release events, and new presses are rejected. A stop is dated by inverting the previous moving clock mapping at the stopped media time, accepted only inside the observation window.
- Input Timing is supplied as the runtime input offset before preprocessing and subtracted from touch times once; the engine's preprocessed value is honored. Visual Timing is supplied as the runtime audio offset, with the mapping `runtimeTime = (mediaTime - levelBGMOffset) / playbackSpeed - audioOffset` in wall-clock seconds. Scheduled sounds compensate for it; immediate sounds stay immediate. Saved results record the engine-adjusted value.
- Results wait for music end and resolution of every input. Intro skipping simulates successive frames (the runtime `skip` value stays zero) and stops at audio, effects, changing visuals or visible input-owned notes. Unchanged initial scenery may stay onscreen while skipping (an owner-approved policy). If an unseen input resolves during skipping, the original start is restored.
- Haptics follow `EntityInput`; waveforms and simultaneous-request mixing are host policy.
- Gameplay options persist per engine, by product policy, instead of following Sonolus's optional cross-engine `scope`.

## Host limits

These are app safety limits, not Sonolus protocol limits or memory guarantees.

| Area | Limit |
| --- | --- |
| Response cache | 256 MB, ten-minute freshness; verified offline assets are stored separately and downloads do not fill it |
| Prepared music | 128 MiB after download; empty music is rejected |
| Metal textures | 8,192 pixels per side, 8 million pixels per image, 128 million RGBA bytes per renderer |
| Particle tints | Whole plan checked before the first tint; separate 128 million RGBA-byte budget |
| Backgrounds | 32 MiB encoded, 128 million source pixels (32,768 per side), decoded to at most 2,048 per side |
| Effect voices | 256 |

Atlas decoding and base sprite crops happen before these checks. An October 6 investigation found no actionable allocation defect; reopen it only with a reproduced failure or new allocation evidence.

## Unsupported

- The 14 stack functions: `StackEnter`, `StackGet`, `StackGetFrame`, `StackGetFramePointer`, `StackGetPointer`, `StackGrow`, `StackInit`, `StackLeave`, `StackPop`, `StackPush`, `StackSet`, `StackSetFrame`, `StackSetFramePointer` and `StackSetPointer`. Engines that can reach them are rejected before play. See [stack evidence needed](#stack-evidence-needed).
- Tutorial, watch and preview modes, including `Paint` (tutorial) and `Print` (preview).
- ZIP compression methods other than stored and deflate.

## Remaining acceptance checklist

Reopen a verified boundary only for new evidence, not because an older note says "more conformance." Earlier versions of this table are in the [archive](docs/archive/COMPATIBILITY-2026-10.md#remaining-acceptance-checklist--september-30-2026).

| Item | Status | What would close it |
| --- | --- | --- |
| Stack functions | Unimplemented. Implementation and upstream clarification deferred by the owner. | An authoritative specification, public reference implementation or legitimate reference trace of the pointer and frame layout; then independent conformance tests before implementation. |
| Audio-offset convention | The client's mapping is explicit and internally consistent. Official settings text supports the user-facing direction (increase when audio is late), but no source fixes the runtime field's numerical units, speed scaling or retroactive preprocessing behavior. | Independent reference evidence. Do not infer it from an early/late distribution. |
| Stopped-clock transition timing | Stops are dated from the previous clock mapping, inside the observation window. | Physical measurement in the device batch. |
| Automatic hold-tick classification | Seven known archetype names mark intermediate hold ticks, which are left out of the distribution and timing statistics (not scoring, hit rate or the scatterplot). Arbitrary engines have no verified universal classification. | A protocol signal or per-engine evidence. |
| Intro classification | Unchanged initial scenery, input ownership and visual-change checks are implemented. A non-input manager could draw note imagery without being recognized. | Client policy, not semantic recognition. Physical check in the device batch. |
| Native parity | Not claimed for skin filtering, mesh algorithms, particle random realization, blur, heatmap drawing, codec breadth, omitted UI defaults or export behavior on invalid or spawned entities. | Reproduce a valid-resource rejection or cite a missing rule before expanding support. |
| Intermittent simulator startup | AudioQueue start timeouts have occasionally stalled intro checks; a bounded October 6 reproduction did not trigger them, and startup diagnostics now name the stalled stage. | Diagnose on the next recurrence using those diagnostics, not repeated green runs. |
| Physical gameplay | Simulator and offscreen checks do not certify phone behavior. | The deferred device batch in [REQUESTS.md](REQUESTS.md#physical-device-batch). |

## Stack evidence needed

The [stack overview](https://wiki.sonolus.com/engine-specs/functions/stack-functions) puts the stack at the end of Temporary Memory, but the public pages do not define pointer values or frame layout. Several incompatible layouts pass the same push/pop round-trip test, so reference observations must include the pointer getters and the raw Temporary Memory cells.

| Question | Evidence needed |
| --- | --- |
| Initialization | Initial stack and frame pointer values; reserved control cells; whether `StackInit` clears data or only resets pointers. |
| Addressing | Whether pointers are absolute Temporary Memory indices; which cell `StackGet(0)` and `StackGetFrame(0)` address; offset direction. |
| Push, pop, grow | Whether pointer updates precede or follow access; exact return values; behavior of newly reserved cells. |
| Call frames | `StackEnter(size)` allocation and header layout; saved pointers; nested `StackLeave` restoration; frame-relative offsets. |
| Pointer setters | Relationship to backing memory and control cells, and effect on later push, pop and frame operations. |
| Lifetime and limits | Reset across callbacks and entities; legal bounds; overflow and underflow; interaction with ordinary Temporary Memory access. |

No real stack consumer has been found. Public code searches found only declarations, metadata and wrappers (for example [sonolus.h](https://github.com/SonolusHaniwa/sonolus.h/blob/86151ef255158ec36bf6e527febc9d198fa1e90b/sonolus.h)); one public web player maps all 14 functions to an unimplemented stub. The owner-authorized paced crawl of 22/7, LLSIF and Project SEKAI finished on October 17, 2026: every enumerated level (550, 1,916 and 9,635) was fetched with no failures, and none of the three engines contains a stack call. The two open-source fixture engines below use none either. This does not prove that no consumer exists, and the crawl is not an atomic server snapshot (SEKAI's page count moved between 481 and 483). Crawl tooling is in `scripts/`; its cache and report are in the ignored `tmp/cached-stack-crawl-20260930/`. Archive details: [stack evidence](docs/archive/COMPATIBILITY-2026-10.md#stack-implementation-evidence-needed).

The October 28 review found what is established: signatures, return values and side-effect flags in [runtime-metadata](https://github.com/Sonolus/runtime-metadata/blob/8da7fab2580701fdff82e10224f428db05add4bc/Runtime/Functions.json), unchanged from Sonolus 0.8.13 through 1.1.4. `StackInit`, `StackEnter` and `StackLeave` return 0; `StackPush`, `StackGrow` and `StackGetPointer` return the stack pointer; `StackSet` and `StackSetFrame` return the value set. The getters have no side effects, so `StackGet` does not pop. The functions date from 0.7.0, and the wiki text has never been more detailed ([wiki-engine-specs history](https://github.com/Sonolus/wiki-engine-specs/commit/3bdaa9ad18c63b40c6cc7cb5574f84750c4abba7)). Growth toward lower Temporary Memory indices is a strong inference, because the official compiler allocates its own temporaries from index 0 upward, but it is not stated. Initial pointer values, frame layout, offset direction, pointer storage and limits remain unknown. No toolchain emits these functions: sonolus.js-compiler, sonolus.py, sonolus.h and sonolus-go only declare or wrap them. Thirteen npm engine packages (including next-sekai 2.17.1, next-rush 2.16.3, and the bandori, llsif, taiko and mania engines) and two GitHub-released engines contain no stack calls. Two third-party projects reached the same gap: Sono-Renderer classifies stack as needing a reference oracle, and the sonolus-go simulator's stack model contradicts the wiki (separate storage, `StackPush` returning the value), which shows the spec is ambiguous rather than evidence of real behavior.

## Test coverage

- **Synthetic contract tests** cover the rules above without third-party data. They run in the default suite.
- **Open-source engine fixtures** run in the default suite: [sonolus-pjsekai-engine](https://github.com/NonSpicyBurrito/sonolus-pjsekai-engine) 1.9.0 and [sonolus-bandori-engine](https://github.com/NonSpicyBurrito/sonolus-bandori-engine) 1.6.4 (MIT), as git submodules under `OpenRhythmTests/Fixtures/Engines`. `EngineFixtureTests` checks version and unsupported-function preflight (neither engine uses one), loading of a generated placeholder presentation through the production loaders, no-touch resolution of every input in small hand-written levels, and deterministic output across restarts and runs. The tests skip if the submodules are not checked out (`git submodule update --init`).
- **Cached real-chart integrations** (`CachedEngineIntegrationTests`) are opt-in. They read an `OpenRhythmIntegrationFixtures` directory in the test host's `Library/Caches` and skip when it is missing; downloaded assets never enter the repository. They cover full-chart, restart and contact workloads for Project SEKAI (Eleventh, 光, "shake it!" Hard 18), SIF Custom Charts and 22/7. The fixture layout is described in the [archive](docs/archive/COMPATIBILITY-2026-10.md#reproducible-cached-chart-device-checks).
- **Not covered:** physical touch, audible alignment and live frame pacing. No-touch runs do not verify successful taps, flicks, holds or multitouch.
