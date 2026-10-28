# Open requests

This lists the owner's requests that are still open and the directives that still constrain the work, as of October 28, 2026. Completed requests, superseded plans and their evidence are in the [request archive](docs/archive/REQUESTS-2026-10.md) (see [implemented and regression-covered](docs/archive/REQUESTS-2026-10.md#implemented-and-regression-covered) and the [breadth-first triage](docs/archive/REQUESTS-2026-10.md#breadth-first-triage--september-30-2026)). The engine and server contract is in [COMPATIBILITY.md](COMPATIBILITY.md); the user-facing summary is [APP_STATUS.md](APP_STATUS.md).

## Standing directives

- **Device testing gate.** Physical-device testing waits until Sonolus API coverage is complete, then happens in one batch ([below](#physical-device-batch)). Do not ask for phone unlocks, install development builds or run device checks before then, unless the owner explicitly asks for a specific issue to be checked sooner; that exception covers only that issue. A connected or unlocked phone does not reopen testing. (In force since late September; restated October 6.)
- **Stack functions.** Implementation and upstream clarification are deferred (September 29). Do not implement a guessed layout or post the clarification draft (`tmp/stack-contract-question.md`, ignored); posting it to the [Sonolus feedback repository](https://github.com/Sonolus/feedback) needs the owner's permission.
- **Pushing.** Push only when asked, and at most once per calendar day (America/New_York), to stay within App Store Connect's upload limit (build 82 was rejected with error 90382, "Upload limit reached"). Batch tested commits into one release. Check the day's pushes before publishing, and assume none are left if the count can't be established. Do not get around the limit with another branch, tag or release trigger. (October 3.)
- **No guessed timing corrections.** Do not add a calibration offset, loosen timing tolerances or infer the audio-offset convention from an early/late distribution.
- **Repository contents.** Do not commit third-party charts, audio, skins or diagnostic logs; scratch probes and downloads stay in the ignored `tmp/`. Do not crawl song servers beyond bounded pages; the paced stack-search crawl was a specific, now finished, authorization.
- **Working method.** The owner asked for breadth-first triage across areas, ranked by impact, rather than perfecting one subsystem at a time, and for narrow completion claims. The full [working guidelines](docs/archive/REQUESTS-2026-10.md#audit-working-guidelines--september-30-2026) are archived.

## Open requests

### Finish the request audit

The goal set in September is "Finish all of the items in the request audit." What remains is the stack functions, the physical-device batch and the audio-offset question below. Everything else in the audit has been implemented or has a recorded decision. Stable, tested subsets can still be released, but they don't complete the goal.

### Stack functions and a real stack chart

The 14 stack functions are unimplemented; [COMPATIBILITY.md](COMPATIBILITY.md#stack-evidence-needed) lists the evidence needed. On September 29 the owner asked for a real chart that uses `StackInit`/`StackGet` to help settle the contract. That request is still open: public code searches and the full paced crawl of 22/7, LLSIF and Project SEKAI (finished October 17, every enumerated level fetched) found no stack consumer. A negative search does not prove none exists.

### Physical-device batch

Deferred under the gate above. Record the tested build and the result for each check, and keep each check tied to its originating report.

| Check | Originating report or reason |
| --- | --- |
| Audio and display alignment; usability of Input Timing and Visual Timing; before/after latency of the `CAMetalDisplayLink` change (baseline: 33.76–34.12 ms sample-to-present on the old driver) | Reported audio/animation timing difference and excess Early judgments (September 25) |
| Close and coincident multitouch; normal and other flick variants, including a flick right after a long stationary hold; hold heads, ticks and releases | On the accumulated device-check list since September; simulator contacts are synthetic |
| Hit-effect appearance, including the particle size fix and the new seed-mixed randomness | Reported phone hit-effect problems |
| Dense-chart and curved-hold frame pacing and frame-time tails, especially "shake it!" Hard 18 (full MORE MORE JUMP / Kagamine Rin) | Reported curved-hold slowdown |
| Intro preservation and skipping | Lead-in and intro-skip requests |
| Repeated starts and restarts, rapid song-to-song changes, abandoned restarts, audio-session activation failures, interruptions, media-services reset (including hit sounds afterwards) and playback stalls, including stopped-clock input timing | Reported intermittent looping sound in 光; the audio-session ownership and interruption fixes |
| Catalog scrolling smoothness | Reported list scroll hitches |

Open question for the owner: the gate is "Sonolus API coverage complete," but the stack functions, the last API gap, are deferred indefinitely. As written, the batch cannot start until the owner either waives the stack functions for the gate or lifts the deferral.

### Audio-offset convention

Resolve how the runtime audio-offset field maps to time (units, playback-speed scaling and behavior when preprocessing changes it) from an independent source. Official settings text supports the current user-facing direction but not the numerical mapping. See the [checklist](COMPATIBILITY.md#remaining-acceptance-checklist).

## Watch items

Reopen these only with new evidence.

- **Intermittent simulator audio startup (BF-26).** AudioQueue start timeouts occasionally stall intro checks. Diagnose the next recurrence with the startup-stage diagnostics; do not rerun suites just to get a green run.
- **Atlas and crop memory (BF-11).** No actionable defect was found on October 6; reopen for a reproduced failure or new allocation data.
- **Crash reports.** As of October 6, TestFlight showed only the two September 10 build-1 search crashes, which are fixed. Xcode's analytics query failed ("Product not found"), so this does not prove there are no newer crashes.

## Deferred or declined

- Extra app-owned sound and animation packs and a hide-combo switch: deferred, as the owner asked. Engine-defined options and animations are separate.
- Local level import, a level writer and validator, separating engine modes, and preview and watch modes: considered in the October 28 review and deferred.
- Tutorial mode and online score submission: not requested.

## Settled decisions

Don't reopen these without a new request.

- Early/Late placement follows the engine, which replaced the earlier top-only request.
- Gameplay stays on screen until the music ends, which replaced continuing audio on the results screen.
- Gameplay options are saved per engine, not shared through Sonolus's cross-engine `scope`.
- History is never discarded automatically.
- Intro skipping may pass unchanged initial scenery (approved September 30).
- Arcade score streak bonuses keep their current reading (October 28).
- The Visual Timing entry in saved results records the engine-adjusted offset (intended).
