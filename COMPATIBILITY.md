# Compatibility is a contract, not a list of working songs

The 22/7 catalog failure was missed because integer-rated LLSIF/SEKAI fixtures
were treated as evidence for an integer protocol field. The public contract
allows a number. Merely adding a third engine would repeat that mistake.

For every public field/function, check its declared type, optionality, legal
callback/mode, value range, ordering, and observable side effects. Test these
independently of downloaded engine graphs. Then use cached real charts as
integration probes, including successful inputs and restart/buffering paths.

## Contract regressions now covered

- Media-service loss/reset is distinct from ordinary session interruption.
  Model-lifetime observers also cover prepared Ready models, invalidate startup
  and active attempts, and retire old BGM/effect controllers. Start is disabled
  while services are lost; reset never autoplays. Explicit Start reconstructs
  media objects from retained bundle data and the BGM lease, then reasserts
  session activation. This follows [Apple QA1749](
  https://developer.apple.com/library/archive/qa/qa1749/_index.html).
  Isolated-notification regression failed before the fix; active/Ready and
  blocked-activation regressions now verify new object identities and advancing
  local music after explicit restart. All 364 non-cached simulator tests, the
  normal build and independent review pass. No real media server was reset;
  post-reset physical audio/effect behavior remains unverified.

- Asynchronous failed Metal commands now reach the existing software fallback,
  not just synchronous encoding errors. Completion releases its frame slot
  before dispatching failure once to the main actor; weak identity-checked
  callbacks cannot replace another renderer. Music/runtime/input state survives
  fallback, and reattachment does not restore failed Metal. Successful frames
  need no actor task. Failed frames have a separate diagnostic counter and do
  not become successful GPU timing samples. Injected completion regressed
  before the fix; local-audio integration now verifies software display-driven
  advancement, plus duplicate/nil-error and metric separation checks. All 362
  non-cached simulator tests, the normal build and independent review pass.
  This does not reproduce a real GPU fault or certify device performance.

- Offline listing and lookup tolerate individual unreadable manifests while
  exposing per-file warnings in the Offline UI. Directory-enumeration failure
  remains a whole-library error. Strict inventory for deletion/garbage
  collection is unchanged, so unknown resource references cannot be silently
  dropped. Mixed valid/corrupt fixtures prove valid song visibility/status,
  zero-network runtime-bundle preparation, retained metadata/object bytes,
  deletion refusal, warning lifecycle and recovery after repair. Empty and
  all-unreadable libraries remain distinguishable. All 66 focused offline,
  catalog and history tests pass
  (`RunSomeTests/48968286-B2D2-4006-91B2-200DAF9758F7.txt`); normal build and
  independent review pass. This does not reconstruct damaged metadata or
  prove audio playback of the fixture's synthetic music bytes.

- Touch velocity now uses consecutive measured OS timestamps and positions,
  not display-frame times or an assumed 240 Hz sampling limit. UIKit's
  [coalesced history](https://developer.apple.com/documentation/uikit/getting-high-fidelity-input-with-coalesced-touches)
  is consumed during delivery under the original contact identity, including
  its final sample exactly once. Raw uptime determines speed; chart-mapped
  timestamps still determine judgments. Per-frame delta/lifecycle pooling and
  within-frame release velocity are retained. The frame-phase regression
  failed before the fix; three new regressions plus the updated stationary
  sample check pass, and all 355 non-cached simulator tests pass
  (`RunSomeTests/956803CF-4C73-40FB-B0FC-CA70758A98AD.txt`). Independent review
  found no actionable issue. The seven cached probes also pass in the original
  `Test-OpenRhythm-2026.09.30_01-35-23--0400.xcresult` run, which completed
  after observer expiry without being restarted: 362 total passes across
  both runs, no failures/skips. The normal build passes at 01:47. These probes
  retain their bounded lifecycle/contact/restart scope.
  If no intermediate samples exist after a long
  hold, only a long-interval average is known until another sample arrives;
  do not describe it as native Sonolus estimator parity or proof of physical
  flick recognition. No timing calibration or judgment window was changed.

- Audio-session interruption begins now stop both gameplay and audio even
  without a scene-phase change. Ready explains the interruption and requires
  an explicit restart; no partial result is saved and `.ended` does not resume
  automatically. Observer lifetime follows the attempt; generation guards
  invalidate pending activation/seek and old input, and deallocation removes
  the token. Generated-audio simulator regressions cover active engine input,
  pending activation, background notification delivery, invalid/ended events
  and explicit restart reaching an advancing player clock. All 352 non-cached
  tests pass (`RunSomeTests/8EA7FD44-9351-4761-AB5C-9EBA604F00B0.txt`), the
  normal build passes at September 30 01:28, and independent review found no
  actionable issue. This is not proof of physical interruption behavior or
  ordinary buffering-input correctness; media-services reset remains a
  separate audit finding.

- Process-wide audio-session ownership is serialized off the main actor.
  Each gameplay model owns a lease, so an old model's delayed cleanup cannot
  deactivate a newer song. This matters because
  [session deactivation](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:options:))
  can stop running audio objects; the active SDK also warns that activation
  is blocking. Activation now completes before the startup seek can prepare
  player I/O. Activation errors are reported, not discarded; stale-generation
  guards still prevent stopped requests from starting playback. Restarts keep
  their model's lease, while stop and destruction release it.
  Five regressions cover multiple owners, serial ordering during a pending
  activation, failed activation without phantom ownership, readable startup
  failure and deallocation of an abandoned restart. Independent review found
  the initial missing destruction cleanup. That regression failed without
  cleanup (`RunSomeTests/196AD755-09C8-40CF-9EC8-DD128180731F.txt`) and passes
  after it. Final independent re-review found no actionable issue.
  All 336 non-cached simulator tests pass in the final run
  (`RunSomeTests/34742835-D020-4699-A9DF-34604BB82DE5.txt`), including the
  previously failing intro/player-clock checks. The normal build passes
  (`BuildProject/BuildProject-Log-20260929-234433.txt`). All seven cached-chart
  probes also pass in the separate 23:56 completion
  (`RunSomeTests/2C185C53-84E1-43C4-A1A4-0BC088C433C2.txt`), including all three
  “shake it!” workloads, Eleventh, 光, 22/7 and SIF Custom Charts. The original
  process continued after observer expiry; its result bundle and
  `TEST FINISHED` marker confirm completion, with no replacement run.
  Thus all 343 tests pass across these two runs, without failures or skips.
  This does not establish acoustic/device alignment or justify an arbitrary
  timing correction.
- Intro-stage classification now tracks definite initialization for direct,
  literal-address Temporary Memory calculations. The public
  [Temporary Memory contract](
  https://wiki.sonolus.com/engine-specs/play-blocks/temporary-memory)
  gives unpredictable initial values, so the proof does not assume that our
  storage's zero-clearing policy makes an uninitialized read stable. Shared
  graph summaries record required prior writes and guaranteed writes; every
  callback starts with no guaranteed scratch values. Lazy branches cannot
  borrow initialization from an unselected path. Read-modify-write operations
  require the old value before operand evaluation, even if that operand writes
  the same slot. Persistent writes, random/time-dependent values and unknown
  addressing still prevent classification. Dependency-set processing shares
  the graph-work budget; exhausting it retains the intro.
  The original two regressions failed before the change and passed afterward:
  initialized scratch stages were previously rejected and retained the whole
  intro. The model case now reaches the first visible note, but still rewinds
  when another entity changes the stage transform. Further adversarial tests
  cover all direct RMW forms, fractional-address aliases, invalid/computed
  addresses, cross-callback state, lazy cases and growing dependency sets.
  Independent review found no actionable issue. This is not Stack* support,
  nor proof that all custom/dynamic graphics can safely be skipped.
  The initial 23:23 September 29 final-validation attempt was not green: it
  completed 331 tests, with 309 passing and 22 failing audio-dependent tests
  (34 assertions). All three scratch-proof tests passed. The completed result
  bundle is `Test-OpenRhythm-2026.09.29_23-23-27--0400.xcresult` in Xcode's
  DerivedData test logs; the observer timed out, but the original process
  finished and was not replaced while live. Audio queues report
  `kAudioQueueErr_CannotStart` (-66681), and player-clock tests cannot advance
  local audio. A simulator reboot and isolated audio-helper restart did not
  recover playback. The same two existing model/clock checks fail with the
  parent classifier restored (`RunSomeTests/664A9042-1050-4B1A-8FC0-453B3ADABF7F.txt`).
  The pending implementation was restored and the normal build passed
  (`BuildProject/BuildProject-Log-20260929-233252.txt`). This establishes an
  independent-of-classification validation blocker, not a passing audio result.
  The session-startup fix above subsequently recovered these checks, with all
  336 non-cached tests passing. Host audio settings remain unchanged.
- Scheduled effects translate deadlines using a fresh playback-clock read
  immediately before voice publication, after allocation or earlier commands.
  Loop setup cannot start an already-expired loop, and buffering recovery
  refreshes each surviving stop after graph startup/other resume work but
  before that loop resumes. Five regressions failed before the change and
  now pass: accumulated allocation delay, separate loop start/stop sampling,
  resume order, expired-loop recycling, and a native PCM deadline. The native
  test advances 512 frames during lazy allocation beyond the eight warmed
  voices, then requires output to start at frame 1024, not 1536. Existing
  native buffering and stop-before-resume tests pass too. Independent review
  found no actionable issue. No arbitrary calibration was applied. Read and
  publication are not atomic; acoustic/device alignment remains deferred.
  All 327 non-cached simulator tests pass after the scheduler change, including
  native audio and live player/display-clock checks; the normal build passes
  at 22:55 September 29. The seven cached graph probes passed before this edit
  and do not exercise the audio controller. No device or remote-song testing
  was performed.
- Normal engine frames now freeze while the music player is paused or waiting,
  rather than evaluating input repeatedly at one frozen chart instant. The
  model pauses effect voices, preserves the previous engine presentation and
  reports whether it consumed its touch batch. Startup preparation and the
  monotonic EOF tail remain separate. Existing contacts retain movement/end
  events until consumption; new begins are rejected while stopped. Stationary
  holds still receive callbacks on every advancing engine frame, not just when
  UIKit delivers a new event. The gate is based on playback state at delivery,
  not proven sample-exact discrimination at a pause/resume boundary.
  A real local AVPlayer pause reproduced a resolved note before the fix; the
  corrected regression verifies stopped frames, resume and EOF, with separate
  pending-tap/release/rejected-identity coverage. All 359 non-cached simulator
  tests and the normal build pass; independent post-fix review found no
  actionable issue. This does not establish physical-device
  alignment or behavior under an actual remote-media stall.
- Stationary contacts continue `touch` evaluation without new presses or
  timestamps. The September 29 per-delivery gate in `ed27b682` misinterpreted
  "input event" in the [input-system documentation](
  https://wiki.sonolus.com/engine-specs/play-lifecycle/input-system);
  the prior compatibility claim and independent approval are retracted.
  Public [Next-SEKAI note logic](
  https://github.com/Next-SEKAI/sonolus-next-sekai-engine/blob/03f0d6a0f583949fb2d66bae0b5fa8fad02b09d3/sekai/play/note.py)
  handles ticks and traces in `touch`, including held-before-window contacts.
  A new synthetic regression failed with the gate and passes after restoring
  continuous evaluation. Six focused checks pass, including a cached “shake
  it!” Hard 18 run with 6,705 genuine stationary pool frames, successful ticks
  during those frames, dense/sparse equality and restart determinism. The
  normal build passes at 22:32 September 29; independent correction review
  found no actionable issue. The earlier 327-test pass did not cover this
  scenario: a counter assertion mirrored the wrong assumption and cached
  contact tests delivered samples every frame. The subsequent full simulator
  run finished at 22:49 with all 329 compiled tests passing and the original
  process's `TEST FINISHED` marker. Five audio tests added to source while it
  ran were enumerated as "No result" rather than present in that binary; their
  separate red/green checks are described above. This is not physical input
  or frame-pacing sign-off.
- Intro-stage candidates can use fixed computed sprite IDs. The graph proof
  establishes stable, side-effect-free arguments and read-only lifecycle;
  the host separately validates each emitted draw's resolved sprite ID against
  unambiguous standard stage metadata. The shared gate covers all seven draw
  families. Selected custom/ambiguous graphics remain non-static, absent
  resources emit nothing, and unselected custom branches do not taint the
  rendered stage branch. Three regressions failed before their fixes and now
  cover prepared/imported IDs, unsafe expressions, branch selection, restart,
  gameplay advancement and visual-change rewind. All 320 non-cached tests pass
  at 12:48 September 27 and the normal build passes at 12:51. The six cached
  integration tests were not repeated for this change. Independent final review
  found no actionable issue; arbitrary dynamic-stage and physical parity remain
  unproven.
  The subsequent full simulator suite completed at 13:02 September 27: all
  326 tests passed, zero failures or skips, with `TEST FINISHED` confirmed in
  the original run's console. All six cached integration checks were included;
  assets were local and no song-server requests or physical tests were used.
  The final normal build passes at 13:02. This supersedes the outstanding
  cached-integration rerun for these intro-proof changes, not the API or
  physical verification gaps below.
- Entity Memory reads can qualify as fixed intro-stage expressions only under
  the whole-archetype read-only proof. Block 4000 is entity-keyed and unaliased;
  preprocessing/spawn-order changes precede the prepared snapshot, and all
  subsequent callbacks must be free of writes or other unproven side effects.
  A memoized read does not waive this condition for another writing archetype.
  Spawned entities never receive the initial-decoration flag. Three new tests
  failed before the change and now cover direct/shifted local stage reads,
  cross-entity isolation, writes in every callback and unselected branches,
  spawn/restart state, actual intro advancement and visual-change rewind.
  All 317 non-cached tests and the normal build pass at 12:38 September 27;
  the six cached-chart tests were not repeated. Independent review found no
  actionable issue. Shared memory and arbitrary dynamic-stage classification
  remain outside this proof.
- Resource-existence checks with fixed pure IDs qualify as constant expressions
  in intro-stage proof. The host's skin/effect/particle availability sets are
  immutable runtime inputs, unlike streams. Exact unary arity is required;
  memoized drawing results and mutable/random/writing ID expressions stay
  unsafe. New regressions failed before the change and now verify selected and
  fallback stage alpha, intro advancement and restoration after a later stage
  transform change. All 314 non-cached tests and the normal build pass at 12:32
  September 27; the six cached-chart tests were not repeated for this follow-up.
  Independent review found no actionable issue. This is not a general proof of
  arbitrary dynamic-stage safety or physical presentation parity.
- Static intro-stage proof accepts `GetShifted` over the same literal immutable
  blocks as `Get`, with exact arity and fixed, side-effect-free address arguments.
  The shift changes only the index, not the target block. `GetPointed` remains
  excluded: immutable pointer storage can still point into mutable memory.
  Regressions cover all four allowed blocks, mutable/drawing/random/writing
  arguments, malformed arity, actual first-visible-note advancement and rewind
  after another entity changes the stage transform. Both new tests failed
  before the fix; all 312 non-cached tests pass at 12:26 September 27 and the
  normal build passes at 12:27. Independent review found no actionable issue.
  The six cached-chart tests passed in the preceding full 316-test run and were
  not repeated for this follow-up. Unknown/dynamic stage policy stays open.
- Native scheduled effect stops no longer depend on a main-actor timer. A C PCM
  source renderer gates samples against native host timestamps (sample time for
  offline rendering), using three preallocated command slots and lock-free
  atomic ownership transfer. Deadlines can move later after buffering without
  losing phase or leaving old queued interruptions. The original timer backend
  fails the new regression at sample 24,577. A reviewer-found resume race is
  fixed by arming while paused and publishing the rebased end with unpausing.
  All 35 focused audio-related tests pass at 11:54 September 27: exact cutoffs
  within render blocks, earlier/later stops, expired-gate recovery, coalesced
  pause/resume, generation-safe reuse, stereo, 44.1-to-48 kHz conversion, and
  host-time kernel boundaries at large uptime with invalid-timestamp rejection.
  Concurrent stress is supplementary evidence, not exhaustive race detection.
  A bounded 256-voice offline Debug comparison measured 0.09–0.10 ms median for
  97/4096-frame clips (old native player 0.08–0.09 ms), and 1.02 ms for one-frame
  loops (old 1.40 ms). No physical/frame-rate guarantee is inferred. Independent
  review initially missed the target's disabled ARC setting. The full suite
  passed 314 compiled tests at 12:05, but a subsequent voice-growth regression
  exposed invalid PCM ownership and graph leaks. ARC is now enabled in both
  Debug and Release and enforced with a source-level compile-time guard.
  Explicit lifetime and stereo graph-growth tests now pass; independent review
  of the build settings and these tests supersedes the earlier ownership review.
  All 37 focused checks pass at 12:10. Seven bounded Thread Sanitizer checks
  pass at 12:09 without reported races (native instrumentation verified in the
  build log); this is not exhaustive proof. Temporary diagnostics are restored,
  and the normal build passes at 12:10. Full-suite validation after the ARC fix
  completed at 12:21: all 316 tests passed, no failures or skips, with the final
  `TEST FINISHED` marker. The final normal build passes at 12:22. This closes
  the pending implementation validation, not acoustic/hardware parity.
- Buffering freezes active effect samples instead of restarting them. A due
  reserved one-shot is promoted once, preserving minimum-distance history;
  active loops retain their sample position and only future reservations are
  canceled/rebased. Queued expired loop stops are reconciled before native
  engine/voice resume. Three regressions failed before the fix, including
  actual offline-rendered PCM that skipped one-shot samples and restarted loops
  at zero. Both now resume at sample 512 after repeated frozen frames. All 26
  focused audio/pause-related tests pass at 11:21 September 27, including
  full 256-voice pool replacement while paused; the normal build passes.
  Independent review found no actionable issue. The full simulator suite then
  passed all 304 compiled tests at 11:32, zero failures/skips, with the final
  `TEST FINISHED` marker. The native-stop capability probe added after compilation
  has no result in that run and is excluded from the 304. The reported 光 sound
  has not been physically reproduced or attributed to this code path; that
  check remains deferred.
- Static-intro analysis now allows lifecycle callbacks when each is proven
  fixed and side-effect-free, rather than requiring all five slots to be absent.
  Pure proof results remain distinct from stage-drawing results through shared
  memoization and branches. Nonzero initialize/updateSequential/touch/terminate
  returns do not retire an entity; EntityDespawn still controls that, while a
  fixed false shouldSpawn retains the waiting queue's existing behavior.
  Mutable reads, effects, writes and drawing in these lifecycle slots preserve
  the intro. New regressions failed before the fix, including a model stuck at
  zero instead of the first visible note at 0.5 seconds. All 25 intro tests pass
  at 11:08 on September 27, including true/false spawning, preprocessing-set
  despawn flags, actual touch callbacks, reverse memoization traversal and
  cross-entity transformed-stage rewind. Independent review found no actionable
  issue. The normal 11:09 build passed. The full 11:09 simulator run completed
  at 11:18 with all 300 compiled tests passing
  (`RunAllTests/4CCB1A77-4D51-4670-B0FD-63A5388A29A5.txt`). Its completed
  report and TEST FINISHED marker resolved the observer timeout without a
  restart. Three buffering tests added after compilation have no result in
  that run and are excluded from the 300.
  Broader dynamic/custom-stage classification and physical verification remain
  open; these tests do not establish a Project SEKAI-specific timing change.
- Playback clock history distinguishes an affine reference origin from its
  validity interval. Native simulator traces supplied host origin zero across
  stop/resume transitions; treating that as a boundary erased earlier mappings
  and changed queued input times. The fix preserves observed history, including
  equal-timestamp ordering and drift-only recalibration, with 128 retained
  mappings. Moving notification EventTime values refine the boundary only
  inside its observation bracket. Stopped transitions and out-of-bracket
  evidence fall back to first observation, explicitly not an exact transition
  measurement; opt-in traces retain 64 records and the uncertainty interval.
  Source-clock anchors are diagnostic only, not presumed transition times.
  A future reference anchor now extrapolates immediately, as documented in the
  active SDK's CMSync.h for CMTimebaseSetRateAndAnchorTime. The new native-clock
  assertion failed before the fix. Synthetic/native checks cover captured
  zero-origin mappings, pauses, jumps, reverse/nested clocks, source swaps,
  repeated reads, invalid boundaries, storage bounds and diagnostic isolation.
  Twenty focused clock tests passed at 10:52 on September 27; subsequent
  nested-source and exact-boundary/debug-pause checks passed at 10:54/10:56.
  Native effective rates remain independently checked against selected speed;
  player stalls/jumps no longer imply unconditional wall-time progression,
  while input/player and history assertions remain strict. The normal 10:57
  build passed. Final independent review found no remaining actionable issue.
  The full 10:57 simulator run finished at 11:06 with all 297 compiled tests
  passing (`RunAllTests/E40E9225-05AF-4014-A70F-A7289EF4492C.txt`), including
  all live clocks and cached charts. The completed report and TEST FINISHED
  marker resolved the observer timeout without restarting. Three intro tests
  added after compilation have no result in that run; they are excluded from
  the 297. This is not physical alignment sign-off or a calibration change.
- Curved draws no longer have a separate 1,024-segment cap. The public
  [DrawCurvedB contract](
  https://wiki.sonolus.com/engine-specs/functions/draw-curved-b) specifies the
  segment count without that numerical restriction. All six edge variants
  now accept positive integer counts within the existing shared 16,384-strip
  frame safety budget; ordinary Draw commands consume that budget too. This
  is a host work limit, not a claimed public/native maximum. Geometry applies
  the same bound before allocating strips, and failed commands do not consume
  the budget. A new regression failed on the old cap, then passed with exact
  strip counts, shared endpoints and full contiguous texture coverage at
  1,025, 4,096 and 16,384 segments. Four focused simulator tests pass, including
  both Metal and software pixel checks with 1,025 strips, mixed-command budget
  accounting and frame reset. Independent review found no actionable issue.
  The normal build passed at 10:35 on September 27. The completed full run
  (`RunAllTests/D9B6F8FB-86E3-4E0E-B845-9AFBC369A6DD.txt`) passed 286 of 292
  tests, including the curve checks and all cached-chart probes. Six live
  audio-clock tests failed to advance audio across an abnormally long run.
  The isolated 10:33 rerun passed five; debug-pause playback still failed on
  approximately 3 ms of historical input remapping and 33 ms of elapsed-time
  disagreement (`RunSomeTests/9E9C31F7-0962-4527-BF5D-B1EBBCE3C0A8.txt`).
  Audio I/O reconfiguration appears in that console, but is not a proven
  explanation. No timing assertions or gameplay offsets were loosened. This
  is not a green full suite or stable-push sign-off. The timing investigation
  stays open in REQUESTS.md, separately from this tested curve compatibility
  fix and from the deferred physical batch.
- Intro stage classification now accepts If and all four Switch variants when
  the selector and case tests are fixed, side-effect-free expressions and every
  alternative contains only fixed expressions or proven stage drawings. It
  does not evaluate a selector and discard an unsafe unchosen branch. Mutable
  reads, random values, writes, unknown graphics, drawing-as-selector/argument,
  malformed arities, cycles and excessive analysis work remain unproven.
  Fixed branches can nest without turning their drawing effects into pure
  numeric expressions. The existing level-entity/lifecycle restrictions and
  frame-to-frame visual guard remain unchanged. Two regressions failed before
  the fix: the proof rejected every branch family, and model startup stopped
  at zero rather than the first visible note at 0.5 seconds. They now pass;
  model tests also preserve a later transform change for all five families.
  Seven focused tests passed at 06:46–06:47; additional conservative branch
  cases suggested by independent review passed at 06:48. Review found no
  actionable issue. The full 06:48 simulator suite passed all 289 tests with
  no failures or skips, including every cached-chart probe; the normal build
  passed at 06:53. The observer timed out but the same run's final report and
  TEST FINISHED marker confirmed completion without a restart.
  This expands safe skipping, not optimal skipping of every
  custom engine or physical presentation certification.
  The cached SEKAI Stage/StaticStage archetypes have shouldSpawn, touch and
  updateSequential callbacks, so they still fail the unchanged lifecycle
  eligibility checks. This change does not establish faster SEKAI startup.
- Particle preparation now crops only sprites referenced by selected engine
  effects, while keeping the resource's original sprite indices. Previously
  an invalid crop used by an unrelated effect could reject a valid selected
  effect. Optional prepared slots avoid allocating unused crops; shared
  references crop once and tint caches retain their index/color separation.
  Selected bad bounds and out-of-range references still fail, with the effect
  name and sprite index in bounds errors. The failed-before-fix regression
  now checks a selected sprite after unused invalid entries, fractional UVs,
  emitted geometry, all four property/random-cache modes, and shared/distinct
  tint identities. Five focused simulator tests passed at 06:31; the final
  tint checks passed at 06:32. Independent review found no actionable issue.
  The full 06:32 simulator suite passed all 286 tests with no failures or
  skips, including all cached-chart probes; the normal build passed at 06:37.
  Xcode's observer timed out, but the same run's completed report and
  TEST FINISHED marker confirmed success without restarting the suite.
  This selection boundary does not bypass structural JSON decoding or atlas
  validation, and does not claim native behavior for malformed resources.
- UI animation endpoints and durations no longer have undocumented +/-1024
  and 3,600-second limits. The public [UI configuration schema](
  https://wiki.sonolus.com/engine-specs/resources/engine-configuration-ui)
  declares numeric tween values without those limits. Easing overshoot is
  preserved instead of being clamped at 1024. Weighted interpolation also
  avoids an overflowing endpoint difference; a complementary difference-based
  calculation handles same-sign overshoot if weighted products overflow.
  Negative durations and nonfinite inputs remain rejected;
  unrepresentable interpolated output still falls back to the finite endpoint.
  Judgment and combo completion tasks now sleep in cancellable bounded chunks,
  preserving long lifetimes without directly converting arbitrary engine
  durations to Swift's fixed-width Duration. Five focused simulator tests
  passed at 06:20. Independent review caught the weighted-product overflow;
  its regression and the correction now pass, along with real child-task
  cancellation and bounded combo-view snapshots. The snapshot has a nonblank
  scale-1 control and exercises +/-2048, 1e300 and Double.max in a clipped
  viewport. It is not live HUD lifecycle or native rasterization evidence.
  The 06:20 full simulator run passed all 284 compiled tests, including cached
  charts, with no failures. The observer timed out, but the same run finished.
  Its report also lists the later-added snapshot as "No result" because it
  was not in that build. All six focused tests passed on the final revision
  at 06:26, including that snapshot, and the normal build passed. Independent
  follow-up review found no further concrete defect. General resource/native
  conformance and physical presentation verification remain open.
- Public function-name coverage is pinned to the official
  [runtime metadata](
  https://github.com/Sonolus/runtime-metadata/blob/8da7fab2580701fdff82e10224f428db05add4bc/Runtime/Functions.json).
  Its main revision was checked on September 25: 191 names, comprising 175
  implemented dispatch entries, 14 unresolved stack functions, and two
  functions belonging only to non-play modes. A new independent inventory
  regression checks every name against the production registry, a reachable
  touch callback's preflight, and actual interpreter/host dispatch. Each
  supported entry must execute without error using declared argument counts,
  valid memory addresses and initialized resources/handles. Invalid arguments
  fail the test rather than hiding an absent operation-specific branch behind
  shared arity validation. Break executes inside Block. This guards against
  another delayed PlayLooped-style missing function without a sampled chart.
  The strengthened September 25 06:15 simulator regression and normal build
  passed. These are successful-call smoke probes, not exhaustive argument or
  return-value/side-effect conformance. The touch callback is a preflight root;
  direct execution has no callback context and does not prove callback legality
  or native semantic parity. The explicit missing stack set
  must not be removed from the test without implementation and behavioral proof.
- Selected particle definitions now validate resource fields before gameplay:
  RGB HTML colors, existing sprite indices, and finite start/duration/end.
  The [particle effect contract](
  https://wiki.sonolus.com/particle-specs/resources/particle-data-effect)
  permits short and full RGB hex colors; alpha remains a separate property.
  Previously malformed colors could silently become white or another color,
  and invalid sprite references could silently disappear while the
  effect remained available through HasParticleEffect. Errors now identify
  the selected particle effect and offending field. Zero duration, start at
  one, negative starts, and start/duration greater than one are not rejected.
  Semantic errors in unselected effects or unused presentation families remain ignored;
  structurally malformed JSON can still fail decoding. A failing-before-fix
  regression covers nine invalid cases and 100 finite boundary combinations.
  Existing easing/default, loop-boundary, and tint regressions also pass in
  the September 25 05:55 five-test simulator run. Final independent review
  found no blocker. This is resource
  conformance, not evidence of physical hit-effect correctness.
  The first full run rejected four cached SEKAI integrations: its hold effects
  use starts as late as `1.4`. Treating the docs' normalized `0...1` description
  as a hard range was an overrestriction, also missed in initial review.
  The public Studio [state construction](
  https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/particle-state.ts)
  and [renderer](
  https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/particle-renderer.ts)
  retain extended intervals unchanged. The restriction was removed, and
  synthetic tests now verify a start at `1.125` and a negative start through
  loop/nonloop rendering and all four cache modes. Normalized units must not
  automatically become validation bounds; check executable reference behavior
  as well as prose before rejecting previously supported resource values.
  Rejecting a nonfinite computed end is host numerical-safety policy, not
  evidence of reference/native resource validation behavior.
  Verification: the 05:56 full simulator suite passed all 281 tests, including
  the six cached-chart integrations, with zero failures or skips
  (`RunAllTests/1E4B9CA8-E947-4F3E-8E69-C42108E6C851.txt`). After the observer
  timed out, the same completed run supplied its full result report. An added
  duration-1.5 rendering case passed separately at 06:02, and the normal build
  passed at 06:02. No physical-device or song-server requests were used.
- Static intro-stage proof includes expressions over prepared immutable data,
  not just literal arguments. The public [Level Data](
  https://wiki.sonolus.com/engine-specs/play-blocks/level-data),
  [Level Option](https://wiki.sonolus.com/engine-specs/play-blocks/level-option),
  and [Entity Data](https://wiki.sonolus.com/engine-specs/play-blocks/entity-data)
  access contracts support their fixed post-preprocessing values; [ROM](
  https://wiki.sonolus.com/engine-specs/play-blocks/engine-rom) is also read-only.
  The proof accepts Get with a literal ID for one of those four
  blocks, a fixed index expression, and explicitly allowlisted deterministic
  arithmetic/easing. Unconditional Draw/DrawCurved statements still require
  a literal known-stage sprite ID and a persistent level-backed non-input
  entity. Drawing effects are tracked separately from pure expressions, so
  shared graph nodes cannot smuggle a drawing operation into an argument proof.
  Traversal is iterative, memoized across archetypes, and limited to 100,000
  node/edge work units; cycles, mutable reads, streams, per-frame randomness,
  dynamic block IDs and time-dependent conditional drawing retain the intro.
  The prepared-expression regression failed before the change and passes after
  it. Additional tests cover shared draws, curved geometry, randomized
  preprocessing and restart, Entity Data array-alias preparation, mixed proof
  roles, direct/indirect cycles, invalid indices, a 12,000-node chain and an
  excessive-width graph. Constant If/easing expressions and a computed fixed
  Get index also have positive coverage. Independent review found no soundness
  or work-budget defect. Model tests reach the first visible note through a
  prepared stage and rewind when another entity changes its global transform.
  Visual comparison remains necessary even with fixed arguments. This does not
  close dynamic/custom-stage classification or deferred physical verification.
  Verification: the September 25 05:22 full simulator run passed all 277 tests
  with no failures or skips, including six cached-chart integrations
  (`RunAllTests/B67BD69C-3CEC-48EC-BC9D-953BEF6D7639.txt`). The observer timed
  out at 300 seconds; the still-running test process subsequently completed,
  and the same execution supplied its full passing summary and `TEST FINISHED`
  marker. The 05:28 normal simulator build passed. No physical-device checks
  or song-server requests were used.
- Fractional skin/particle sprite rectangles preserve exact texture regions.
  The public [skin sprite](
  https://wiki.sonolus.com/skin-specs/resources/skin-data-sprite) and
  [particle sprite](
  https://wiki.sonolus.com/particle-specs/resources/particle-data-sprite)
  contracts declare numeric coordinates and dimensions. Previously CGImage
  rounded fractional crop bounds and the renderer stretched that entire crop.
  Crops now retain fractional UV bounds with a one-texel neighboring border
  for linear filtering; horizontal/vertical curved slices compose within those
  bounds, and particle tints retain them. Integral crops keep their existing
  full-region affine fast path. Tests compare emitted skin and tinted particle
  pixels against independent whole-atlas UVs in software and Metal, including
  nearest/linear filtering, atlas-edge clipped borders, and subpixel extents.
  The initial regression failed before the fix (maximum channel errors 255
  and 98), then passed after it. Independent review found no correctness issue.
  The public [Studio importer](
  https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/skin.ts)
  also forwards source bounds directly to drawImage, but its integer canvas
  backing dimensions make it an imperfect rasterization oracle. The tests
  prove exact whole-atlas sampling equivalence, not native filtering parity.
  Existing integral-edge clamping is unchanged. On systems without Metal,
  fractional regions use the existing whole-frame software mesh path; physical
  performance and rendering checks stay deferred under the API-coverage gate.
  Verification: the September 25 05:07 full simulator run passed all 272 tests,
  including six cached-chart integrations, with no failures or skips
  (`RunAllTests/02856B1F-BD6A-4C55-B009-F1C10EB6CC66.txt`). After the observer's
  300-second timeout, the same execution supplied the full passing summary and
  `TEST FINISHED` marker. The 05:13 normal simulator build passed. No physical
  checks or song-server requests were used.
- Intro simulation can continue beyond input activation until the first
  visible frame or an existing audio/debug/effect boundary. Resolving an input
  during simulation instead restores the original start, before committing
  judgments, score or timing history. No engine-specific note-time heuristic
  or timing offset is introduced. The former first-activation stop failed the
  new offscreen-note model regression; the corrected path reaches visibility.
  Eleven focused model/visual guard tests pass, including BGM-first (the 50 ms
  pre-onset margin), invisible-input fallback, held opening graphics, and
  separate judgment-triggered and visual-only background/spawn rollback.
  Independent review found that restored initial DebugPause needed capturing
  before audio startup; its failing regression now passes, including resume
  with a single committed initial judgment/log. Final review found no further
  actionable issue. Scheduled life changes also trigger rewind: the regression
  failed before the fix and now confirms restored life and the still-pending
  event. Time HUD content intentionally follows the skipped timeline; this is
  not a claim that all HUD values remain frozen. Existing direct runtime tests
  cover scheduled/looped
  engine-sound boundaries; a model-level sound-first fixture is still useful.
  This does not establish optimal skipping for every dynamic stage or certify
  an audible/visible phone start. Unknown initial graphics remain protected.
  Verification: the September 25 04:50 full simulator run passed 269 tests
  (`RunAllTests/C26C14ED-5180-4EA4-AE74-99B518AD0B0F.txt`), with its completed
  console marker checked after the observer timeout. The life test was added
  after that run built and appears as No result, not a pass. All 11 focused
  intro/visual guard tests passed on the final code at 04:56
  (`RunSomeTests/5C59FEC8-3362-4555-9912-A85D1203CB78.txt`), with no failures
  or skips; the 04:57 normal simulator build passed. No real-device checks
  were performed. General API coverage and the deferred physical batch remain
  open.
- Particle dimensions now use local half-extents before rotation and bilinear
  mapping. The previous extra division by two shrank both dimensions compared
  with the official Studio renderer. Its pinned
  [import/export path](https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/particle.ts)
  and [state evaluation](https://github.com/Sonolus/studio/blob/c6cb8e93a25368da7fca5b2cb8e44be16f29bd24/src/core/particle-state.ts)
  pass width/height coefficients through without compensating scaling.
  A failing-before-fix synthetic regression now passes with independently
  calculated corners for animated width, translated centers, quarter-turn
  rotation, negative-width reflection, and non-square parent geometry across
  all four cache modes. Four focused simulator checks pass. Independent review
  checked the source chain and corner calculations and found no issue. This
  improves reference-renderer conformance; it does not certify the user's
  physical hit-effect appearance or the GPU cost of the larger visible area.
  Verification: September 25 04:27 simulator suite, all 263 tests passed with
  no failures or skips, including six cached-chart integrations
  (`RunAllTests/658CE375-A60D-4966-95ED-FBB0DE18BAEE.txt`). The observer's
  300-second timeout was followed by the same run's full summary and
  `TEST FINISHED` marker. The 04:33 normal simulator build passed. No device
  checks or song-server requests were used.
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
  Additional source comparison found particle easing-curve differences;
  the separate particle implementation is described below.
  The official [numerical easing contract](
  https://wiki.sonolus.com/engine-specs/functions/easing-functions) references
  easings.net; its Back/Elastic definitions support the existing numerical
  implementation. Particle-specific formulas must not replace numerical
  functions or HUD animation behavior wholesale.
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
- Particle resource easing now has a separate path for Studio's `inOutBack`,
  `inOutElastic`, `outInExpo` and `outInElastic` variants. The numerical engine
  functions and HUD animations retain their existing formulas. The initial
  three-curve regression failed before this correction; independent review
  caught the fourth case, `outInElastic`'s exact midpoint, which was added to
  the implementation and regression. Independent expected values cover both
  halves, endpoints and midpoints, including overshoot and the small Expo/
  Elastic midpoint discontinuities. Decoded particle properties exercise both
  direct and cached endpoints; decoded HUD tweens check path separation.
  After the fourth-case fix, independent review compared all 38 Studio curves
  against a separate arithmetic transcription of the Swift formulas at 10,009
  phases each, including exact midpoint and adjacent representable values.
  Maximum difference was 2.34e-15; no remaining issue was found. This numerical
  source comparison is distinct from executing the Swift regression tests.
  This is parity with the pinned public Studio curves, not a claim of native
  renderer output. Other resource/native conformance work remains open.
  Verification: the September 25 04:37 full simulator run passed all 264 tests
  with no failures or skips (`RunAllTests/FF1EB864-8416-49F7-9685-7D432AA5FDE7.txt`).
  The observer timed out at 300 seconds, then the same run produced its full
  passing summary and `TEST FINISHED`. That run built before the fourth-case
  review correction and HUD assertions. All seven focused particle/numerical/
  HUD regressions passed against the final code at 04:42
  (`RunSomeTests/B18F6498-F146-4053-9C21-59BD3CF415D6.txt`), and the final 04:42
  normal simulator build passed. No device tests or song-server requests.
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
  optional depth keys, and contiguous texture slices. Positive integer segment
  counts share a 16,384-segment frame safety budget; the former separate
  1,024-per-curve cap has been removed as described above.
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
  lifetimes as well as audio boundaries; resolving an unseen input rewinds it.
  Unknown graphics
  present at media zero preserve the entire opening; unchanged alone is not
  evidence of disposable stage decoration. A narrow exception requires fixed
  standard-stage Draw/DrawCurved calls from persistent non-input entities without
  spawn conditions or mutable play callbacks. Custom names, mutable conditional draws,
  ambiguous resource IDs and dynamic spawns cannot establish that exception.
  The prepared-expression extension and its bounds are described above.
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

## Temporary Memory storage optimization

Play-mode Temporary Memory keeps 4,096 value/generation pairs instead of a
dictionary of addressed cells. Callback selection advances the generation;
wrap discards all slots before reusing generation 1. Bounds and callback
permissions are still checked before access. Standalone memory without a
declared play layout retains sparse storage for indices above 4,095. Restart
snapshots capture both slot data and generation with copy-on-write semantics.
This preserves the app's existing clearing policy; it does not redefine the
public contract's unpredictable initial scratch values as guaranteed zeros.

The dense buffer uses approximately 64 KiB per memory instance, plus another
64 KiB when a write first separates it from a retained preparation snapshot.
Ordinary callback clearing changes only a scalar, without copying the buffer.
Four focused tests passed on September 25, covering callback/entity changes,
bounds, sparse fallback, bit preservation, epoch wrap and snapshot isolation.
All six full cached-chart paired probes also passed on that initial revision.

Independent review found no production defect. Its two test recommendations
are implemented: compare presentation-memory and exported-value bit patterns
in addition to commands, judgments, life and scores, and alternate adjacent
timed runtime updates before rendering. Comparisons and rendering are outside
the runtime timing intervals. Runtime-plus-sprite CPU durations sum the two
separately measured phases. Follow-up review found no further actionable issue.
The six revised full-chart paired probes passed in the September 26 normal
Debug simulator run (iPhone 17 Pro, iOS 26.5). Mean runtime-update CPU decreased
5.0–10.6% with matching captured outputs on every simulated frame and restart.

| Cached case | Frames | Sparse mean / p95 ms | Dense mean / p95 ms |
| --- | ---: | ---: | ---: |
| Eleventh Hard 16 | 6,062 | 7.404 / 13.333 | 6.628 / 11.882 |
| 光 Hard 18 | 6,567 | 9.017 / 21.137 | 8.064 / 18.904 |
| 22/7 Pro 4.9 | 8,108 | 1.283 / 2.009 | 1.218 / 1.908 |
| “shake it!” Hard 18, no contacts | 8,054 | 6.163 / 13.554 | 5.548 / 12.184 |
| “shake it!” Hard 18, repeated contacts | 8,046 | 9.327 / 16.994 | 8.378 / 15.215 |
| SIF Custom Charts UNSTOPPABLE | 5,854 | 0.375 / 0.493 | 0.345 / 0.454 |

The full 22:45 simulator run passed all 291 tests, with no failures or skips
(`RunAllTests/4A218BE7-C614-44E3-B5CE-57AB5A4FB2B2.txt`). Its observer timed out
after 300 seconds, but the same run's completed report and TEST FINISHED marker
confirmed success; no replacement run was launched. The 22:54 normal app
build passed (`BuildProject/BuildProject-Log-20260926-225454.txt`).
The fixture runs use their existing options and independent random sources;
future random-heavy fixtures need controlled randomness before exact paired
equality can be asserted. These probes compare captured outputs, not native
Sonolus semantics, complete memory histories or real-time device performance.

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

## Resource acceptance boundaries

These distinguish the implemented selection/default rules from native parity
questions. They do not certify every legal combination of resource fields.

| Surface | Implemented boundary | Remaining evidence |
| --- | --- | --- |
| Gzip resources | All concatenated members are decoded and validated; output limits apply to their cumulative data. Split JSON and ROM resources are covered. | Host output budgets remain 64 MiB generally and 16 MiB for ROM; this is not unbounded resource support. |
| Engine configuration | Required for server playback; declared options, categories, UI metrics, visibility and animations are consumed. Per-engine preference policy is explicit. | Missing UI sections still use app defaults; do not mistake acceptance of incomplete configuration for a specified native default. |
| Skin atlas | Only named sprites requested by the engine are cropped. Interpolation, transforms, fractional bounds and render mode are honored. | Exact native filtering and treatment of declared atlas dimensions that differ from image dimensions. |
| Particle atlas | Selected effects are validated, original sprite indices are preserved, and only their referenced sprites are cropped. Structural decoding and atlas validation still apply. | Native rasterization/random realization parity beyond the public Studio reference; selected numeric limits remain explicit host limits. |
| Particle property defaults | Missing from/to coefficients use zero, and omitted easing uses linear, supported by the public Studio importer. | These defaults are not proprietary-client observation. |
| Effect audio | Engine-requested named clips are selected from the ZIP and prepared through the native audio backend; missing names remain unavailable to HasEffectClip. Filenames honor ZIP UTF-8 flags, legacy CP437 and validated Unicode Path extra fields. | An exhaustive supported codec contract is not supplied by the public MP3 recommendation; native format support and acoustic alignment remain separate checks. |
| Background | Natural aspect and unit scaling apply when overrides are absent; declared fit, color, mask and blur are consumed. | The blur kernel/radius is not specified publicly; the current size-normalized Gaussian is host policy. |

A bounded independent review on September 27 found no new contract-supported
valid-resource incompatibility in decoding, selection, options or play UI.
This does not close the evidence limits above or convert host policies into
native guarantees. Per-engine preference scope remains an explicit user policy.

September 30 gzip correction: the shared resource decoder previously returned
after the first compressed member, silently discarding later data. Gzip permits
concatenated members under [RFC 1952 section 2.2](
https://www.rfc-editor.org/rfc/rfc1952.html). The decoder now uses zlib's
[`inflateReset`](https://zlib.net/manual.html) between members, validates later
headers/trailers, rejects incomplete or trailing non-member data, and retains
one cumulative output budget. Its output buffer is reused across members;
raw-DEFLATE decoding for ZIP entries is unchanged. Magic detection also works
for Data slices whose startIndex is not zero.

Three initial regressions failed before the fix and pass afterward. Four new
tests use independently generated fixtures to cover split JSON, split ROM,
empty members, corrupt/truncated later members, wrapper boundaries, Data slices
and cumulative limits across 64 KiB output chunks. Independent review found no
actionable issue. All 349 non-cached simulator tests and the cached 22/7
lifecycle/restart check pass; the normal build passes at 01:06. Summary IDs:
`A1E24DFF-C0CD-4B34-8876-53F26B0CE755` and
`C83817F1-F4AD-458A-B159-FB5C22F79EBD`. The other six cached chart/workload
checks were not rerun for this bounded decoder change. Physical tests remain
deferred. This unit was already in verification when the breadth-first policy
was adopted; further resource edge cases return to global triage.

September 30 ZIP filename correction: the old effect loader treated every name
as UTF-8. Valid legacy filenames could fail decoding, and Unicode Path metadata
was ignored, so a requested clip could appear unavailable despite being present.
The loader now follows [PKWARE APPNOTE Appendix D and section 4.6.9](
https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT): bit 11 selects UTF-8,
otherwise the header uses CP437; a recognized Unicode Path field overrides a
legacy name only when its original-name CRC matches. Stale CRCs and unknown
versions fall back to the header name. Extra-field parsing is bounded, invalid
UTF-8 is rejected, and duplicate checks use the final decoded name. Filenames
are still dictionary keys only, never filesystem extraction paths.

Both new regressions failed before the fix. Coverage includes flagged/unflagged
non-ASCII names, legacy bytes that also happen to be valid UTF-8, Unicode-field
precedence, stale/unknown metadata, invalid/truncated fields, unrelated fields,
conflicting overrides and duplicate decoded names. Independent review found no
actionable issue, including the final adversarial fixture additions. All 341
non-cached simulator tests pass, and the normal build passes at 00:16. The seven
cached-chart probes also pass in the run completed at 00:28, covering Eleventh,
光, 22/7, SIF and all three "shake it!" workloads. All 348 tests therefore pass
across these two runs without skips or failures. The observer expired after
300 seconds; the same original test process continued to its verified
`TEST FINISHED` result, without restart. Result summaries:
`BE14EA8F-596E-4C44-8B9D-E8892A5F51B2` (341 tests) and
`35595312-95FC-4EAA-9D8D-252E87179A38` (seven cached tests).
This does not expand the archive's existing stored/deflate compression support,
64 MiB encoded/total decoded bound, 16 MiB per-entry bound or 1,024-entry limit.
The ZIP64 gap noted in this pass is addressed by the follow-up below; other
compression methods remain unsupported. No claim of all ZIP variants or native
audio codec parity follows from these tests.

September 30 ZIP64 follow-up: tiny archives can legally use ZIP64 metadata, so
the existing byte/entry budgets did not justify treating its sentinel values
as actual file sizes or counts. The parser now resolves the ZIP64 end record
and locator and independently present extended central-entry fields using
[APPNOTE sections 4.3.14–16 and 4.5.3](
https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT). Integer conversion,
directory ranges and local data ranges are bounded before arithmetic/slicing;
multi-disk and inconsistent metadata fail explicitly. The original resource
budgets remain. Optional directory signatures and extensible ZIP64 records are
accepted without interpreting their opaque content.

The new positive matrix failed before implementation. Tests cover all 16 central
entry sentinel combinations across three directory modes, 64 mixed legacy-end
sentinel patterns, comments, empty archives and independent Python zipfile
deflate fixtures (including a nonseekable writer's data descriptor). Negative
tests cover UInt64.max/Int.max fields, missing/truncated/duplicate extensions,
cross-record bounds, contradictory counts, other disks and retained 1,024-entry
and 16 MiB-entry limits. Every truncated prefix of the bounded ZIP64 fixture
is rejected. Independent review of the final parser and tests found no actionable
issue. All 345 non-cached simulator tests pass; the normal build passes at 00:40.
Three cached probes, one per existing engine-family resource set, pass at 00:43:
Eleventh/Next-SEKAI, 22/7 and SIF Custom Charts/LLSIF. The four redundant cached
chart/workload probes were not rerun for this archive-only change; their full
348-test parent verification is recorded above. Current result summaries:
`AB6A0FC9-8A3A-452F-BDB3-CC2B2F0D65F4` (345 non-cached) and
`DA99B6E2-EEA4-4836-B6BF-7EDA675013B0` (three cached). These checks establish
archive/runtime regressions, not physical playback or every ZIP variant.

## Stack implementation evidence needed

Deferred by user direction on September 29. Retain the explicit unsupported
preflight, but do not let this dependency block non-stack implementation or
verification. The draft is not authorized for posting.

The user's subsequent September 29 request reopens a bounded search for a
real chart using these operations, not speculative implementation. Seven
cached engine files reduce to three unique graphs: LLSIF (1,308 nodes),
22/7 (1,818) and Next-SEKAI (72,110). All have zero `Stack*` nodes, so the
cached UNSTOPPABLE, シャンプーの匂いがした, Eleventh, 光 and “shake it!” charts
cannot exercise stack dispatch. Public code searches found only relevant
metadata/declaration/wrapper hits, notably [sonolus.h](
https://github.com/SonolusHaniwa/sonolus.h/blob/86151ef255158ec36bf6e527febc9d198fa1e90b/sonolus.h)
and its copy bundled with the Sirius engine. A wrapper definition is not a
gameplay invocation. No real consuming engine/chart has been verified; search
coverage is bounded and does not establish nonexistence. No catalog crawl or
reference-client execution was performed. A future candidate needs reachable
stack calls in its engine graph and a chart that exercises those callbacks;
even then, successful self-execution alone will not establish reference parity.

A further bounded GitHub code search checked `StackGetFrame` and
`StackGetPointer`, plus `StackInit` in SonolusHaniwa's repositories. Relevant
results again consist of declarations, operation metadata and wrappers, not
verified gameplay consumers. The official compiler's
[function classification list](https://github.com/Sonolus/sonolus.js-compiler/blob/b67abf697c281003f5c2794653a029edb30a9124/src/utils/funcs.ts#L100-L103)
is not an emitted stack program. The additional public web-player candidate
[SonolusWP_dev](https://github.com/1217pond/SonolusWP_dev/blob/61a9b2979934f115fb25403185d8d378c8098599/env/src/as/assembly/node_calc.ts#L647-L660)
maps all 14 stack functions to `UnimplementedFunction`, so it supplies neither
an implementation reference nor an executable stack fixture. Sirius's current
repository tree has only a thumbnail under `dist/`, not a published engine
graph to verify. These searches do not cover unindexed or compressed engine
assets, all repository history, or every server. The fixture request remains
open; no stack implementation or reference-client/device execution was added.

September 30 scope expansion: the user authorizes downloading every chart's
data from 22/7, Project SEKAI and LLSIF through a slow cached crawl, managed by
a dedicated subagent. `scripts/cached_stack_crawl.py` enumerates catalog pages,
retains each difficulty's metadata and engine association, and downloads only
level data and engine play data. No music or presentation media is included.
Each actual hostname has one request gate with randomized 60–120-second gaps;
the two milkbun catalogs alternate tasks, while SEKAI can advance concurrently.
Redirects and retries share the gates; HTTP backoff and checkpointed cooldowns
survive restart. An exclusive cache lock prevents duplicate workers.

The cache verifies content hashes and reuses existing local chart/engine blobs.
A resource-level lock also prevents simultaneous cache misses from downloading
the same content twice. Catalog responses belong to a dated crawl, not a
permanently fresh snapshot. Failures, incomplete items, cursor loops and changes
in reported page counts remain visible. A multi-day crawl cannot establish an
atomic server snapshot. The scan reports all Stack-prefixed nodes separately
from callback-graph reachability; neither establishes that a chart executes a
call or that our stack semantics match a reference implementation.

Independent review found and prompted fixes for shared-resource duplicate
fetches, unrestricted destination hosts and incomplete HTTP-transfer retries.
The crawler now accepts only explicitly approved catalog/resource hosts and
treats truncated HTTP transfers as retryable, including a short bounded read
that does not raise an HTTP exception. Twenty-five offline regressions
pass, including pacing, host concurrency, cache reuse, restart, pagination,
hash conflicts, malformed items and graph reachability. Final independent
re-review found no remaining blocker for the bounded live probe. This tooling
does not close the stack ABI gap.

The bounded September 30 probe fetched the first page of all three catalogs:
22/7 reported 28 pages, LLSIF 96 and SEKAI 483. Their three referenced engine
play-data resources matched seeded hashes, so no engine download was needed;
all three scanned graphs have zero Stack nodes. The first two milkbun requests
started 72.268 seconds apart, with SEKAI progressing on its separate host gate.
This small sample verifies the live catalog format and initial cache reuse,
not full enumeration or absence of stack consumers elsewhere in the catalogs.
The user subsequently reaffirmed the 60–120-second pace. It applies to page
requests, redirects and retries, not only chart-data downloads.
The probe ended normally after exactly five requests, with 100 chart
associations queued and no task/item failures or observed page-count drift.
Follow-up regressions exposed retry starvation both across task kinds and
among chart downloads: positive retry timestamps were sorted behind fresh
tasks with a zero timestamp. Due work now normalizes its deadline before
stable insertion ordering, retaining engine/page priority without letting
new chart downloads bypass older eligible chart retries. Future retries still
honor their deadlines. Both regressions failed before their corresponding
fixes and pass afterward; final independent re-review found no launch blocker.

The full crawl resumed the same cache on September 30 at 05:00:39 UTC as
detached PID 40431, verified with parent PID 1 and process-group ID 40431.
It continued at Nanaon/SEKAI page 2 without repeating the five probe downloads.
Cache and logs are in ignored `tmp/cached-stack-crawl-20260930/`, with live
summary `report.json`, request history `events.jsonl` and console `worker.log`.
The first full-run requests succeeded on both hosts. This verifies durable
launch/resume, not completion of the multi-day crawl. Old hashless fixture
bytes are not assumed current merely because their former URL is known;
safe reuse requires a matching declared hash or this crawl's dated URL cache.

The September 25 contract recheck still does not supply an interoperable stack
layout. The [overview](
https://wiki.sonolus.com/engine-specs/functions/stack-functions) locates the
stack at the end of Temporary Memory; [StackInit](
https://wiki.sonolus.com/engine-specs/functions/stack-init) and [StackEnter](
https://wiki.sonolus.com/engine-specs/functions/stack-enter) do not define the
pointer values or frame representation. General stack literature cannot
resolve these observable implementation choices.

An authoritative specification, public reference implementation, or legitimate
reference execution must establish the following before registration changes:

| Question | Evidence needed |
| --- | --- |
| Initialization | Initial stack/frame pointer values; reserved control cells; whether StackInit clears data or only resets pointers. |
| Addressing | Whether pointers are absolute Temporary Memory indices; which cell StackGet(0)/StackGetFrame(0) addresses; offset direction. |
| Push/pop/grow | Whether pointer updates precede or follow access; exact return values; newly reserved-cell behavior. |
| Call frames | StackEnter(size) allocation and header layout; saved pointers; nested StackLeave restoration; frame-relative offsets. |
| Pointer setters | Relationship to backing-memory/control cells and subsequent push/pop/frame behavior. |
| Lifetime and limits | Reset behavior across callbacks/entities; legal bounds; overflow/underflow handling and interaction with ordinary Temporary Memory access. |

Reference observations must include the pointer getters and relevant raw
Temporary Memory cells, not only push/pop round trips: multiple incompatible
layouts pass the same abstract round-trip test. Once established, encode the
observations independently as conformance tests before implementing the stack.
The existing name/dispatch test deliberately keeps all 14 functions unsupported.
Independent review found no interoperable subset justified by these contracts;
knowing a setter's scalar return value does not establish its backing-memory
effects. These questions can be used for upstream clarification, but no issue,
message or reference-client probe has been submitted or executed.
No native-client execution is authorized by this evidence request; the user's
device-testing gate remains in force. Repeatedly rereading the same signatures
is not progress toward resolving the layout. A public clarification draft was
prepared on September 27; permission to post it to the project's designated
[developer-support repository](https://github.com/Sonolus/feedback) is pending.
No public issue or message has been submitted.

## Remaining checks, including engines we have not sampled

- [StopLoopedScheduled](
  https://wiki.sonolus.com/engine-specs/functions/stop-looped-scheduled)
  specifies precise stopping when scheduled at least 0.5 seconds ahead. The new
  native PCM adapter implements timer-independent stops, including later
  rebasing after asymmetric buffering. The ARC-fixed implementation passes all
  316 tests in the September 27 12:21 full simulator run and the final normal
  build; the independent review and native boundary/lifetime tests are recorded
  above.
  The earlier silent-buffer prototype was rejected after a native probe proved
  that an earlier queued interruption survived a later replacement. The new
  gates do not rely on selective unscheduling or missing player-time anchors.
  Immediate pause still has ordinary command-publication/render-quantum latency,
  distinct from pre-scheduled sample cutoffs. Acoustic/hardware integration
  remains deferred; the host-time kernel test is not a microphone measurement.
- Fourteen play-capable stack entry points remain unimplemented: StackEnter,
  StackGet, StackGetFrame, StackGetFramePointer, StackGetPointer, StackGrow,
  StackInit, StackLeave, StackPop, StackPush, StackSet, StackSetFrame,
  StackSetFramePointer, and StackSetPointer. Preflight rejects them before
  playback. Closure requires independently established pointer/frame layout,
  Temporary Memory aliasing and enter/leave semantics, followed by execution
  tests for nested frames and pointer mutation. Metadata supplies signatures
  and side-effect classifications, not that ABI; registration alone cannot
  close this gap. Native rendering parity also remains open. Debug functions
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
  September 30 bounded configuration/HUD review found no additional runtime
  blocker, but identified incomplete standardized text resolution. Standard
  time-unit labels now follow the public English templates (`ms`, `s`, `m`,
  `h`, `d`, `mo`, `yr`) without altering stored/runtime numbers. Percentage
  scaling remains unchanged. Source: [Sonolus English text templates](
  https://github.com/Sonolus/i18n/blob/develop/src/localizations/en/Localization.json).
  The time-unit regression failed before the fix; all 79 RuntimeDecodingTests
  passed at 00:03 and the normal build passed at 00:04. The subsequent general
  label fix bundles all 596 English protocol labels from Sonolus/i18n revision
  `20bab26806ed8f5bf0977d61a294d3bca27caa67`, with its full MIT notice in the
  resource. All settings label paths share the resolver without changing
  preference keys, option indices or runtime values. Custom strings remain
  verbatim; future unknown identifiers retain a readable fallback. Prior saved
  result text remains as recorded; newly generated summaries use resolved labels.
  The settings integration regression failed before the fix, and the bundle test
  caught an initially missing target resource. After registration, all 105
  decoding/localization/results tests pass and the normal build passes at 00:10.
  The bundled dictionary was compared exactly with the pinned upstream Texts
  section and the license checked separately. This matches the app's English UI;
  it is not whole-app localization or proof of other resource-default contracts.
  The resource acceptance table above names the current boundaries and
  outstanding evidence; unrelated bad particle crop bounds no longer broaden
  the selected effect's validation scope.
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
- Pagination recovery now offers an explicit fresh-chain refresh after a cursor
  fails, and Retry bypasses cached invalid pages. Refetching a parent invalidates
  buffered descendants and their in-flight completions; request-cursor tags
  prevent consuming a different chain's page at the same ordinal. Synthetic
  regressions cover both cursor and numbered pages, shrinking page counts,
  bounded sparse-result loading, and stable already-visible row order.
  Force reload shares an existing same-URL network fetch but bypasses stored
  responses. A changing server's numbered pages are not an atomic snapshot:
  deduplication avoids duplicate rows, but only a server snapshot/cursor contract
  can guarantee no omissions during concurrent remote insertions/removals.
- Conservative visual provenance can preserve more intro silence than
  necessary, especially custom/dynamic stage producers. Input activation alone
  no longer stops simulation; an unseen resolved input restores the start.
  Optimal first-visible-pixel skipping across arbitrary engines and physical
  presentation verification remain open. Unknown silence is not inferred from
  bgmOffset.
- Physical device multitouch, rendering/audio latency, performance tails,
  successful flick/hold variants, interruptions, and repeated play. Simulator
  clocks and no-touch lifecycle completion cannot establish those properties.

Public references: [server specifications](https://wiki.sonolus.com/server-specs/)
and [engine specifications](https://wiki.sonolus.com/engine-specs/).
Download probes remain in ignored scratch storage; no third-party charts or
assets belong in the regression fixtures. Ordinary probes use bounded pages
and cached shared resources. The separately authorized September 30 slow
cached corpus crawl is the explicit exception for the three named catalogs;
it does not authorize unrelated server crawls. State exactly which paths
were exercised and do not treat partial enumeration as full coverage.

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
