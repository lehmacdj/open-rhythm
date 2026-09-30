# Thread request audit — September 13, 2026

This ledger distinguishes implemented behavior from remaining compatibility
work and device verification. Passing simulator tests does not establish that
phone audio alignment, touch handling, or frame pacing is correct.

## Audit working guidelines — September 30, 2026

The intended outcome is dependable, engine-faithful gameplay and completion of
the user's requested app features, not an ever-growing count of tests or fixes.
The user requests breadth-first work, not subsystem-by-subsystem perfection.
The active goal remains “Finish all of the items in the request audit.” A
proposed replacement is not authority to change its scope or completion gate.

1. **Discover broadly before choosing the next fix.** Make bounded passes
   across gameplay timing/input, rendering/performance, API/resource
   compatibility, catalog/downloads, and results/settings. Record findings
   promptly instead of immediately implementing every issue encountered.
   Keep reviewed areas and unreviewed areas explicit; a negative spot check
   does not establish complete coverage. Normally time-box discovery to
   10–15 minutes, then choose an action; extend only for a stated concrete
   question. Do not repeat a negative check without new evidence, a relevant
   code change, or a previously identified missing path.
2. **Triage the whole backlog.** Each finding should include evidence or a
   reproduction, user impact, confidence, affected scope, dependencies, and
   the next bounded action and an observable acceptance criterion. Distinguish
   confirmed defects from suspicions, missing coverage, and undocumented
   contracts. Choose the highest-priority
   actionable issue across all discovered findings, not simply the next issue
   in the file or subsystem currently open.
3. **Prioritize impact and reach.** Crashes, data loss and silent corruption
   come first; gameplay-affecting timing, input and frame pacing generally
   outrank narrow compatibility edge cases and presentation polish. Account
   for prevalence, confidence and risk when ordering work. A low-confidence
   high-impact report can warrant diagnosis before a confirmed minor defect.
   Record the reason for choosing the next item; do not invent severity from
   an unverified hypothesis.
4. **Bound each implementation pass.** Define the defect and completion check,
   fix it, add a meaningful regression, and verify in proportion to the risk.
   Obtain independent post-fix review as requested. Broader tests remain
   appropriate for shared runtime changes and stable release batches, but
   do not endlessly expand an edge-case matrix or chase incidental refinements
   before reconsidering higher-impact work elsewhere. Add follow-up findings
   to the backlog and re-triage after each completed unit. Stop when the unit's
   acceptance criterion is met, not when every adjacent question is answered.
5. **Respect dependencies without serializing unrelated work.** Defer issues
   that need unavailable evidence or authorization, with the exact dependency
   recorded, and continue other actionable work. The stack contract and the
   physical-device testing gate remain in force. The paced cached crawl runs
   independently under its dedicated agent; do not wait for more files to
   investigate unrelated issues. Bring back meaningful crawl findings or
   blockers, not unchanged progress polls.
6. **Keep completion claims narrow.** Separate implemented behavior, verified
   regressions, remaining questions and deferred device checks. Push stable,
   tested units under the existing authorization without treating that subset
   as completion of this audit.
   **September 30 push limit:** at most four repository pushes per calendar
   day in America/New_York, to avoid App Store Connect limits. This is a cap,
   not a target: batch tested local commits into meaningful releases instead
   of pushing each fix. Check the day's successful pushes before publishing;
   if the count cannot be established, do not assume unused capacity. No
   further pushes on September 30. Continue local commits/testing normally.
   Do not evade the limit through another branch, tag or release-trigger path.
7. **Batch verification by risk.** Run the focused regression for a fix; run
   the broader non-cached suite for high-risk shared changes or a coherent
   release batch. Use expensive full-chart runs for affected runtime, render
   or audio paths and release acceptance, not documentation-only updates.
   Review meaningful fix batches independently. An observation timeout does
   not establish a test failure: inspect the run before launching another.
   Record exact
   chart, difficulty, input workload and test environment; no-touch playback
   does not verify successful taps, flicks, holds or multitouch.
8. **Preserve the next action across continuations.** Maintain one short
   current-work record below: outcome, selected action, reason, acceptance
   check and dependencies. Read it and the latest human request after context
   recovery. Automatic goal continuations are not new human requests to
   re-acknowledge or re-document an old policy. Report material progress,
   findings and decisions; avoid repeating unchanged deferrals. Keep long
   historical evidence below the working record, not in every status reply.
9. **Make remaining scope finite and evidence-based.** Classify work as
   unimplemented, reproduced, implemented but unverified, verified with stated
   scope, or deferred with an exact dependency. Replace vague “more conformance”
   tasks with named contracts and acceptance checks. Documented API coverage,
   fixture coverage and native-client parity are different claims. Do not
   silently add undocumented native behavior as an indefinite completion gate,
   or drop actual missing API semantics because sampled engines do not use
   them. A negative discovery pass is a valid result, not a reason to invent
   another patch. If all remaining required actions are genuinely gated,
   report the dependencies instead of cycling through cosmetic audit edits.

## Current work record — September 30, 2026

- **Outcome:** complete the requested features and documented play-mode API;
  establish dependable timing, input and rendering with the deferred physical
  validation batch, without claiming that simulator tests prove those outcomes.
- **Completed action:** BF-24 preserves numeric resource IDs end-to-end while
  retaining integer indices/handles. Fractional declarations failed before
  the fix; 387 non-cached tests plus cached SEKAI startup and 22/7 contacts
  pass, as do the normal build and independent review. Work is local.
- **Selected next action:** BF-25, engine-provided result buckets. Reproduce
  the loss of EntityInput bucket/value at despawn, trace it through new and
  persisted results, and use the declared metadata without conflating custom
  bucket units with accuracy in seconds.
- **Why:** source review exposed another supplied field the client discards.
  This affects requested complete statistics and engine-driven behavior, so
  it outranks further speculation about atlas allocation or native parity.
- **Acceptance:** engine-selected grouping/value/unit and graph participation
  survive despawn and history persistence; declared sprite/fallback metadata
  is honored in bucket presentation. Keep requested timing-in-seconds plots,
  score/accuracy calculations and legacy-result readability intact. Verify
  generic synthetic names and cached hold ticks before replacing name-based
  exclusions. No physical checks or stack implementation are authorized here.
- **Dependencies:** stack ABI implementation remains deferred; the dedicated
  cached crawl is independent, serial within each server with 60–120 second
  jitter and caching. Physical testing waits for full Sonolus API coverage
  unless the user explicitly requests an earlier issue-specific check. Stable
  tested subsets may be pushed, but do not complete the broader goal.

## Workflow retrospective — September 30, 2026

Read all 74 human comments in the canonical five-segment thread history,
excluding 111 automatic goal continuations and environment/configuration
messages. At that snapshot there were 816 assistant progress updates and 121
final replies, totaling about 40,700 whitespace-delimited words. Recorded tool
events included 473 test calls and 163 build calls; these are calls, not counts
of successful independent runs, and include failures and observation timeouts.
At least 11 final replies primarily repeated the device-deferral policy.

The problem is not just message length: repeated policy acknowledgments,
fine-grained verification cycles and growing historical ledgers displaced
attention from user-visible acceptance. These counts do not establish that
every repeated test was unnecessary. The correction is the working record,
risk-based batch verification and explicit stopping criteria above. Retain
the useful regression evidence, but measure progress by resolved requirements
and reduced uncertainty about the remaining important outcomes. Raw history
analysis stays in ignored temporary files, not in the repository.

## Breadth-first triage — September 30, 2026

Reconciliation pass: the resource/default review distinguishes host policies,
native parity questions and actual documented API gaps. It found BF-18 below.
An Xcode simulator probe also measured the visual intro guard on five cached
charts without playing audio or making requests. At default options/aspect 1.8,
all three SEKAI charts had no statically recognized stage archetype and stopped
at the first stage draw, one simulated frame after the initial empty frame:
shake it! -8.521833 (initial -8.538500), Eleventh/光 -8.983333 (initial -9).
Each stopping frame contained only “Sekai Stage,” no judgment, particle or
scheduled engine audio. SIF stopped on nine note slots at 0.016667; 22/7 already
had visible note graphics at that time. This isolates a visual-guard boundary,
not actual audio onset, complete GameplayModel startup or physical alignment.
The probe is retained in ignored `tmp/intro-boundary-audit.swift`.

| ID / priority | Finding and evidence | Acceptance / next action |
| --- | --- | --- |
| BF-18 / P2 — verified | Download recursively fetched overridden default assets, non-play engine data and thumbnails. The regression failed on unwanted requests despite successful online bundle preparation. | Selected runtime resources plus level cover now download; all four override/default families, ROM, source-relative artwork, malformed-update preservation and offline reload verified. All 61 offline/catalog tests, normal build and independent review pass. Existing manifests are pruned only through ordinary updates. |
| BF-19 / P2 — approved policy implemented and verified | Initial non-input scenery, including first-cycle deferred stage spawns, may remain onscreen while silence advances. Initial changes/disappearance rewind; visible input-owned graphics, particles and later additions stop advancing. | Cached GameplayModel startup passes Eleventh, 光 and shake it! twice each; all 381 non-cached tests, normal build and independent review pass. No engine-name exception or timing shift. Physical behavior and semantic note imagery drawn by non-input managers remain outside this bounded evidence. |
| BF-20 / P2 — verified | Catalog artwork and relative BGM identity ignored the level source. The regression reproduced wrong cover URLs, incorrectly joined different-origin audio, and a missed absolute-URL alias. | Shared level resource-base resolution now matches runtime/offline behavior. All 77 catalog/offline tests, normal build and independent review pass. Absolute URLs, absent-source fallback, existing incremental row IDs and persisted result/download identities are preserved. |
| BF-21 / bounded regression verified | New opt-in Eleventh normal-flick regression resolves entity 6: stationary control misses, measured upward movement succeeds at +1/60 s, and restart repeats the result. | Pooled/coalesced sample path, cached engine and unchanged windows/options; independent review clean. This closes the named cached-workload gap, not other flick variants, UIKit/physical delivery or acoustic timing. No gameplay code or calibration was changed. |
| BF-22 / P2 — verified | Cross-engine preparation profiling isolated repeated per-pixel tint arithmetic as a main-actor loading cost. Exact 256-entry channel tables now amortize that work; below 256 pixels the original arithmetic avoids table setup. | Paired Debug presentation means: SEKAI 461.9→312.2 ms, SIF 10.6→8.6 ms, 22/7 61.3→40.6 ms. Exhaustive channel-byte equivalence, tiny/cutoff images, alpha, metadata and allocation-failure checks pass in 20 focused tests. Normal build and independent review pass. Loading improvement only; in-song/device performance remains open. |
| BF-23 / P1 — verified | Native-clock/cached-engine contacts failed immediately in 22/7 with invalid StreamSet arguments. Cached engine node 627 explicitly writes stream ID -9999; the host invented a nonnegative-integer restriction. Prior no-touch lifecycle tests never reached that contact path. | All five stream functions now preserve finite numeric IDs without narrowing. New synthetic and cached contact/restart regressions failed before the fix; 16 focused tests, all 384 non-cached tests, normal build and independent review pass afterward. The actual GameplayModel probe now reaches chart time 8 s in all three engines, including 33 successful 22/7 judgments. |
| BF-24 / P2 — verified | Declared skin/clip/particle IDs and bucket sprite references were narrowed to Int despite numeric public schemas. Fractional declarations failed to decode, and missing finite IDs could throw instead of reporting absence. | Numeric identities now survive resource maps, drawing, audio and particle caches; indices/counts and generated handles remain integers. All 387 non-cached tests, two bounded cached integrations, normal build and independent review pass. No sampled-engine fractional-ID occurrence or native-client parity is claimed. |
| BF-25 / P2 — result metadata finding | EngineJudgment drops EntityInput bucket/value; results retain archetype-name types instead. Bucket units/sprites are decoded but unused in results, and fallbackId is not decoded. Intermediate hold exclusion is a known-name list. | Preserve engine-assigned result metadata through despawn/history and honor bucket presentation while retaining requested timing plots. Establish graph participation from the public contract and cached evidence, not from zero error or guessed archetype semantics. Test custom units, missing buckets, fallback sprites and old results. |

BF-24 evidence: the fractional decode regression failed before production
changes in `RunSomeTests/4F1DCB41-5706-4CA1-8729-FFBE6B784DE2.txt`.
Four focused checks passed in
`RunSomeTests/8C4B6D28-5D3A-45A2-ADED-E197F23E6B79.txt`.
The first broader run passed 386/387 and exposed an old malformed-input test
that incorrectly required HasSkinSprite(greatestFiniteMagnitude) to throw.
That test now rejects infinity and explicitly expects zero for the unavailable
finite ID. Final run: all 389 selected tests pass with no skips/failures,
`RunSomeTests/F8488A14-9BE5-405A-ADC1-D05B369D9803.txt`; normal build:
`BuildProject/BuildProject-Log-20260930-200012.txt`. The two cached checks cover
SEKAI startup/restart and 22/7 stage contacts/restart, not complete chart replay.
Independent concrete-diff review is clean. Native fractional audio-ID behavior
was not separately measured; synthetic audio coverage uses mock voice pools.

BF-25 source evidence: [Entity Input](
https://wiki.sonolus.com/engine-specs/play-blocks/entity-input) supplies bucket
index at cell 2 (-1 means none) and bucket value at cell 3. The runtime currently
reads cells 0, 1 and 4 only when collecting judgments. [Engine Data Bucket](
https://wiki.sonolus.com/engine-specs/resources/engine-data-bucket) explicitly
describes result graphs and supplies unit and composite sprites, including
optional fallbackId. `GameplayModel.ingestJudgments` instead uses archetype
names and `NoteTiming.isIntermediateHold` recognizes seven fixed tick names.
This is a source/data-flow finding; a behavioral reproducer and correction are
next, not already verified by BF-24's decoding test.

BF-23 is a contract/coverage correction, not an engine-name exception. The
public [StreamSet contract](https://wiki.sonolus.com/engine-specs/functions/stream-set)
does not constrain IDs to nonnegative integers, and
[ReplayData](https://wiki.sonolus.com/replay-specs/resources/replay-data)
represents stream IDs as numbers. Signed/fractional/large finite IDs now remain
distinct across get/has/neighbor/set operations. Nonfinite rejection, total
entry budgets, replacement, interpolation and prepared-state restore remain.
The regression also checks signed zero and values beyond Int's range.
Pre-fix failures: `RunSomeTests/53046CE5-1456-46C7-BB7A-5402224B755C.txt`.
Post-fix focused run: `RunSomeTests/F4276FAC-2C93-43F4-95A7-8A6EEF12388E.txt`.
Broader suite: `RunSomeTests/D904DC7D-49FA-4321-9A3B-F1ED73E3E3D0.txt`;
normal build: `BuildProject/BuildProject-Log-20260930-172346.txt`.

Why prior checks missed it: the general stream test explicitly encoded the
unsupported ID restriction, while the full cached 22/7 workload supplied no
contacts. Passing that pair reinforced the same blind spot rather than
independently checking the contract. The new cached regression requires an
actual stage-touch stream write and repeats after restart; positive-input
coverage must accompany lifecycle coverage when evaluating another engine.

### Live gameplay phase diagnostic — September 30

Opt-in saved timing reports now include **Gameplay bookkeeping** (score/life
snapshots, judgment storage/feedback and haptic dispatch) and **Effect audio
dispatch** (command collection, clock reads and native scheduling). They sample
completed CPU phases only, including idle polls; they do not measure SwiftUI
layout, acoustic latency or total display-frame time. Recording remains off by
default, with existing per-play isolation, fixed storage and string-keyed report
compatibility. Recording work is outside the adjacent phase's timing interval.

The bounded cached probe used actual GameplayModel/AVPlayer, generated local
music and native effect audio, default engine options, aspect 1.8, eight pooled
periodic stationary contacts, and manually paced nominal 60 Hz updates through
chart time 8 s. Sprites were generated but not submitted to a display/GPU.
This was a Debug simulator measurement, not deterministic autoplay or physical
input/display/acoustic validation. Means include frames with no judgments.

| Cached workload | Advancing frames / successful judgments | Runtime mean ms | Bookkeeping mean / max ms | Effect dispatch mean / max ms | Sprite mean ms |
| --- | --- | --- | --- | --- | --- |
| shake it! Hard 18 | 469 / 18 | 8.37 | 0.01 / 0.07 | 0.02 / 0.08 | 0.91 |
| SIF UNSTOPPABLE | 460 / 16 | 1.00 | 0.01 / 0.05 | 0.03 / 0.07 | 0.24 |
| 22/7 cached Pro 4.9 | 460 / 33 | 2.11 | 0.01 / 0.10 | 0.03 / 0.12 | 1.86 |

These samples do not justify optimizing bookkeeping or effect scheduling.
The metrics remain available for the deferred physical batch, where dense
inputs, route changes and scheduling costs may differ. Scratch probe/output:
`tmp/live-gameplay-phase-profile.swift` / `tmp/live-gameplay-phase-results.txt`.
The first probe's own fatal assertion produced a preview-process crash log on
the handled BF-23 gameplay failure; the diagnostic was changed to print the
failure and stop before reproducing/fixing the host defect. It was not treated
as an unexplained native audio crash. The new report round-trip and live-clock
phase-count checks pass with restart/debug pause coverage in the focused and
384-test runs recorded above. Independent review found no remaining issue.

BF-22 profiling covered compressed engine/chart decode, cached asset reads,
presentation, native effect-bank construction, runtime preprocessing, Metal
pipeline creation and texture upload across all three engine families. No BGM
or remote assets were fetched and no music was played. SEKAI's initial warm
presentation cost was 475–476 ms, including 417–419 ms for 131 tint variants /
1,169,750 pixels; runtime preprocessing was 235–237 ms, audio-bank construction
111–112 ms and texture upload 50–55 ms. These phases happen before play, and
their Debug simulator timings are not Release/device frame-time measurements.
The selected optimization addresses the largest measured preparation phase,
not an inferred cause of the reported curved-hold slowdown.

The final paired probe alternated the original tint arithmetic and the new
implementation through the same factory seam, discarded the first warm-up
pair, then averaged three pairs. Tint-subset means were 402.3→253.8 ms (SEKAI),
5.88→3.89 ms (SIF) and 56.65→36.06 ms (22/7). The temporary probes and output
are retained under ignored `tmp/preparation-profile.swift`,
`tmp/tint-paired-profile.swift` and `tmp/tint-paired-profile-results.txt`.
Independent review found a tiny-image setup regression in the first version;
the retained direct-arithmetic path fixes it. The final 20-test run is
`RunSomeTests/FA8E0CD2-60BC-423B-865F-E983EFD04F51.txt`; normal build is
`BuildProject/BuildProject-Log-20260930-171108.txt`. No full-chart replay or
physical check was needed for this byte-equivalent preparation-only change.

BF-21 initial verification: the new cached flick test and the two coalesced
input regressions pass in
`RunSomeTests/3D856613-2F4A-4076-9337-503A073D475B.txt`. The test bounds
execution to the first normal flick, rather than rerunning whole songs, and
includes a stationary negative control and two moving attempts across restart.
The final harness-throttling version also passes:
`RunSomeTests/7AEF1122-7E90-4DE6-BA2D-C3945F913557.txt`.
No music is played and no remote resources are fetched. Physical harness
throttling follows the existing cached suite; this does not authorize device
execution before the API gate. Tested work remains local under the new daily
push limit.

BF-20 verification: the source-resolution regression failed before the fix
(`RunSomeTests/33C7A511-D2C8-4640-A4E4-FEEF6C0513B7.txt`). All 77
catalog/offline tests pass afterward
(`RunSomeTests/5F3B007F-0CF1-4234-B3AE-690903842106.txt`), and the normal
build passes (`BuildProject/BuildProject-Log-20260930-164144.txt`). Independent
review found no actionable regression. No result key, manifest ID or saved
schema changed; newly reconstructed rows use the corrected BGM identity.

BF-19 trace follow-up: at the same default options/aspect, the first visible
note graphics appear at chart time -0.138500 (shake it!), -1.283333 (Eleventh)
and -1.983333 (光). The custom stage is unchanged from its first draw until
those times. These are simulated presentation times, not audio onset or a
physical latency measurement. Independent review agreed that custom names and
stability do not establish whether a held graphic's duration is dispensable.
The rendered graphic shown to the user is the lane playfield and purple
judgment line, on a black backdrop without the HUD.

BF-19 implementation: the user approved skipping past that unchanged stage.
Input ownership now follows each draw through ordinary/curved rendering and
host restart snapshots. The visual guard may capture non-input scenery during
the initial update and its first deferred Spawn cycle, but never a later
appearance. It compares the retained opening layers before permitting any
addition; moving/fading/disappearing initial graphics and changed HUD/background/
life rewind rather than discard a held count-in. Particle, debug, engine-audio
and hidden-input safeguards remain in force. This is an approved client policy,
not a protocol claim that every unknown opening graphic is stage decoration.

The cached regression drives GameplayModel with real cached engines/charts
and generated audio with known silence through chart zero. It stops at the
first visible input-owned notes after 7.7167 / 7.0167 / 8.4 seconds for
Eleventh / 光 / shake it!, repeating after restart with zero resolved inputs.
Generated audio isolates the startup policy; this does not establish actual
song audio onset or acoustic alignment. Independent review corrected fixture
preference isolation (a unique base URL, not just a unique server ID); final
review is clean. Results: all 381 non-cached tests
`RunSomeTests/6F31F313-9197-4312-8891-E0C7DC1FB065.txt`, final cached startup
`RunSomeTests/9C62C561-B7C2-4767-8293-DB06615423E6.txt`, normal build
`BuildProject/BuildProject-Log-20260930-165807.txt`.
The earlier policy requiring static-expression proof for every initial sprite
is superseded. Note ownership identifies the drawing archetype's hasInput flag;
it is not general semantic recognition of images drawn by non-input managers.
Do not claim universal optimal first-note classification from these fixtures.

Tenth bounded discovery pass: inspected playback/input clock consumption,
callback scheduling, audio reservation handling, result payload transactions,
catalog pagination, download identity and settings/results persistence. An
independent read-only cross-area review also found no new actionable defect.
These are bounded negative checks, not proof of general correctness. A suspected
discovery-time difficulty overwrite was ruled out because the picker is
disabled during discovery; do not add it as a confirmed bug.

The next action selected was to resolve the scope of the vague remaining
host-callback legality item, rather than extend tint/memory-limit polish. All
39 implemented host-function specification pages and nine lifecycle pages at
the pinned public wiki revision were read. They establish the already-enforced
preprocessing/debug restrictions, but no further explicit callback exclusion.
COMPATIBILITY.md now separates that completed documented-exclusion check from
underdocumented native policy and full function semantics. No timing calibration,
callback allowlist, resource budget or gameplay behavior was changed.

Current-build cached full-chart/restart verification completed: all seven
tests passed, using existing assets only. Coverage includes shake it! Hard 18
with no-touch/restart, repeated contacts and stationary pooled contacts,
Eleventh, 光/Hikari, SIF Custom and 22/7/Nanaon:
`RunSomeTests/7F2E5E85-0C70-4053-B9FD-A7ABF49B6BAA.txt`.
These supplement the earlier 378 non-cached passes; they were not one combined
385-test run. A short CPU sample of the repeated-contact harness includes both
dense and sparse interpreter execution and is not a live frame-pacing or clean
before/after measurement. Physical checks and stack ABI implementation remain
deferred; neither this source audit nor the independent review closes them.

Ninth bounded discovery pass: inspected atlas decoding, selected crop/tint
preparation and Metal's eager upload boundary. Atlas/base-crop memory growth
still lacks an observed failure or a justified tighter numerical limit, so
BF-11 remains diagnostic. A separate concrete failure-path defect was found:
the tint factory silently returns its original, untinted sprite if Core
Graphics cannot create its context or output image. The caller then caches
that image as if the engine's color were applied. This is not evidence for
the reported phone effect bug's cause. Select explicit preparation-failure
propagation next, with tiny injected-failure fixtures; do not induce OOM or
invent new resource limits to make the diagnostic look resolved.

BF-17 focused verification: injected nil context/output factories and a missing
source image produce explicit particle-preparation errors. Declared warmup
propagates failure; an incidental lookup can retry successfully without a leaked
budget charge or wrong cache entry. Existing transparency and fractional UV
checks pass with unchanged pixel math:
`RunSomeTests/3408DCA8-9C8D-4772-B4DC-690ED4B0C571.txt`.
The interrupted observer was recovered from its completed Xcode result, not
restarted. Independent post-fix review found no actionable issue.

A separate cached-resource preparation probe passed for SEKAI, SIF and 22/7,
including Metal upload. Unique prepared-image nominal RGBA payloads remain
20,341,844 / 265,796 / 7,440,064 bytes. Atlas metadata reports skin/particle
dimensions 2048²/1024², 512²/256² and 2048²/1024² respectively. These bounded
fixtures establish continued resource acceptance, not arbitrary atlas safety,
resident memory, real-time frame pacing or physical effect correctness.
All 378 non-cached simulator tests passed:
`RunSomeTests/7C205261-3773-49B7-ABB0-1EFD825DBCAE.txt`.
Normal build passed: `BuildProject/BuildProject-Log-20260930-160102.txt`.
No remote assets were fetched for this unit. Re-triage before expanding the
remaining atlas-allocation diagnostic; this fix does not close it.

Eighth bounded discovery pass: revisited the public offset/input and scheduled
audio contracts, BPM/time-scale selection, stream boundary lookups, judgment
metadata ingestion and catalog grouping. The [offset guide](
https://wiki.sonolus.com/getting-started/advanced/offsets) and
[PlayScheduled](https://wiki.sonolus.com/engine-specs/functions/play-scheduled)
still do not independently establish the missing audio-offset sign/unit
convention; no timing constant was changed. The input guide's subtraction rule
matches the implemented input offset. No additional host mismatch was proved
by these spot checks; they are not exhaustive API sign-off.

The BF-16 Xcode probe did establish a concrete failure: URL+hash, hash-only and
URL-only locators for one BGM produced two rows (`[easy, expert]`, `[hard]`).
`completeSong` used the same key equality, so its discovery could exclude the
hash-only difficulty. Promote BF-16 to P2 and select it before speculative
atlas-allocation changes: it affects the explicit all-difficulties download
requirement, not just row presentation. Use known URL/hash bridges scoped by
engine, not title guesses. Verify stable row IDs, metadata replacement,
offline grouping and persistence boundaries before shipping.

Seventh bounded discovery pass: rechecked result payload/index replacement,
playback interruption and startup-generation guards, selected skin/particle
preparation and online artwork. No new transactional or playback defect was
established by these spot checks. Earlier atlas decoding/base-crop allocation
risk remains unproven; no allocation-to-failure or device probe was attempted.
Select BF-15 next: the confirmed cover identity loss prevents cached hash-only
artwork and can reuse URL-cached old covers. Preserve grouping/row identities;
test actual artwork transport with isolated caches and no production requests.
BF-16 needs a grouping/migration diagnostic, not an incidental key rewrite.
The stack contract and physical timing/input checks remain gated.

Sixth bounded discovery pass: rechecked UIKit touch cancellation/coalescing,
host draw/audio/spawn limits, software frame budgets and effect preparation.
No new input/lifecycle defect was established in that spot check. It confirmed
BF-12 across actual resource and queued-work paths: errors there misleadingly
blame one callback's operation count. Some allocation failures also use that
same error. Select this confirmed diagnostic defect next; retain numerical
budgets and control flow, distinguish resource/work limits from allocation
failure and true callback execution limits, and test real throwing paths.
BF-11 remains a higher-impact but unproven memory-risk diagnostic; this pass
adds no crash evidence or authority for an arbitrary tighter atlas limit.
Stack and physical timing/input dependencies are unchanged.

Follow-up resource lookup discovery during verification: runtime references
retain URLs but discard advertised resource hashes, and online resource reads
use the ordinary ten-minute URL response cache. Required hash-only locators
are rejected before cache lookup. The public
[SRL contract](https://wiki.sonolus.com/custom-server-specs/misc/srl) permits
omitted URLs and calls for immediate reuse of cached matching hashes. This is
a new concrete compatibility gap, not a reason to reopen URL path resolution.

| ID / priority | Finding and evidence | Scope / confidence | Next bounded action / dependency |
| --- | --- | --- | --- |
| BF-14 / P1 — runtime/offline unit verified | Runtime references and saved resources retain optional URLs and per-role hashes. The collector preserves distinct identities at one URL; verified Downloads objects can serve online playback. | Integration regressions reproduced rejected hash-only engine data and wrong offline music bytes before their fixes. All 375 non-cached tests, normal build and independent post-fix review pass. | Re-triage the whole backlog. Online catalog artwork remains separately tracked as BF-15; do not claim all app SRL support. |
| BF-15 / P2 — verified | Catalog/detail artwork now retains the cover hash and keys its loading task by the full resource reference. Verified response-cache and Downloads hits support hash-only covers; changed hashes cannot reuse stale URL bytes. | All 74 catalog/download/history tests, normal build and independent review pass. Row IDs/grouping are unchanged; these are transport and identity checks, not rendered-image measurements. | Re-triage across the backlog; no production-server or device request was needed. |
| BF-16 / P2 — verified | Known URL/hash aliases now connect BGM references for catalog grouping, all-difficulty discovery and offline rows. Existing row IDs survive added aliases; splitting a group reserves its old ID for the original first chart. | Pre-fix execution produced two rows for one BGM. All 377 non-cached tests, normal build and independent review pass after incremental merge correction. Stored results and download manifests retain their existing per-level keys. Real-server prevalence is unmeasured. | Re-triage the broader API/performance/intro backlog. No title-only inference joins resource-bearing charts; a missing bridge remains insufficient evidence of identity. |
| BF-17 / P2 — verified | Particle tint preparation now throws a descriptive preparation error instead of substituting original pixels. Declared variants fail level preparation; incidental failed lookups return nil without caching or charging budget. | All 378 non-cached tests, normal build and independent review pass; cached SEKAI/SIF/22/7 assets still prepare through Metal. No memory-pressure event was induced and the phone effect report's cause is not established. | Re-triage. Earlier atlas allocation and physical effects remain separate open checks. |

Re-triage selects BF-14 ahead of further diagnostics/resource polish once the
verified BF-12 unit is complete. Silent stale chart/engine
data and broken hash-only resources have greater gameplay/compatibility reach
than the remaining error text or unproven allocation-growth follow-ups.

BF-14 first bounded implementation: cached URL resources no longer overrule a
new expected SHA-1. Each requested content identity has a separate in-flight
entry; identical hashes across URLs share one verified fetch. A matching old
URL-cache entry is rehashed and migrated without another download. Immutable
hash hits bypass age/forced metadata refresh only after verification; wrong
fresh bytes fail without entering the content cache. The existing 256 MiB
response-cache quota counts both URL and hash entries. Hash-only low-level
misses never invent a URL. This does not add a cache-negative shortcut or
change the ten-minute metadata policy.

The production-loader regression failed on all five resource classes:
`RunSomeTests/2B20ECC5-D17B-4C95-A6D6-087AEEB33296.txt`.
Both focused regressions pass:
`RunSomeTests/D86614F8-44B5-4802-B2D0-DFA8AF55EE87.txt`.
Independent review found no actionable issue; its suggested legacy-hit
no-fetch case was added, along with different-hash/unhashed in-flight isolation.
All 373 non-cached simulator tests passed:
`RunSomeTests/4680E010-8C3E-48F0-B028-7737B7CC42B3.txt`.
Normal build passed: `BuildProject/BuildProject-Log-20260930-033532.txt`.
Tests use an isolated response cache and URLProtocol fixtures; no server crawl,
real chart re-download, cached full-chart replay or physical test was needed
for this transport/integrity unit.

BF-14 second bounded implementation carries optional URLs through runtime
references and manifests, preserving existing URL-bearing records. The
collector retains distinct content identities at one address. Online playback
can reuse verified SHA-1-named Downloads objects; it does not scan the entire
legacy hashless library. Missing/corrupt hash-only resources fail without an
invented URL, and failed downloads do not publish a new manifest.

Independent review caught two regressions in the new offline resolver before
shipping: cover lookup read unrelated declared-hash payloads, and URL-only
lookup could choose a different hashed record at the same URL. Exact declared
hashes now resolve metadata-only, with payload verification restricted to
genuinely hashless legacy candidates. URL-only references prefer the exact
unhashed record. The mixed-identity regression reproduced engine JSON being
returned as music: `RunSomeTests/BF6ABD75-4DCA-45BE-85B5-87DEC354C325.txt`.
The cover read-count regression passes; final independent review is clean.
All 375 non-cached simulator tests passed:
`RunSomeTests/987E9503-D79A-4FE6-BC14-1E4F1F79A83D.txt`.
Normal build passed: `BuildProject/BuildProject-Log-20260930-034955.txt`.
These are isolated transport fixtures, not valid-media decoding or
acoustic/rendering evidence. No production-server requests, full-chart replay
or physical-device tests were performed for this unit.

Re-triage boundary: finish this data-integrity unit, then reconsider the entire
backlog. Record the newly discovered artwork and grouping limitations as
BF-15/BF-16 instead of expanding this patch into a catalog identity rewrite.

BF-15 verification: the production artwork loader regression covers changed
hashes at one URL despite an old URL-cache entry, unchanged row identity,
uppercase hash-only cache hits, Downloads-to-online reuse, local-file checksum
validation and corrupt/missing hash-only content without any invented request.
Both list and detail use the full reference as SwiftUI task identity; cancelled
tasks still cannot publish their image. The existing background image decoder
and placeholder behavior are unchanged. All 74 catalog/download/history tests
passed: `RunSomeTests/3EE210A6-7999-4083-8DFE-F2C9E8DF5992.txt`.
Normal build passed: `BuildProject/BuildProject-Log-20260930-035409.txt`.
Independent review found no actionable issue. Test payloads exercise transport, not codecs;
no production request, whole-chart replay or device check was performed.

BF-16 implementation uses a union of known URL/hash aliases, scoped by engine;
offline rows additionally remain scoped by normalized server origin. Hash-only
identities no longer fall back to title/artist. Different declared hashes with
no URL bridge and different engines stay separate. A known URL+hash record can
bridge URL-only and hash-only records, including transitive URL aliases. Title
equality alone cannot prove that two resource-bearing levels share audio.

Merge tests cover every starting locator, later bridge discovery, unchanged
row IDs, deterministic difficulty ties, repeat pages, engine separation and
same-ID metadata replacement that splits a group without duplicate SwiftUI
IDs. The actual song-download fixture now mixes three locator forms, saves
all three difficulties, rereads manifests into one offline row and still
fetches the shared payload once. Manifest filenames and result keys remain
per-level and unchanged; no saved library migration or deletion occurs.

An initial full-regroup implementation cost 34.1–36.6 ms for a page addition
to 1,000 songs × five difficulties, versus 1.03–1.11 ms for the prior URL-only
algorithm. That regression was caught before shipping. Cached per-song alias
keys now let additions reuse old groups/search indices; only removal of an
existing chart's identity alias requires the full split-capable regroup.
The repeated six-sample paired Debug simulator probe measured 3.34–3.63 ms
versus 1.03–1.32 ms for the legacy algorithm. At 100 songs it measured
0.77–0.84 ms versus 0.57–0.71 ms. Both paths add the same 20 new rows, with
fixture construction excluded and execution order alternated. This is a
bounded page-merge CPU comparison, not device scrolling/FPS evidence; the
model already performs merge work in a detached task. The residual alias
overhead remains explicit rather than claiming a general speed improvement.

All 75 catalog/download/history tests pass after the incremental revision:
`RunSomeTests/54305AFB-287F-41E2-B46E-8297F641CB89.txt`.
Independent read-only review found no actionable issue. All 377 non-cached
simulator tests passed:
`RunSomeTests/E25A1241-F73B-47BE-92C0-0A415CA4FC64.txt`.
Normal build passed: `BuildProject/BuildProject-Log-20260930-040742.txt`.
No production request, full-chart replay or physical check was needed.
Re-triage after this unit, rather than optimizing
alias matching to parity with the less-capable URL-only algorithm.

BF-12 verification: a new regression failed before implementation on stream,
draw, loop, audio queue, effect clip and software-size errors:
`RunSomeTests/08B1937A-DACE-4674-AB3E-78722DE8686D.txt`.
Resource/work guards now report their subsystem, allocation/preparation failures
have a separate description, and interpreter execution exhaustion still names
the callback. Existing software pixel-work and ZIP entry-limit fixtures also
assert the correct messages. Numerical budgets and short-circuit allocation
order are unchanged. All 371 non-cached simulator tests passed:
`RunSomeTests/B4CAA129-6935-4BCE-BE54-BE1B928FDF26.txt`.
Normal build passed: `BuildProject/BuildProject-Log-20260930-032515.txt`.
Independent review found no actionable issue. No allocation-to-failure,
cached full-chart replay or physical run was performed for error remapping.

Fifth bounded discovery pass: checked event-time mapping/stopped-clock guards,
result index/payload replacement, online page invalidation, offline list reads,
per-engine preference restoration, and resource URL resolution. No new timing,
transaction or pagination defect was established by those source spot checks.
The apparent leading-slash URL concern is not a defect: the public
[SRL contract](https://wiki.sonolus.com/custom-server-specs/misc/srl) explicitly
resolves those paths against the server address, not the domain root; retain
the existing behavior. These checks are not native/audio or full API sign-off.

| ID / priority | Finding and evidence | Scope / confidence | Next bounded action / dependency |
| --- | --- | --- | --- |
| BF-13 / P2 — fixed | Offline and Played Songs now store visible rows, instead of recalculating filtering, localized sorting and engine-key selection for every SwiftUI read. | The same bounded 1,000-song / five-difficulty Debug simulator probe improved from 19.6–20.5 ms for paired unchanged reads to roughly 0–0.001 ms, at timer resolution. 69 focused tests, normal build and independent review pass. This is not phone frame-time evidence. | Song/filter/engine mutations invalidate rows, including same-ID metadata refreshes and deletion. Search stays session-only and preferences remain per engine. Actual filtering and library refresh costs remain; no network-cache changes. |

Re-triage selects BF-13 ahead of error-message polish (BF-12) and continued
unproven atlas-growth diagnosis (BF-11): measured repeated catalog work affects
an existing user-reported area and has a small semantics-preserving fix. No
new timing/input defect displaced it in this pass. Physical alignment and the
stack ABI remain gated; neither is silently treated as completed.

BF-13 verification: the new model regression covers stored difficulty/sort
preferences on two engines, session query preservation, switching engines with
different ranges, filter mutations, repeated reads, same-ID replacement,
deletion and recreation with saved settings but no saved search. All 69
CatalogTests/OfflineStoreTests/ResultStoreTests passed:
`RunSomeTests/9FE8C958-8E4C-4EFA-BACF-6E0F83E2C09A.txt`.
Normal build passed: `BuildProject/BuildProject-Log-20260930-031810.txt`.
Independent read-only review found no actionable issue. Performance evidence
comes from the identical before/after Xcode snippet, not a timing assertion in
the behavioral test. Fixture creation, actual filter changes, SwiftUI layout,
image loading and physical scrolling were outside that read-only measurement.
No full runtime replay or device run was needed for this list-model unit.

Re-triage: BF-13 is complete within that scope. Remaining concrete queued work
includes BF-12 resource-budget diagnostics; BF-11 atlas/base-crop risk remains
an open diagnostic. Make another bounded cross-area check before choosing the
next implementation, with gameplay-affecting evidence able to displace either.

Fourth bounded discovery pass: independently rechecked imports/defaults,
prepared-state restart, spawn/callback sequencing, spawned-entity restrictions,
judgment arguments, scheduled audio compensation and stream interpolation
against the public [archetype schema](
https://wiki.sonolus.com/engine-specs/resources/engine-play-data-archetype),
[play lifecycle](https://wiki.sonolus.com/engine-specs/play-lifecycle/overview),
[Spawn](https://wiki.sonolus.com/engine-specs/functions/spawn),
[Judge](https://wiki.sonolus.com/engine-specs/functions/judge),
[PlayScheduled](https://wiki.sonolus.com/engine-specs/functions/play-scheduled)
and [StreamGetValue](https://wiki.sonolus.com/engine-specs/functions/stream-get-value).
No new concrete legal-engine mismatch was established in that pass. These were
source/contract checks, not new execution tests, native parity evidence or a
substitute for the deferred stack ABI and physical batch.

BF-11 preparation diagnostic: an Xcode snippet constructed a single 128x128
white PNG (3,868 encoded bytes) and a selected particle effect with distinct
declared colors. Production preparation retained 65,536 / 524,288 / 2,097,152
RGBA bytes for 1 / 8 / 32 colors respectively, before any renderer exists.
Observed preparation durations were approximately 45 / 46 / 173 ms in this
single Debug simulator probe; first-use overhead was not controlled, so these
are not comparative performance claims. The largest retained payload was only
2 MiB, not an allocation-to-failure or OOM experiment. Combined with the
source path, this establishes selected-color expansion before the Metal check,
not an observed crash or the cause of the user's phone slowdown.

The fourth pass selected a bounded **selected tint preflight**: compute the
required unique `(sprite index, color)` images and actual padded crop sizes,
then apply explicit preparation accounting before creating any tint surfaces.
Do not charge repetition count as image count, reject unselected sprites, or
silently omit/resize a requested effect. Reuse the documented renderer budget
policy where appropriate instead of inventing a smaller limit. Prove exact
boundaries, duplicate variants, unused large entries and failure-before-tint
allocation using small injected budgets. Earlier encoded-atlas decode remains
a separate risk to investigate; tint preflight must not claim to bound it.
No higher-confidence gameplay/API defect displaced this work in that pass.

The selected tint preflight is now implemented. It plans every unique declared
index/color variant before calling the tint factory, charges actual padded crop
pixels and preserves the existing selected-resource behavior. It shares the
Metal per-image accounting helper with a separate 128-million-byte tint-cache
limit. This is explicit host policy, not a protocol limit or process-RSS bound.
An incidental internal lookup cannot bypass the cache budget; all engine-declared
variants either warm successfully during preparation or fail preparation.

Tiny 31/32/63/64-byte fixtures verify exact boundaries, duplicate references,
particle repetitions, unused huge sprite entries, padded dimensions and zero
tint calls when the complete plan is over budget. Numeric dimension tests use
no large allocations. Three focused checks passed:
`RunSomeTests/8C4BC150-935D-4ED7-ABDC-BC67EB6A4D28.txt`.
All 369 non-cached simulator tests passed:
`RunSomeTests/3209759D-5596-43CF-9AE6-E9C00727BF2A.txt`.
Independent review found one stale test count after adding a fourth unused
sprite; corrected to four and explicitly asserted that it remains unprepared.
No production-code finding remained. The initial run's assertion failure was a
fixture update error, not a before-fix behavioral reproduction.
Actual cached SEKAI, SIF and 22/7 resources still prepare successfully through
the new preflight and Metal path: 20,341,844 / 265,796 / 7,440,064 uploaded RGBA
bytes, unchanged by repeat preparation. No server requests were made. Normal
build passed: `BuildProject/BuildProject-Log-20260930-031236.txt`.
Full-chart cached replays, physical gameplay and allocation-to-failure were not
rerun for this accounting-only unit.

Re-triage after this bounded unit: return to a cross-area discovery pass before
selecting another implementation. Atlas decode/base-crop risk remains open,
but does not automatically take precedence over reported timing/input/frame
pacing, catalog behavior or other known API gaps. Compare impact, evidence and
dependencies globally; do not continue resource refinements just because that
code is open. The stack contract and physical-device gates remain unchanged.

| ID / priority | Finding and evidence | Scope / confidence | Next bounded action / dependency |
| --- | --- | --- | --- |
| BF-12 / P3 — fixed | Audio, particle, entity, rendering and queued-work limits now identify their actual subsystem instead of blaming callback execution. Allocation/preparation failure is distinct from exceeding a budget. | Before-fix regression reproduced misleading messages; all 371 non-cached tests, normal build and independent review pass. Actual OOM failures were not induced. | Bounded diagnostics unit complete; numerical limits and normal behavior unchanged. Re-triage selects the new BF-14 hash-aware resource gap, not further message polish. |

Third bounded discovery pass covered random-function ranges, BPM/time-scale
mapping, scheduled effect pause/resume and sprite preparation/upload.
[Random](https://wiki.sonolus.com/engine-specs/functions/random) and
[RandomInteger](https://wiki.sonolus.com/engine-specs/functions/random-integer)
endpoints agree with the public contracts; a suspected
paused-voice recycling issue was ruled out by the native `playing` semantics
and existing sample-position regressions. No new audio alignment correction
was supported. These spot checks are not exhaustive API coverage.

| ID / priority | Finding and evidence | Scope / confidence | Next bounded action / dependency |
| --- | --- | --- | --- |
| BF-10 / P2 — fixed | Skin preparation shares exact atlas crops, so Metal's image-identity cache reuses their uploads. Actual cached assets now prepare SEKAI 175 sprites / 136 unique images, SIF 17 / 11, 22/7 15 / 13. | Alias regression failed before and passes after; all 367 non-cached tests, normal build and independent review pass. SEKAI nominal RGBA payload falls from 18,752,256 to 15,662,844 bytes; not a resident-memory/frame-latency measurement. | Bounded unit verified below. Per-sprite transforms/UVs and per-presentation lifetimes remain independent. Aggregate allocation accounting is separate BF-11. |
| BF-11 / P2 — Metal and selected tint guards implemented; atlas/crops open | Metal applies the existing software numeric budgets before conversion/upload: 8 million pixels / 8192 per side per image and 128 million aggregate RGBA bytes. Selected tint variants now preflight their whole plan before the first tint allocation with the same per-image limits and a separate cache budget. | Tiny injected-budget checks and all 369 non-cached tests pass; independent review found no remaining production issue. No memory-pressure crash was reproduced. | Earlier atlas decode/base-crop allocation remains a separate diagnostic, subject to global re-triage. These are host limits, not Sonolus resource constraints or process-RSS bounds. Metal accounting spans its persistent cache; software accounting spans one render call. |

BF-10 is selected as the demonstrated cross-engine redundancy with a narrow,
semantics-preserving fix. BF-11 remains a separate diagnostic rather than an
excuse to introduce arbitrary compatibility restrictions. Existing physical
timing/input questions remain gated; stack ABI work remains deferred. Re-triage
after this unit instead of extending into atlas packing or shader redesign.

BF-10 verification: the initial regression failed both integer and fractional
crop identity/count assertions in
`RunSomeTests/BEFBDC10-584C-4C16-AF86-16A134104D02.txt`.
It now verifies alias image/UV reuse, separate transforms, distinct rectangle
pixels and no cross-presentation cache lifetime. All 367 non-cached tests pass,
including existing software/Metal fractional-atlas and compositing checks:
`RunSomeTests/501C94DE-E4FA-425D-955F-931332165EB9.txt`.
An Xcode snippet prepared actual cached assets through production decoding and
confirmed the unique-image counts above without server requests. The corresponding
SIF payload is 265,728 -> 198,400 bytes and 22/7 is 6,982,560 -> 6,776,512 bytes.
Normal build passed:
`BuildProject/BuildProject-Log-20260930-024957.txt`.
Independent read-only review found no actionable issues. Cached full-chart
replays and physical gameplay were not rerun for this immutable crop reuse.

Re-triage: investigate BF-11's resource-growth exposure next, using bounded
metadata/accounting fixtures rather than allocation-to-failure. Potential
process termination warrants diagnosis ahead of further crop/mesh tuning.
Establish which allocations occur before existing safety checks and whether
selected-resource aliases or unused entries affect them. Keep supported-resource
semantics and explicit host-budget policy separate; this is not authorization
to pick an arbitrary restrictive limit and declare general compatibility done.

BF-11 Metal verification: tiny 15/32-byte budgets exercise rejection, exact
capacity, repeated image reuse and repeated rejected uploads without charging
or caching. A roughly 64 KiB overwide image exercises dimension rejection
without a memory-exhaustion probe. Both focused tests passed:
`RunSomeTests/F55A7900-E335-40A4-AE60-8B33E8043614.txt`.
Actual cached engine preparation and repeat preparation succeeded, accounting
20,341,844 RGBA bytes for SEKAI, 265,796 for SIF and 7,440,064 for 22/7; repeating
preparation did not add charges. Selected tint payloads alone were 4,679,000,
67,396 and 663,552 bytes respectively, so these fixtures do not demonstrate an
excessive chart. All 368 non-cached tests passed:
`RunSomeTests/96D1D5ED-BD13-487B-B6C5-C542085EDCB7.txt`.
Normal build passed:
`BuildProject/BuildProject-Log-20260930-025617.txt`.
Independent read-only review found no actionable findings. Existing software
fallback remains; no silent texture omission or downscaling was added. Cached
chart replays, driver allocation-to-failure and physical tests were not run.

Re-triage: the earlier atlas/tint allocation path remains a memory-risk
diagnostic, not a completed requirement. Inspect encoded-image metadata and
selected crop/color expansion before further GPU optimization. Prefer evidence
from bounded accounting fixtures and retain the selected-resource boundary;
do not reject unused sprites merely to simplify a safety check. Full API,
conservative intro and physical timing/input verification remain open.

Second bounded discovery pass: catalog filtering/pagination, engine option
defaults, result metadata and persistence were inspected. No new defect was
confirmed in pagination invalidation or atomic result writes by this spot check;
that is not exhaustive coverage. New findings are recorded before implementation:

| ID / priority | Finding and evidence | Scope / confidence | Next bounded action / dependency |
| --- | --- | --- | --- |
| BF-08 / P2 — bounded optimization verified | Catalog filtering now computes matching minimum rating and localized sort label once per song. The same generated 1,000-song/five-variant simulator probe improved difficulty sorting from 303–312 ms to 13.5–14.2 ms, title from 59–63 ms to 16.8–17.9 ms, and artist from 20–21 ms to 10.6–10.8 ms. | Shared online/offline filter path; output-equivalence regression, 68 focused tests, normal build and independent review pass. Synthetic simulator timings do not establish the cause or magnitude of phone scroll jitter. | Re-triage below. Remaining repeated whole-catalog passes and actual phone scrolling stay separate; no persistent keys, cache invalidation change or catalog/index redesign. |
| BF-09 / P2 — fixed | New result score-mode labels use the same effective preference/default and display-label resolvers as runtime and modified-option summaries. Legacy generic overrides and standard identifiers such as `#COMBO` are honored. | Normal completion/persistence regression failed in both cases before the fix and passes now. All 117 focused decoding/results/catalog tests, normal build and independent review pass. Numeric gameplay scoring is unchanged. | Unit verified below. Old records remain untouched because they lack the original effective option values; return to cross-area discovery. |

BF-08 is selected because the measured main-actor pause affects ordinary catalog
use across engines, while BF-09 is limited to historical labels under legacy
preferences. Existing gameplay/compatibility questions remain open with their
evidence and device/contract dependencies; neither finding justifies a guessed
timing correction. Re-triage after this bounded optimization.

BF-08 verification: the reference-equivalence regression covers both English
and Japanese title selection, all three sorts, empty and nonempty queries,
no matches, empty variants, fractional rating bounds, difficulty subsets,
equal-key ID ties and reversed input order (96 comparisons). All 68
Catalog/OfflineStore/ResultStore tests passed, including append-order and
pagination regressions:
`RunSomeTests/015003B4-5865-49A7-A414-A4FCB3E260DD.txt`.
Normal build passed:
`BuildProject/BuildProject-Log-20260930-023814.txt`.
Independent read-only post-fix review reported no actionable findings.
No production-server requests, cached gameplay replays or physical-device
checks were needed for this pure catalog transformation.

Re-triage: BF-09 is the next bounded reproducible correctness candidate. It
affects saved result interpretation without a device/stack dependency, whereas
remaining catalog refresh/index redesign lacks a newly demonstrated requirement
and the major physical timing/input questions remain gated. Reproduce the
result-save mismatch before changing it; preserve the existing numeric scoring
and inspect whether other result labels share the same discrepancy. Do not
extend BF-08 toward perfect catalog performance before that cross-area step.

BF-09 verification: after correcting an optional-field access in the test,
`RunSomeTests/20D27B33-6A43-4EEE-8A25-FEA1A69B6667.txt` reproduced the legacy
override being saved as Flat while runtime option memory contained 1, and the
dedicated selection being saved as raw `#COMBO`. The regression completes and
saves six no-input engine plays, checking runtime memory, saved mode and saved
modified-option summary. Cases cover legacy generic values, dedicated values,
dedicated precedence, absent preferences, out-of-range and fractional choices.
Neighboring standard-option summaries already used the correct resolution path.
All 117 RuntimeDecoding/Catalog/ResultStore tests passed:
`RunSomeTests/DAFAAFE4-8ED5-4891-9912-D9C1D5C6055D.txt`.
Normal build passed:
`BuildProject/BuildProject-Log-20260930-024259.txt`.
Independent read-only post-fix review reported no actionable findings. This
tests persistence, not actual audio playback or engine score-formula parity.

Re-triage: BF-08/09's bounded fixes are complete. The next pass should return to
gameplay/API/resource discovery, comparing primary contracts and executable
behavior across those areas before selecting another implementation. Do not
extend this metadata fix into historical-data reconstruction or speculative
preference migrations. The existing stack ABI, conservative intro and physical
timing/input/rendering evidence gaps remain open; no new evidence in this unit
closes them or authorizes the deferred device batch.

This initial discovery pass inspected result persistence/history, offline
manifest lookup and cleanup, catalog pagination/prefetch, gameplay startup and
stopped-clock input, touch sampling, and Metal submission/completion handling.
It is source inspection plus existing-test review, not a full UI/performance
or physical-device validation. Findings below are recorded before fixing them.

| ID / priority | Finding and evidence | Scope / confidence | Next bounded action / dependency |
| --- | --- | --- | --- |
| BF-01 / P1 — fixed | `ResultStore.record` silently capped history at 500, removed older timing payloads, and thereby also dropped old-only songs from `playedSongs`. The previous audit described this limit, but the user did not request automatic deletion. | Confirmed by the 501st-play regression; automatic eviction is now removed. | Verification below closes this unit. Previously deleted data cannot be reconstructed. |
| BF-02 / P1 — frame dependence fixed | Velocity now uses consecutive OS samples, including UIKit's coalesced history, independently of display time and the mapped chart clock. No assumed 240 Hz floor or synthetic stationary frame sample remains. | The frame-phase regression failed before and passes now, alongside coalesced hold-to-flick, lifecycle and clock-separation checks. Native estimator parity and contribution to reported early/late bias are not established. | Keep single-sample-after-long-hold uncertainty explicit; physical flick verification remains deferred. Do not add guessed calibration to force a timing distribution. |
| BF-03 / P1 — interruption and stopped-clock paths fixed | An audio-session interruption previously left the engine interpreting input without a scene change; it now requires an explicit restart. A separate local-player regression confirmed that a stopped music clock still allowed notes to be judged. Normal engine frames now freeze during paused/waiting playback, without aborting the attempt. | Actual local AVPlayer pause/resume regression failed before the fix and passes afterward, including the EOF-tail exception. Pool regressions cover pending taps, held releases and rejected new presses. All 359 non-cached tests, normal build and independent review pass; not a physical or network-stall measurement. | Re-triage below selects BF-05 measurement next. Exact transition-time input discrimination and physical behavior remain deferred. |
| BF-04 / P2 — fixed | Catalog and lookup reads now recover valid manifests individually and report unreadable records in the Offline UI. Strict manifest inventory, whole-song deletion and asset cleanup still fail closed on unknown references. | Mixed valid/corrupt regression verifies visible songs, download status, offline runtime-bundle preparation with zero network requests, warning lifecycle and byte-for-byte preservation. No current user file was shown corrupt. | Bounded recovery unit verified below. Damaged metadata is retained; no automatic deletion or speculative reconstruction is performed. |
| BF-05 / P2 — batch status fixed; catalog cost separate | The five-difficulty status check now reads one fresh inventory and verifies each shared content-address/hash pair once. The same 1,000-manifest/8 MiB-object probe improved from 331–339 ms to 76–79 ms. | Confirmed improvement on song-detail status checks, not per scrolling row. Separate catalog refresh remains about 79–81 ms. Read-count/invalidation regression, 67 focused tests, normal build and independent review pass. | Keep large-library catalog construction and single-lookup scan cost as lower-priority follow-ups; no persistent memoization or relaxed integrity checks. This does not establish the cause of the reported phone scroll hitch. |
| BF-06 / P2 — recovery fixed | A `.error` completion now triggers the existing software fallback on the main actor, once per renderer, instead of leaving Metal active after failed GPU work. The frame slot is released first; normal successful completions do not dispatch an actor task. | Injected background completion reproduced missing fallback before the fix. Strengthened regression passes with actual local audio/runtime advancement, preserved playback generation, software redraw and detach/reattach. All 362 non-cached tests, normal build and independent review pass. No real GPU fault was induced. | Physical GPU-failure/performance behavior remains deferred; this is recovery-path coverage, not a diagnosis of curved-hold slowdown. Re-triage below selects BF-07 next. |
| BF-07 / P2 — recovery fixed | Model-lifetime loss/reset observation now cancels the attempt, retires media-bound objects and disables Start while services are lost. Reset only restores availability; explicit Start recreates BGM/effect audio and reasserts session activation. | Isolated notification regression failed before the fix and now passes with fresh object identities and an advancing local player. Pending-activation cancellation/restart also passes; all 364 non-cached tests, normal build and independent review pass. Not an actual media-server reset. | Real service/device recovery remains in the deferred physical batch; do not kill host services for this diagnostic. Return to broader discovery/triage rather than extending this lifecycle unit indefinitely. |

BF-01 is selected over speculative timing/render changes because it has a
deterministic irreversible data-loss path, no evidence dependency, and a small
verification boundary. BF-02 and BF-03 are next high-impact diagnostic
candidates, not invitations to assume either is the cause of reported timing
bias. Catalog generation/cursor guards and per-engine preference paths yielded
no additional confirmed defect in this bounded pass; they are not certified
complete. Existing API/stack, intro-classification and physical-verification
items below remain open alongside this queue. Re-triage after BF-01 rather than
expanding history storage into an unrelated redesign.

BF-01 verification: after correcting an initially incomplete test fixture, the
new boundary regression failed with 500 retained summaries and the oldest
timing file missing. It now passes with all 501 summaries, original timing
payload, score/duration, replay metadata and same-ID deduplication preserved
after reopening. Cleanup only removes superseded same-ID payload versions
after the replacement index is atomically committed. All 35 focused
ResultStore/Catalog tests pass (summary
`873C6DCF-FA24-4DB0-A37A-02C9F18C63C6`), the normal build passes at 01:12,
and independent post-fix review found no actionable issue. Gameplay and
physical-device suites were not rerun for this persistence-only change.

Re-triage: BF-02 is the next bounded diagnostic choice because it directly
affects flick input and can be investigated with deterministic event sequences,
without a phone or new chart files. BF-03 remains a separate high-impact
diagnostic item; BF-04–06 remain queued. Very-large-history index cost is also
unmeasured; measure it before redesigning storage, rather than restoring
silent deletion as a performance shortcut.

BF-02 diagnostic: running the production `EngineTouch` implementation in Xcode
with samples at 1.000 and 1.010 seconds returns 10 units/s with no intervening
frame, but 24 after `nextFrame(at: 1.008)` or a delayed delivery following
`nextFrame(at: 1.020)`. Thus the sensitivity is not limited to out-of-order
timestamps. The [public touch contract](https://wiki.sonolus.com/engine-specs/play-blocks/runtime-touch-array)
defines OS event times, per-update position deltas and velocity components,
but not a velocity estimator. Simply reverting to the preceding event time
would reintroduce averaging a first flick over an entire stationary hold;
the existing hold-to-flick regression makes that tradeoff explicit. Keep this
finding open rather than presenting a guessed constant as a timing fix.

Re-triage after this bounded diagnostic: investigate BF-03 interruption
handling next, since it has a documented OS event and can be exercised with
synthetic notifications independently of the unresolved velocity estimator.

BF-03 interruption verification: after correcting the generated fixture's
required configuration field, the regression demonstrated that `.began` left
the model in `.playing`, did not invalidate its generation, and allowed
another runtime input update. The fix observes the
[audio interruption notification](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification),
using the active SDK's typed `.began` value. It handles notification delivery
on the main queue before the next input frame, removes the observer on stop
or destruction, and does not save a partial result or auto-resume on `.ended`.
This follows the existing backgrounding policy, without changing timing
calibration or normal buffering behavior.

Two regressions cover active-engine stop, pending off-main activation cleanup,
background notification delivery, invalid/ended notifications, generation
invalidation, observer teardown, and explicit restart through an advancing
audio clock. All 352 non-cached simulator tests pass with no skips or failures
(`RunSomeTests/8EA7FD44-9351-4761-AB5C-9EBA604F00B0.txt`); the normal build
passes (`BuildProject/BuildProject-Log-20260930-012805.txt`). Independent
post-fix review found no actionable issue, including after strengthening the
restart check. The seven cached-chart workloads were not rerun for this
model-lifecycle change, and no physical-device tests were run.

Re-triage: BF-02 remains the highest-confidence unresolved gameplay defect.
Its next bounded step is to check actual UIKit/coalesced sample semantics and
exercise an event-based estimator against both delayed delivery and a first
flick after a stationary hold. BF-03's ordinary-stall question remains separate;
BF-04's corrupt-library recovery is the next confirmed non-gameplay defect.
BF-05–07 remain diagnostic backlog items, not newly expanded requirements for
closing the interruption fix.

BF-02 fix: UIKit's
[coalesced touch history](https://developer.apple.com/documentation/uikit/getting-high-fidelity-input-with-coalesced-touches)
is captured during event delivery, preserving the main contact's identity.
The history includes the final delivered sample, so it is not appended twice;
nil/empty history falls back to the main touch. Begin/end flags apply once per
batch. No predicted touches are used. Raw OS uptime determines velocity, while
each sample's mapped chart time remains the judgment timestamp. Rendering only
clears per-frame deltas/velocity; it does not advance the sampling baseline.

The new frame-phase regression failed with 20/24 units/s instead of 10 for
identical samples and with 24 instead of 100 for a measured 1 ms interval
(`RunSomeTests/BB7B4B47-189B-4A26-886C-99BDB3881ED4.txt`). It now passes.
Two further regressions cover recent coalesced motion after a long hold,
frozen/remapped chart timestamps, short tap/release preservation, contact-ID
reuse, equal timestamps and no-history fallback. The old hold-to-flick test now
supplies an actual stationary sample instead of treating a frame as proof of
stationarity. All 355 non-cached simulator tests pass with no failures or skips
(`RunSomeTests/956803CF-4C73-40FB-B0FC-CA70758A98AD.txt`). Independent
post-fix review found no actionable defect.

Final integration verification: all seven cached probes passed in the original
September 30 01:35:23 run, completing at 01:46:35. The response observer expired
after 300 seconds, but the verified live simulator process was not restarted.
The completed `Test-OpenRhythm-2026.09.30_01-35-23--0400.xcresult` bundle
reports 7 passes, no failures/skips, on the iPhone 17 Pro iOS 26.5 simulator.
Together with the non-cached run this is 362 passing tests. The normal build
passes (`BuildProject/BuildProject-Log-20260930-014703.txt`). These cached
lifecycle/contact/restart probes are not physical flick or native-estimator
parity checks; no physical-device tests were run.

Information limit: when only one movement sample follows a long stationary
hold and UIKit supplies no intermediate samples, only the long-interval
average is known. That average may not cross a flick threshold until another
sample arrives. The old frame-derived estimate did not resolve this unknown;
it guessed motion onset from renderer timing. Neither these tests nor the
public Sonolus velocity-component contract establish native-estimator parity
or physical-device flick behavior. That verification remains deferred, and no
causal claim about the user's early/late distribution is made.

Re-triage after fixing the confirmed frame dependence: BF-04's corrupt-manifest
library failure is the next confirmed, broadly affecting defect with a bounded
reproduction and no device/contract dependency. BF-03's ordinary-stall input
question and BF-05–07 remain queued for diagnosis; no additional failure in
those paths was established during this touch-input unit. Preserve the
remaining API/stack and physical-verification gates rather than extending
this unit into undocumented native filtering behavior.

BF-04 recovery: `catalogSnapshot()` returns valid songs plus per-file issues,
which the Offline view displays separately from a whole-library failure.
Each issue includes a readable explanation, filename and original error
domain/code. Empty libraries, all-unreadable records and directory-enumeration
failure remain distinguishable. Lookup/status and runtime preparation no
longer fail because of an unrelated malformed record. Reads never delete,
quarantine or rewrite that record, and a repaired file is re-read on refresh.

Destructive callers still use strict `manifests()`: whole-song deletion fails
before changing any manifests if references cannot be inventoried, and garbage
collection does not treat resources referenced by unreadable metadata as
unreferenced. This intentionally does not add an automatic damaged-record
purge or relax the pre-existing shared-resource safety policy.

Two regressions cover mixed valid/corrupt files, per-record diagnostics,
visible catalog/model state, offline bundle preparation with a fail-on-network
stub, strict deletion refusal, preservation of both manifests and potentially
referenced object bytes, refresh after repair, warning removal in history mode,
and empty/all-damaged/enumeration-failure distinctions. The synthetic music
bytes are checked for preservation, not decoded or played. All 66 focused
OfflineStore/Catalog/ResultStore tests pass
(`RunSomeTests/48968286-B2D2-4006-91B2-200DAF9758F7.txt`), the normal build
passes (`BuildProject/BuildProject-Log-20260930-015036.txt`), and independent
post-fix review is clean, including the added runtime-bundle coverage. The
shared engine and physical suites were not rerun for this offline-only unit.

Re-triage: investigate BF-03's remaining ordinary-stall input behavior next,
with controlled player state and no guessed timing correction. Its gameplay
impact warrants diagnosis before optimizing BF-05's unmeasured library I/O.
BF-06/07 and the existing API/intro/device items remain open; a successful
partial-library read does not certify those separate areas.

BF-03 stopped-clock follow-up: a generated local audio file and injectable
AVPlayer construction reproduce the issue without remote requests or a phone.
After `pause()`, media time remains fixed, but the old model resolves a
synthetic input (`RunSomeTests/17BBC861-9990-4384-8086-1F714D8ADEB7.txt`).
The active SDK's `AVPlayer.h` distinguishes requested rate from advancing
playback: waiting can retain a nonzero desired rate. The fix therefore uses
`timeControlStatus == .playing`, with an explicit monotonic EOF-tail exception.

Normal engine callbacks and engine presentation remain at their previous
frame during a stopped clock. Effect voices are paused without draining queued
commands. Startup preparation still runs, and buffering does not change the
attempt's phase or generations. `engineFrame` reports whether it consumed the
input batch; only a consumed frame clears per-frame touch flags. Existing
contacts continue receiving real movement/releases while new begins are
rejected, preventing both stuck holds and unbounded accumulation of paused
presses. Pending pre-stop taps survive until consumption; later moves cannot
revive a rejected press. This is a delivery-time gate, not exact discrimination
of an OS event on either side of a media transition. It does not adjust timing
calibration or establish the cause of reported early bias.

The first post-fix tail assertion exposed a test setup error: `start()` does
not restart an already-playing attempt. Correcting the fixture to stop first
made the paused/resumed/tail check pass
(`RunSomeTests/A8286B51-044F-4C2E-B3F4-205100223F03.txt`). The separate contact
pool check passes too. All 359 non-cached simulator tests now pass, without
failures or skips (`RunSomeTests/A87F1178-D9BB-431C-8F46-E76AAA77CD87.txt`),
and the normal build passes
(`BuildProject/BuildProject-Log-20260930-020635.txt`). Independent post-fix review
found no actionable issue, including effect-pause ownership and retained input
lifecycle. The seven cached-chart workloads were not rerun for this model/input
delivery change. This unit covers server/native-engine gameplay; the explicitly
synthetic basic-lane helper is not evidence of native-engine behavior. No
physical-device check or live network-buffering experiment was performed.

Next re-triage choice: measure BF-05's offline-library I/O before changing it.
It can affect every catalog refresh for a large downloaded library and aligns
with the reported list-performance concern, whereas BF-06/07 are currently
unreproduced exceptional failures. Do not skip resource integrity validation
or introduce a stale cache just to improve the measurement. API/stack,
intro-classification and deferred physical checks remain open; the crawl
continues independently and is not a reason to wait on this diagnosis.

BF-05 measurement: an Xcode simulator snippet generated 10, 100 and 1,000
manifests (five variants per song), sharing an 8 MiB SHA-256-addressed resource.
Three sequential checks at each size returned complete downloads correctly.
Five-variant status took 18.9–22.7, 42.1–45.5 and 330.7–338.8 ms respectively;
separate catalog construction took 0.7–3.9, 7.2–7.8 and 84.0–89.6 ms. Setup was
outside the measured intervals, generated files were removed afterward, and no
server requests were made. These are local simulator observations, not device
performance targets or proof of UI jank. Call-site inspection narrows the
status path to song details/playback lookup; the list does not run that status
check for every row. The earlier broad catalog-responsiveness suspicion must
not be presented as a confirmed scroll diagnosis.

Select a bounded batch-status fix over BF-06/07's unmeasured exceptional paths:
read manifests once per `containsAllDifficulties` call and validate each shared
content-address/expected-hash pair once within that synchronous actor operation.
Discard all memoized results when it returns, so a later corruption, repair,
download, deletion or changed manifest is observed on the next call. Keep
standalone lookup, strict destructive inventory and playback validation intact.

BF-05 verification: before batching, the new regression counted 250 manifest
reads and five shared-object reads where one check needs only 50 and one
(`RunSomeTests/0C98BE7B-9598-428F-8A7C-EA3A98BDBF2D.txt`). It now passes with
those exact bounds. Additional assertions cover URL aliases, discovery failure
without I/O, same-length corruption and repair between calls, contradictory
hash declarations on the same object, changed metadata and removed difficulty
records. Integrity memoization keys include both object name and expected
SHA-1, not just the remote URL or file size. The stored-data reader dependency
allows deterministic read counting; production still reads the actual bytes.

Repeating the original snippet after the fix produced status times of 4.4–7.4,
9.4–10.3 and 76.1–78.7 ms for 10/100/1,000 manifests. Catalog construction
remained separate at 0.8–1.5, 6.9–7.3 and 79.4–80.8 ms. No persistent cache
was introduced. All 67 OfflineStore/Catalog/ResultStore tests pass without
skips/failures (`RunSomeTests/CAEF1C83-0611-4409-970C-73B03E26E000.txt`),
the normal build passes (`BuildProject/BuildProject-Log-20260930-021432.txt`),
and independent post-fix review found no actionable issue. Gameplay/cached
engine workloads and physical-device checks were not rerun for this unit.

Re-triage: do the bounded BF-06 asynchronous GPU-error propagation diagnostic
next. A failed GPU command currently has no route to the existing software
fallback; this has a clear inspection/injection boundary and can affect visible
gameplay. BF-07 media-services reset remains a separate lifecycle investigation.
Do not turn the successful BF-05 batch into an open-ended indexing/cache redesign;
its remaining full-inventory cost is recorded, not declared solved. The
broader API, intro, timing and deferred physical requirements remain open.

BF-06 diagnostic/fix: the active SDK's `MTLCommandBuffer.h` defines `.error`
as aborted execution and exposes optional error details. Previously the draw
completion handler released its in-flight slot but never examined that status.
After extracting the same completion path for injection, a background `.error`
left the Metal layer/display link active
(`RunSomeTests/99B42561-53D0-448F-9347-88D23CFA5D06.txt`). The initial fixture
needed an explicit UInt-to-Int conversion for the SDK error enum before this
runtime regression could execute.

Failed completions now count separately from successful GPU timing samples,
retain a readable explanation plus available original domain/code, and dispatch
recovery to the main actor. Weak references, renderer identity checks and
once-per-renderer notification protect against late/duplicate completions.
Fallback removes the failed Metal layer and replaces its display link, without
changing the engine, touch pool, playback generation or music. Nil error
metadata still triggers recovery. Successful frames retain the original
diagnostics path without main-actor task creation.

The strengthened integration regression now passes
(`RunSomeTests/A2A30959-3ED2-4C58-8CCA-DC4F41518AA7.txt`): it starts generated
local audio, injects failure on a background task, verifies the same playing
runtime advances through software display frames, and confirms reattachment
does not restore failed Metal. Independent post-fix review found no actionable
issue. A separate duplicate/nil-error/metric-separation check passes too. All
362 non-cached simulator tests pass without skips/failures
(`RunSomeTests/5F1EBD47-2D8C-4C3F-BC1C-A80719B10FD4.txt`), and the normal
build passes (`BuildProject/BuildProject-Log-20260930-022219.txt`). The seven
cached-chart workloads were not repeated for this completion-handling change.
No GPU hang, real resource fault, physical-device check or remote chart request
was induced by this diagnostic.

Final review noted a bounded test limitation: `Task.yield()` is not a guaranteed
barrier for both queued duplicate-failure deliveries. Nil-error handling and
metric separation are verified; the once-only guard is also confirmed by
source inspection, but this is not deterministic scheduler-interleaving proof.
Record that limit rather than expanding this recovery unit into a concurrency
test-framework redesign before re-triage.

Re-triage: investigate BF-07 media-services loss/reset next. The active SDK's
`AVAudioSessionTypes.h` explicitly requires reinitializing audio objects after
the media server restarts; the current interruption handler alone does not
provide that recovery. Diagnose with isolated notifications and object-lifetime
checks, not by killing the host audio service or resuming deferred device tests.
Remaining catalog cost, intro classification, API/stack contract and physical
timing/rendering requirements stay open. Do not expand BF-06 into speculative
GPU fault generation or renderer tuning before that next bounded diagnosis.

BF-07 diagnostic/fix follows the active SDK's loss/reset notifications and
[Apple QA1749](https://developer.apple.com/library/archive/qa/qa1749/_index.html):
reset invalidates media-bound objects and must not trigger automatic activation.
The isolated-notification regression first showed continued playback, unchanged
generation and retention of the original effect controller
(`RunSomeTests/23F2160D-FF16-4361-8EC5-010A3D99E2C6.txt`). This reproduced a
missing host response, not an actual operating-system media failure.

The observer now lives with the model, so reset while Ready is not missed when
the attempt-specific interruption observer has been removed. Loss/reset calls
the existing stop path to invalidate callbacks, seeks, input and pending
startup, then releases the model's player/effect-controller references. The
immutable bundle and prepared-BGM lease/URL remain available for reconstruction.
Start is unavailable between loss and reset. Reset does not allocate/start new
playback: explicit Start recreates audio, and the existing serialized session
activation reasserts category/active state. Haptic startup already recreates its
backend. A service event while preparation is incomplete also prevents new
media objects from being constructed until availability returns.

Two regressions now pass
(`RunSomeTests/AE92CD90-003F-4F18-9DF8-E84ACF1D3D87.txt`): active loss on a
background notification, blocked Start, reset without autoplay, fresh player
and effect-controller identity, advancing audio after explicit restart, reset
without a preceding loss while Ready, and a reset while session activation is
blocked. The already-running system activation call cannot be retroactively
cancelled; queued release and generation guards prevent its stale continuation
from seeking or playing. Independent post-fix review found no actionable issue.
All 364 non-cached simulator tests pass without skips/failures
(`RunSomeTests/9C766AA6-0C63-42AF-AB6C-DE5D781F8B5A.txt`), and the normal
build passes (`BuildProject/BuildProject-Log-20260930-023028.txt`). The seven
cached engine workloads were not rerun for this model-lifecycle change.
These fixtures use local generated music and an empty effect set; they do not
simulate invalid system audio handles or certify post-reset hit-sound playback
on a physical device.

Re-triage: the initial BF-01–07 implementation units have now been addressed,
with their explicit measurement/physical limits retained. Do a new bounded
cross-area discovery pass before selecting another fix: compare catalog/list
main-thread work against the separate offline-inventory cost, recheck remaining
play-mode resource/default contracts, and inspect results/settings persistence
boundaries. Record newly supported findings first, then rank them against
existing intro/API/timing/performance follow-ups. The stack crawl stays
independent; neither it nor the deferred phone batch closes the wider audit.

## Current verification order — reaffirmed September 27, 2026

September 29 priority update: defer the 14 stack operations and their upstream
clarification for now. Continue the non-stack audit, implementation and
simulator verification; the stack contract is not a blocker for that work.
This is not a claim that the remaining non-stack requirements are complete,
nor permission to post the draft or resume physical-device testing.

September 29 stack-fixture search: the user subsequently requested a real
chart that uses `StackInit`/`StackGet` to help resolve the contract. Seven
cached engine files reduce to three unique engines (LLSIF, 22/7, Next-SEKAI);
none contains a stack node. Bounded public code searches found declarations
and wrappers, including the header bundled with Sirius, but no verified
gameplay consumer or usable chart. This is not proof that no such chart
exists. Details and evidence limits are in COMPATIBILITY.md. No song-server
crawl or reference-client/device execution was used.
Follow-up searches for stack-frame/pointer functions found no verified
consumer either: official compiler hits are metadata and the additional
public web-player hit explicitly leaves these operations unimplemented.
The chart-fixture request remains open, not completed by these negative hits.

September 30 scope update: the user explicitly authorizes a slow, cached crawl
of all chart data on 22/7, Project SEKAI and LLSIF to continue the stack search,
and authorizes a dedicated crawl subagent. Requests may run in parallel across
servers, but must remain serial within each server. The implementation uses
a persistent queue/cache with randomized 60–120-second request spacing and
retry backoff. The two milkbun catalogs share their host's rate limit; SEKAI
can advance in parallel. Scope is catalog metadata, every chart difficulty's
level data, and associated engine play data, not BGM, artwork or other media.
Engine bytes are reused by verified content hash while retaining their chart
associations; scans distinguish callback-reachable calls from orphan nodes.
The user explicitly reaffirmed the 60–120-second pace after discussing a
two-minute minimum. Following 25 passing offline tests, independent review
and a successful five-request probe, the full crawl started September 30 at
05:00:39 UTC as detached PID 40431. It resumed the same dated cache at
`tmp/cached-stack-crawl-20260930`; the PID/start event is retained in
`events.jsonl` and `worker.log`, and `report.json` is the read-only progress
summary. The initial catalogs advertise 28, 96 and 483 pages respectively;
full chart-data collection will take days at this pace. The corpus search is
in progress, not complete. Verify the process command/start time before
stopping or resuming it; neither a stale PID nor the lock-file path proves a
live worker. See `scripts/README.md` for safe cache/status/resume instructions.
This does not authorize stack implementation based on guesses,
upstream messages, or physical-device testing.

September 30 19:57 UTC read-only checkpoint: PID 40431 was verified live with
the expected command after the session interruption. All initially queued
catalog pages have been fetched. Completed/pending chart-data tasks are
22/7 278/272, LLSIF 208/1,708 and SEKAI 123/9,512. Three engine variants have
been scanned with no stack calls; no chart stack hits have been found so far.
SEKAI pages 427–445 reported 481 pages instead of the 483 reported elsewhere;
the report flags that non-atomic enumeration, so it must not be called an
exhaustive snapshot. One truncated response recovered on retry; no unresolved
failures were reported. Across 1,217 logged requests, no same-host interval
was below 60 seconds. This checkpoint made no network requests and did not
restart the independent worker. It does not complete the corpus search.

Per the user's latest direction, postpone real-device testing until Sonolus
API coverage is complete, then perform the outstanding physical checks in one
large batch. Do not request phone unlocks, install or launch development builds
on physical devices, or run incremental device checks before that gate unless
the user explicitly asks for a specific device issue to be investigated sooner.
The previous pending unlock request is superseded; a connected or unlocked
phone alone does not reopen device testing.

The pending live audio-clock device check is deferred with the rest of the
batch, including after the user's earlier unlock confirmation. Do not retry
that launch or continue other queued device checks in the background. Continue
API implementation and simulator validation without waiting for the phone.

Continue the API contract checklist, implementation gaps and synthetic
conformance tests using simulator tests and builds. Select the next actionable
item using the breadth-first guidelines above; API edge cases do not
automatically outrank higher-impact gameplay or data-integrity findings.
The gate is closure of the API contract gaps tracked in COMPATIBILITY.md, not
merely passing the sampled engines or the current test suite. Collect remaining
physical checks into the batch as implementation proceeds.

Current batch status: deferred; the API gate has not been met. In particular,
the 14 unimplemented stack functions and remaining semantic conformance gaps
must not be waived to resume phone testing. Simulator audio-clock investigation
can continue without reopening the physical-device queue.

Before scheduling the batch, explicitly review the remaining API checklist and
record its closure. Keep each deferred device check tied to its originating
request, so batching does not drop earlier timing, input or performance reports.

Keep the physical checks below open and label them deferred, not passed or
blocked on an immediate phone unlock. Existing device evidence remains useful
but does not substitute for the eventual batch. The stable-build push
authorization is unchanged; deferred physical validation must be disclosed,
and no unmeasured latency improvement should be claimed.

The eventual device batch must cover the accumulated requests together:
audio/display alignment and timing controls; close/coincident multitouch,
flicks and holds; hit-effect rendering; dense and curved-hold performance
(including “shake it!” Hard 18); intro preservation; and repeated starts,
restarts and audio interruptions. Record the tested build and results for
each check. A user-requested early device check is an exception for that
specific issue, not permission to resume the rest of the device queue.

Correction to the September 29 non-stack audit: the per-delivery touch gate
shipped in `ed27b682` was incorrect, and the previous independent approval is
retracted. A stationary contact must continue to invoke `touch`: Next-SEKAI
evaluates hold ticks and traces there, including when a finger was already
held before the input window opened. Treating "input event" as only a fresh
UIKit delivery skipped those evaluations. Continuous dispatch is restored
without fabricating a new press, movement or timestamp.

The earlier 327-test run passed but did not establish this behavior: its new
counter test encoded the mistaken assumption, and its cached contact workload
supplied samples every frame. A new held-before-window regression failed
before the correction. Six focused checks now pass, including “shake it!”
Hard 18 with actual pooled contacts and 6,705 stationary frames; successful
hold ticks during those frames are required, as are dense/sparse equivalence
and restart determinism. The normal build passes at 22:32. Independent review
of the correction found no actionable issue. The subsequent full simulator
run finished at 22:49 with all 329 compiled tests passing and `TEST FINISHED`
confirmed. Its summary also enumerated five newly edited audio tests as
"No result"; those were not in that run's binary and were run separately
below. The observer timeout did not restart the original test process.
No physical-touch or frame-rate improvement is claimed.

Temporary-memory intro follow-up (September 29): fixed stage calculations
can now use explicitly initialized callback-local scratch values. The safety
proof follows read-before-write dependencies through shared graph nodes and
lazy branches, without relying on undefined initial values or carrying
initialization between callbacks. Persistent writes and time/random-dependent
calculations remain ineligible. Analysis cost is bounded even when dependency
sets grow. Two original regressions failed before the fix and passed after it;
the model test covers both useful skipping and transform-change rewind.
Independent review of the final implementation and adversarial tests found no
actionable issue. Broader classification and device verification remain open;
this does not implement or depend on the deferred stack operations.
The initial final-validation attempt was not green: the 23:23 run completed 331
non-cached tests with 309 passing and 22 failing tests (34 assertions), all in
audio-dependent intro/clock checks. The three scratch-analysis tests pass.
Logs show audio queues unable to start (`kAudioQueueErr_CannotStart`, -66681),
and local music fails to advance. Simulator reboot and restarting its isolated
audio helper did not recover playback. Two existing intro/clock tests also
failed with the parent classifier restored as a control; the pending classifier
was then restored. The normal build passed at 23:32, but pushing remained on
hold. The session-startup follow-up below subsequently recovered the blocked
checks; the earlier focused green run was not substituted for a current pass.
No host audio settings were changed and no physical-device test was performed.

Audio-session startup follow-up (September 29): the app previously launched
independent detached activation/deactivation tasks for a process-wide session,
with no ownership across song models, and discarded activation errors. A
previous model's delayed cleanup could deactivate a newer song. Session calls
now use one off-main serial queue and per-model leases. Activation is completed
before seeking can prepare player I/O, and failures stop startup with a
human-readable message plus the original diagnostic domain/code. Generation
checks still prevent a stopped/restarted request from starting playback.
Restart retains its model's lease; ordinary stop releases it, and model
destruction releases an abandoned lease automatically.

Five regressions cover overlapping owners, pending activation/release order,
failed activation ownership, user-visible startup failure and model lifetime.
Independent review caught the initial missing destruction cleanup; its new
regression failed without cleanup and passed afterward. Final independent
re-review found no actionable issue. All 336 non-cached simulator tests now
pass at 23:44, including the previously blocked intro and
live audio/display/input-clock checks. The normal build also passes at 23:44.
The seven cached-chart probes also pass in the separate run completed at 23:56,
including full-chart/restart checks for Eleventh, 光, 22/7, SIF Custom Charts
and all three “shake it!” workloads. All 343 tests have therefore passed across
these two runs, without failures or skips. The original cached-test process
continued after the observer expired and finished normally; it was not restarted.
This fixes a concrete session-ordering/ownership gap, not acoustic alignment;
no judgment windows, input times, calibration or BGM offsets were adjusted.
Include rapid song-to-song transitions, abandoned restarts and audio-session
activation failures in the deferred physical batch; simulator ownership tests
do not certify acoustic continuity on the phone.

Scheduled-effect timing follow-up (September 29): voice allocation and prior
commands could consume time after the audio controller sampled the playback
clock. Reusing that sample delayed later starts/stops in a batch, including
loop-stop re-arming during buffering recovery. The controller now reads the
live chart clock immediately before each publication and checks for loops
that expired during setup before starting them. Resumed loops are re-armed
after graph startup/other voice work but before publishing unpaused samples.
No input timestamps, judgment windows, BGM mapping or calibration defaults
were shifted. Five new regressions failed before the fix and pass afterward,
including native PCM that advances 512 samples during voice setup and must
still start at sample 1024 rather than 1536. The fixtures exhaust the eight
prewarmed voices before injecting allocation work. Existing native buffering
and pre-resume stop-order checks also pass. Independent review found no
actionable issue. This removes stale batch-clock delay; it does not make the
clock read/publication atomic or establish physical alignment.
All 327 non-cached simulator tests pass after this scheduler change, including
native audio and live player/display-clock probes. The normal build passes
at 22:55. The seven cached engine-graph tests passed in the preceding 329-test
baseline; they do not exercise this audio controller and were not repeated
after the scheduler edit. No device tests or song-server requests were used.

The distribution-state Xcode preview was rendered and visually inspected on
September 29: dense data has jagged peaks using the default Swift Charts
palette, exact-zero data is centered, and empty and isolated-outlier states
remain readable. This verifies the results-plot presentation, not acoustic
alignment. The stack deferral does not imply all non-stack work is complete.

Resolved-sprite intro follow-up (September 27, 2026): fixed computed sprite
IDs now qualify for stage classification, with identity checked on every
emitted draw rather than inferred solely from literal graph nodes. All seven
draw families require an unambiguous standard stage ID; selected custom or
ambiguous sprites remain visible stopping conditions. Unselected custom
branches no longer disqualify an otherwise fixed stage draw. Missing resources
emit no draw. Every argument and later lifecycle callback still requires the
existing stability and side-effect proof. Three new regressions failed before
their fixes and now cover imported/prepared IDs, unsafe expressions, selected
branches, restart, actual intro advancement and transform-change rewind.
All 320 non-cached simulator tests pass at 12:48 and the normal build passes
at 12:51; the six cached-chart tests were not repeated. Independent review of
the final change found no actionable issue. General dynamic-stage safety and
physical verification remain open.
The subsequent full simulator run completed at 13:02 with all 326 tests
passing, zero failures or skips, and the final `TEST FINISHED` marker. It
includes all six cached-chart lifecycle/restart and repeated-contact checks
after the accumulated intro changes. The original process continued through
the observer's five-minute timeout and was not restarted. The final normal
build passes at 13:02. No device checks or song-server requests were used;
these integration results do not establish acoustic or physical parity.

Read-only entity-memory intro follow-up (September 27, 2026): prepared local
stage coordinates can now qualify for safe skipping through direct or shifted
reads. Entity Memory has no cross-entity alias; this is a conditional proof,
not a declaration that block 4000 is globally immutable. Every callback after
preparation must be read-only (or only draw fixed stage graphics), and any
possible writer disqualifies the archetype, including unselected branches.
Preprocess and spawn-order writes finish before the restart snapshot. Spawned
copies remain excluded from initial-decoration flags. Three regressions failed
before the change and now cover advancement to the first visible note, visual
rewind, writer rejection across all callbacks, shared proof nodes in both
traversal orders, independent entity values, other-entity writes, spawned copies
and restart restoration. All 317 non-cached tests and the normal build pass at
12:38; the six cached-chart tests were not repeated. Independent review found
no actionable issue. Shared/dynamic stage state and physical presentation
verification remain open.

Resource-query intro follow-up (September 27, 2026): fixed unary
`HasSkinSprite`, `HasEffectClip` and `HasParticleEffect` calls can now select
static stage layouts. Their availability sets are immutable for each prepared
runtime; restart retains them and a changed bundle/settings prepares a new
runtime. Resource IDs must still be proven fixed and side-effect-free; wrong
arity, mutable reads, drawing-valued arguments, randomness and writes are
rejected. Two regressions failed before the change and now pass, including
actual intro advancement and transform-change rewind. The gameplay checks
assert the present-skin branch's alpha and the absent-resource fallback alpha,
not only the skipped duration. All 314 non-cached simulator tests and the normal
build pass at 12:32; the six cached-chart tests were not repeated. Independent
review found no actionable issue. Unknown/dynamic stage classification and
physical presentation checks remain open.

Shifted-read intro follow-up (September 27, 2026): immutable stage coordinates
read via `GetShifted` now qualify for the same fixed-stage proof as `Get`.
The block must be a literal member of the existing immutable allowlist, the
call must have exactly four arguments, and every address expression must be
proven fixed and side-effect-free. Indirect pointers remain excluded because
immutable pointer storage does not establish an immutable target. Two new
regressions failed before the change, including gameplay stopping at zero
instead of the first visible note at 0.5 seconds. They now pass, and a later
stage-transform change still causes genuine simulation followed by rewind.
All 312 non-cached simulator tests pass at 12:26; the six cached-chart tests
passed in the preceding 316-test full run and were not repeated for this
classifier-only follow-up. Independent review found no actionable issue; the
normal build passes at 12:27. This broadens safe classification but does not
claim arbitrary dynamic-stage classification or physical startup parity.

Native scheduled-stop follow-up (September 27, 2026): effect voices now use a
native C PCM renderer with replaceable start/stop gates instead of a main-actor
timer. A queued silent-buffer prototype could stop precisely but could not
cancel an earlier stop when buffering required a later deadline; it was not
used in production. A three-slot atomic ownership exchange publishes complete
commands without render-thread locks, allocation, task dispatch or Swift calls.
Phase tracks emitted samples, including when an already-ended native loop must
resume after a chart-relative rebase. Independent review caught and helped close
a resume-order race: the rebased stop and unpaused state are now published
together. The original timer backend fails at sample 24,577 in the new regression.
All 35 focused audio-related tests pass at 11:54, including exact native PCM,
earlier/later replacements, coalesced pauses, reuse, stereo/rate conversion,
large-uptime host-timestamp gates and concurrent publication stress. The stress
test is not exhaustive race proof; slot ownership provides snapshot coherence.
A bounded 256-voice offline comparison measured roughly 0.09–0.10 ms median per
512-frame block for 97/4096-sample clips versus 0.08–0.09 ms for the old native
player; one-sample loops were about 1.02 ms versus 1.40 ms. These simulator Debug
measurements do not establish physical latency or full-game performance.
The 11:56 full simulator run completed at 12:05 with all 314 compiled tests
passing and the final `TEST FINISHED` marker. A voice-growth test added after
compilation was not part of those 314. That follow-up exposed a missed build
integration prerequisite: Objective-C ARC was disabled, invalidating the PCM
ownership assumptions and leaking native graph objects. ARC is now explicitly
enabled in both Debug and Release, with a compile-time guard. New lifetime
checks verify PCM survives caller/controller release and is released with the
graph; stereo growth checks verify existing phase and new voice deadlines.
The earlier ownership review is superseded by an independent review of the
actual build settings and lifetime tests, with no remaining actionable finding.
All 37 focused audio checks pass at 12:10 after the fix. Seven bounded checks
also passed under Thread Sanitizer at 12:09 with no reported races; the build
log confirms native `-fsanitize=thread` instrumentation. This is not exhaustive
race proof. The temporary sanitizer setting is restored and the normal build
passes at 12:10. The full rerun after the ARC fix then completed at 12:21 with
all 316 tests passing, zero failures or skips, and the final `TEST FINISHED`
marker. This includes the cached Eleventh, 光, 22/7 and “shake it!” lifecycle/
restart checks and the repeated-contact probe. The final normal build passes
at 12:22. The observer's five-minute timeout did not restart or invalidate the
still-running suite; completion was verified from the original run's artifacts.
This closes the native implementation's pending full-suite validation, not
acoustic alignment, hardware interruptions or arbitrary-engine compatibility.

Buffering-audio follow-up (September 27, 2026): buffering now uses the same
sample-preserving pause path as explicit debug pause. Previously a reserved
one-shot that became due between display frames could be stopped and replayed,
and active loops restarted from sample zero. Queued loop stops are now applied
before voices resume, preventing a brief restart of an already-stopped loop.
Three regressions failed before the fix, including native offline-rendered PCM:
the one-shot skipped ahead and the loop restarted instead of resuming at sample
512. They now resume at the expected sample and remain silent while frozen.
All 26 focused audio/pause-related checks pass at 11:21, including repeated
buffering, minimum-distance state, future reservations, and full 256-voice
capacity replacement. The normal build passes; independent review found no
actionable issue. The full simulator run then passed all 304 compiled tests at
11:32 with zero failures or skips and the final `TEST FINISHED` marker. The
separate native-stop capability probe was added after that run compiled and
has no result in it; it is not included in the 304.
These are reproducible client defects, not proof of the cause of the reported
intermittent sound in 光. Physical reproduction stays in the deferred batch.

Pure-lifecycle intro follow-up (September 27, 2026): the static-stage proof no
longer rejects an archetype merely because compiler-generated lifecycle
callbacks exist. Every present shouldSpawn/initialize/updateSequential/touch/
terminate callback must instead be proven fixed and side-effect-free. Drawing
is not a pure callback result, even in an unselected branch or a shared memoized
node. Mutable reads, writes, random values, spawned entities and other effects
remain disqualifying. Runtime visual-change and despawn safeguards still apply.
Three new regressions failed before the change; the model then stopped at zero
instead of reaching the first visible note at 0.5 seconds. All 25 intro checks
now pass, including true/false spawning, ignored nonzero returns, touch calls,
prepared despawn flags, transformed-stage rewind and dynamically spawned copies.
Independent review found no actionable issue. The 11:09 normal build passed,
and the full 11:09 simulator run completed at 11:18 with all 300 compiled tests
passing. The final report and TEST FINISHED marker resolved the observer timeout
without a restart. Three buffering regressions added after compilation have no
result in that run and are excluded from the 300. No new Project SEKAI startup
or physical-device improvement is claimed from these synthetic checks.

Clock-history follow-up (September 27, 2026): simulator traces reproduced a
client defect independently of the reported acoustic bias. Core Media supplied
host-relative affine anchors at zero; the history mistook those reference
origins for transition times and replaced prior mappings, changing an already
queued touch by roughly 2–9 ms in captured failures. History now stores its
validity boundary separately and never uses a new reference origin to rewrite
previously observed timestamps. Moving notification times can refine the
boundary inside the observation interval. Stopped or uncertain transitions use
the first changed observation; their exact physical transition time is not
claimed. Opt-in diagnostics retain that uncertainty bracket in bounded storage.

The investigation also found an incorrect future-anchor test assumption:
Core Media already extrapolates before a future reference anchor; it does not
wait for that anchor to start the timebase. A new assertion failed before the
fix and now agrees with a direct native-clock read. Regression coverage includes
the captured zero-origin sequence, repeated reads, discontinuities, invalid
boundaries, exact-timestamp ordering, nested parent changes and source swaps.
Twenty clock tests passed at 10:52; the added nested-source test passed at
10:54, and final boundary/debug-pause checks passed at 10:56. The normal build
passed at 10:57. The full 10:57 simulator run completed at 11:06 with all 297
compiled tests passing, including cached charts and live clock checks. Its
completed report and TEST FINISHED marker confirm success after the observer
timeout; it was not restarted. Three intro tests added after compilation have
no result in that run and are not included in the 297. Independent review
caught the exact-timestamp edge and it is fixed;
final follow-up review found no remaining actionable issue.

Native playback stalls/jumps are distinguished from uninterrupted wall-time
progression in the integration checks. Every moving native rate is still
checked against the requested speed, and input/player alignment and queued
history assertions remain strict. Neither calibration nor player timing is
adjusted to hide a failure. Physical audio/display alignment remains unverified
and deferred under the API gate.

Long-curve compatibility follow-up (September 27, 2026): removed the app's
undocumented 1,024-segment limit on individual curved draws. All six variants
can now use the remaining shared frame drawing budget, with no reduction in
the requested segment count. The existing 16,384-segment frame safety limit
remains explicit host policy, not a Sonolus API maximum. The new regression
failed before the fix and now preserves geometry/texture continuity at 1,025,
4,096 and 16,384 segments. Four focused simulator tests pass, including
1,025-strip Metal/software pixel comparisons and budget/reset checks.
Independent review found no actionable issue; the 10:35 normal build passes.
The full simulator run completed with 286/292 tests passing, including the
curve checks and all cached charts. Six live audio-clock tests failed because
audio did not advance; the run spanned an abnormally long wall-clock interval.
An isolated 10:33 rerun passed five unchanged, while debug-pause playback
reported a roughly 3 ms historical input-time remapping and a roughly 33 ms
elapsed-time mismatch. Its console also records audio I/O reconfiguration;
causality is not established. This is not a green full suite or stable push.
The curve unit is retained separately; timing tolerances and production
calibration are unchanged. Investigate the clock failure next. Physical checks
remain deferred, and neither phone performance nor the API gate is signed off.

Scratch-memory performance follow-up (September 26, 2026): Temporary Memory
now uses 4,096 dense value/epoch slots, eliminating per-access
dictionary lookups while preserving the previous callback-clearing behavior,
bounds, permissions and copy-on-write preparation snapshots. This is an
implementation optimization, not a newly inferred API default: the public
contract still leaves initial Temporary Memory values unpredictable.
The original sparse implementation remains available to tests.

Four focused synthetic checks passed on September 25, including epoch wrap,
snapshot isolation, callback/entity changes, out-of-range accesses, and exact
floating-point bit preservation. The six paired full cached-chart probes also
passed, including repeated contacts on “shake it!” Hard 18 and both other
cached engines. Independent review found no production defect and recommended
stronger presentation-state comparisons and symmetric timing order. Both are
now implemented and re-reviewed: runtime updates alternate adjacently before
rendering, and comparisons include transforms, background/HUD memory, exports,
accuracy score and the existing command/judgment/life snapshots.
The September 26 22:45 full simulator run passed all 291 tests with no failures
or skips; its completed report and TEST FINISHED marker confirmed success
after the result-request timeout, without restarting it. The 22:54 normal app
build passed. The revised paired probes show 5.0–10.6% lower mean runtime CPU
time, including 10.2% for the repeated-contact “shake it!” case; the exact
table is in COMPATIBILITY.md. These Debug CPU probes do not establish phone
frame pacing, audio alignment, complete API coverage or physical sign-off.

Intro-branch follow-up: fixed option/prepared-data selectors can now choose
stage drawings through If and all four Switch variants without unnecessarily
retaining the silent intro. All alternatives must be proven safe; mutable
selectors, drawing side effects in selector/case expressions and unknown or
unsafe branches still preserve it. Model regressions failed at a zero-second
start before the fix and now reach the first visible note at 0.5 seconds;
later visible transform changes remain protected in all five branch families.
Seven focused tests and the added nested/unreachable-unsafe branch cases pass.
Independent review found no actionable issue. The full 06:48 simulator run
passed all 289 tests with no failures or skips; its completed report confirmed
success after the observer timeout. The 06:53 normal build passed. The
stack-reference dependency and deferred physical batch are unchanged.
At that checkpoint, cached SEKAI stage archetypes were excluded by their
additional lifecycle/touch callbacks. The later pure-callback extension above
does not establish a SEKAI-specific startup improvement.

Stack evidence dependency: the public contracts still omit observable pointer
initialization, addressing and frame layout. COMPATIBILITY.md now lists the
specific independent evidence needed for all 14 stack functions, including
Temporary Memory aliasing, lifetime and bounds. This cannot be closed by
registering guessed implementations or writing tests against the same guess.
An authoritative specification, public implementation or legitimate reference
trace is needed. This dependency does not authorize earlier device testing.
Independent review confirmed that no interoperable subset is established by
the available contracts. The user has been asked for any authoritative
reference; no speculative stack code or external clarification request was
submitted. The goal remains unfinished.

Particle-selection follow-up: unused sprite crop bounds no longer prevent a
valid selected effect from loading. Only referenced sprites are cropped, with
original indices and fractional UVs retained; shared references reuse crops
and color-specific tints. Selected invalid references/bounds still fail. Five
focused simulator tests passed at 06:31, and final tint checks passed at 06:32.
Independent review found no actionable issue. The full 06:32 simulator run
passed all 286 tests with no failures or skips; its observer timed out but
the same run's completed report confirmed success. The 06:37 normal build
passed. Malformed JSON/atlases are still rejected, and physical checks stay
deferred. COMPATIBILITY.md now separates each resource family's implemented
selection/default behavior from remaining native-parity evidence.

UI-animation follow-up: engine values beyond the app's former +/-1024 endpoint
and one-hour duration limits are now retained. Easing overshoot is no longer
clamped. Judgment/combo completion waits use bounded cancellable timer chunks
to avoid overflowing Swift's duration conversion. Five focused simulator tests
pass at 06:20, including the regression that failed before the fix. Independent
review caught an intermediate-overflow case; the correction, actual task
cancellation and bounded combo-view snapshots pass in the final six-test
06:26 run. The full run passed 284 compiled tests, including cached charts;
the snapshot was added after that build and passed in the focused run instead.
The normal build passes, and follow-up review found no further concrete defect.
Physical presentation checks remain in the deferred batch.

API inventory follow-up: a pinned official function list now checks all 191
names through registration, reachable touch-path preflight, and dispatch.
175 entries execute valid smoke calls, 14 stack functions remain unimplemented,
and Paint/Print belong to non-play modes. The strengthened 06:15 simulator
regression and normal build passed. Argument errors now fail the probe rather
than masking missing implementation branches. This is not comprehensive
semantic or callback conformance; the 14 missing stack functions still keep
the API gate open. Their exact names
and required evidence are now listed in COMPATIBILITY.md rather than only
described as a general stack-compatibility concern.
Independent post-fix review found no blocker and mechanically matched all
191 argument counts to the pinned metadata, including repeated groups and
optional draw depths. Debug, stream and control-flow smoke cases can take
early-return paths; behavioral tests remain separate.

Particle resource follow-up: selected effects no longer silently substitute a
color or disappear when their color or sprite reference is malformed. Resource
validation reports the affected field before gameplay, while retaining finite
extended intervals. An initial `0...1` timing restriction rejected four cached
SEKAI probes and was removed: its hold effects use starts above one, supported
by the public Studio renderer. Synthetic tests now preserve those intervals,
including negative starts, across loop modes and all four cache modes. Five
focused simulator tests pass on the revision; independent review found no blocker.
The 05:56 full simulator suite passed all 281 tests, including the six cached
charts, with no failures or skips. The added long-duration rendering case and
normal build passed at 06:02. The timed-out observer did not require restarting
the full run; its completed report supplied the results.
No physical-device or song-server requests were used. This does not establish
that phone hit effects look correct; that check remains in the deferred batch.

Pagination-cache follow-up: prefetched pages now retain their request cursor.
Refetching a parent discards speculative descendants and rejects late responses
from the previous prefetch revision, including numbered pages. Prefetch stops
when a response reduces the remote page count. A failed page's Retry bypasses
stored data, and Refresh Songs explicitly starts a new chain if its cursor has
expired. Errors do not trigger automatic prefetch/restart loops. Forced reloads
still share an active network request for the same URL; they bypass stored
responses, not the server's lack of a cross-page snapshot guarantee.
Nine focused simulator tests passed at 05:38–05:39, covering these changes plus
stable existing row order, bounded look-ahead, and stale-search suppression.
These checks used local response fixtures, not song-server or device requests.
Independent post-fix review found no remaining release-blocking issues. Recovery
buttons have separate tap targets, and prefetch rechecks errors after suspension.
The 05:40 full simulator suite passed all 280 tests with zero failures or skips;
the 05:46 normal build passed. Xcode's observer timed out after five minutes,
but the completed result report confirms every test passed; it was not rerun.

Static-stage follow-up: intro analysis now recognizes unconditional stage
draws whose geometry uses fixed prepared Level Data, Level Option, Engine ROM,
or Entity Data through Get and deterministic arithmetic/easing. Reused graph
nodes and curved draws are supported. Mutable reads, randomness during drawing,
time-dependent conditional drawing, and dynamically spawned copies remain
protected. Fixed-selection branches are covered by the later follow-up above. Analysis
is iterative and bounded; inconclusive graphs retain the intro. A model test
now passes the prepared stage to the first visible note, while another confirms
that a different entity moving the stage forces rewind and preserves that event.
This expands safe classification, not a claim of optimal skipping for every
engine or physical startup verification.
Independent review found no soundness or work-budget issue. The September 25
05:22 full simulator run passed all 277 tests with no failures or skips; the
05:28 normal build passed. No device checks or song-server requests were used.

Sprite-resource follow-up: fractional texture bounds now retain their exact
sampling region instead of stretching the whole-pixel-rounded crop. Skin,
curved skin slices, and tinted particles share the correction. A one-texel
border preserves neighboring samples for linear filtering; integral crops
keep their existing fast path. The regression failed before the fix and now
passes for both simulator renderers, including atlas edges and subpixel-sized
rectangles. Independent review found no correctness issue. This establishes
whole-atlas sampling equivalence, not native Sonolus filtering parity; broader
resource conformance and physical verification remain open.
The September 25 05:07 full simulator run passed all 272 tests with no failures
or skips; the 05:13 normal simulator build passed. No device checks or
song-server requests were used.

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
reconstruction of data older builds never recorded. The former automatic
500-play eviction was removed by BF-01 on September 30: new plays preserve
existing history and timing payloads. Already evicted data cannot be recovered
by this fix, and older summary-only records remain without per-note charts.

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
2. General engine compatibility is not complete: stack-function ABI remains
   unimplemented; the finite remaining acceptance checklist in COMPATIBILITY.md
   separates actual API gaps from native parity and host policy. Do not reopen
   the older generic resource/callback wording without a specific rule or
   reproducer. DebugLog/DebugPause now have
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
   must have HTTP(S) URLs or valid cached hash identities; absent ROM remains
   supported. Both online
   and offline playback perform unsupported-function preflight. Downloads may
   still archive an unsupported engine, but cannot play it through basic lanes.
   Engine option categories are now decoded and rendered in their declared
   order, with runtime option indices and per-engine persistence unchanged.
   September 30 display follow-up: standard time units now render as `ms`,
   `s`, etc., without converting engine values. The new regression failed
   before the fix; all 79 RuntimeDecodingTests and the normal build pass.
   Independent post-fix review found no actionable issue; saved standard-option
   summaries are also covered by the unit-formatting regression.
   Standardized text follow-up: all 596 public English protocol labels are
   bundled offline with pinned revision and MIT attribution. Settings names,
   descriptions, categories, select choices and new saved option summaries
   resolve identifiers through that table; custom text and unknown future
   identifiers retain their fallback. Existing saved result text is not rewritten.
   This matches the current English app UI, not whole-app localization.
   The new integration regression failed before the fix. Packaging checks also
   caught and corrected an initially missing target resource; all 105 focused
   decoding/localization/results tests and the normal build now pass.
   Independent review verified the pinned text/license data, bundle registration
   and call sites, with no actionable findings.
   The same resource audit found effect ZIP filenames were incorrectly assumed
   to be UTF-8. They now honor legacy CP437 and CRC-validated Unicode Path
   metadata, with bounded parsing and duplicate decoded-name checks. Both
   regressions failed before the fix; independent review found no actionable
   issue. All 348 simulator tests pass across the 341-test non-cached run and
   seven cached-chart probes completed at 00:28; the normal build passes.
   The cached run continued after its observer timed out and was not restarted.
   Stored/deflate and existing archive size limits remain;
   ZIP64 follow-up now resolves bounded extended directory and entry fields,
   including independently optional sentinels. The new matrix failed before
   implementation. Independent review found no actionable issue; positive
   coverage includes externally generated seekable/streamed deflate archives,
   extensible metadata and directory signatures. Adversarial cases cover
   overflowing integers, bad offsets, truncated fields and retained safety
   budgets. All 345 non-cached tests and three cached engine-family checks
   pass, with a clean normal build. Other compression methods remain outside
   stored/deflate support.
   The shared gzip loader now decodes all concatenated members instead of
   silently truncating after the first, with cumulative size limits and later
   member validation. Split JSON/ROM and malformed-member regressions cover
   this confirmed resource-compatibility defect. Independent review is clean;
   349 non-cached tests, the cached 22/7 lifecycle/restart check and the normal
   build pass. This closes the bounded fix already in flight at the policy
   change; the next implementation choice follows a breadth-first triage pass.
   Dedicated note-speed/score preferences work inside those categories, and
   legacy controls now resolve/reset generic saved overrides consistently.
   Skin mode selection is now
   honored, but exact native rendering parity is not claimed. Unsupported
   functions are surfaced before music rather than assumed harmless. See the
   separate contract checklist; sampled engines do not prove arbitrary support.
3. Physical intro verification remains part of the deferred batch. The approved
   unchanged-initial-scene policy is implemented and passes cached SEKAI startup
   plus synthetic count-in/effect/input checks (BF-19). The previous requirement
   to stop on every unproven initial sprite is superseded. Input activation alone
   does not end skipping; unseen input resolution restores the original start.
   A non-input manager can draw semantic note imagery without input ownership;
   that classification is not guaranteed by the cached evidence. Unknown audio
   silence is never inferred from bgmOffset.
4. Full-chart no-touch runtime integration now passes on the physical device
   for four cached charts. Interactive playback, audio and display integration
   beyond those probes still need verification in the deferred device batch.
5. Physically verify the implemented manual visual/audio alignment control,
   independently of input-judgment adjustment. Passing simulator regressions
   and explicit sign/unit documentation do not certify acoustic alignment.
   Check calibration usability and alignment in the deferred device batch;
   resolve the public API's underdocumented audio-offset sign/unit convention
   without guessing a correction from the user's early/late distribution.
6. Independently establish stopped-clock transition precision and physical
   alignment in the deferred batch. The September 27 affine-origin history
   defect is fixed, independently reviewed and verified by the 297-test full
   simulator run. Exact stopped-transition timing is still bounded by
   observations, not independently established. Native player re-anchors are
   not corrected by arbitrary calibration or relaxed alignment tolerances.
   This limitation does not reopen device testing before the API gate.

The former native scheduled-stop full-suite item is complete: all 316 tests
pass after the ARC fix, with final normal build and independent review. Its
acoustic/hardware checks remain part of items 1, 4, 5 and 6 above. Do not infer
calibration from these checks. A bounded independent resource review on
September 27 found no new contract-supported defect; undocumented parity and
the stack ABI remain open. A public stack-contract clarification draft is
prepared locally; both stack implementation and upstream clarification are
deferred by the September 29 instruction. No issue has been submitted. Continue
the remaining non-stack work without waiting for approval on that draft.

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
