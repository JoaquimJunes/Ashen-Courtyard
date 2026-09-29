# Animation priorities validation — 2026-09-27

Implemented exact contact-work reduction, shared validation results for repeated
character creation, prepared combat resources, and the targeted forward-downhill
crouch correction. The user chose to defer the newly exposed gait-entry, backward
and diagonal movement issues. No source clips, skeletons or models changed.

## Changes and ownership

- `skin_contact_cache.gd` rejects irrelevant vertex groups with conservative bounds,
  then evaluates remaining vertices exactly. `knight_locomotion.gd` removes exact
  sole duplicates and reuses foot support within one contact update. The original
  evaluator remains the oracle; bounds never become the returned clearance.
- `animation_profile.gd` and `character_appearance.gd` share successful validation
  only while actual key/mesh data still matches. Double-precision key times,
  receiving rigs, targets, bindings and metadata remain live checks. Installed
  assets retain their immutable-resource contract.
- `combat_services.gd` retains the projectile scene during world setup.
  `world_effects.gd`, Warden setup and arena setup prepare all seven existing cues.
  Playback shares waveforms with independent sound lifetimes; reset retains
  preparation and scene unload releases ownership. The waveforms are byte-identical.
- `crouch_presentation.gd` gradually biases tightly folded knees outward, scaled to
  leg length. Foot targets, the clearance envelope and source animation are kept.
- `animation_benchmark.gd` optionally records slow-frame intervals, intervening
  physics ticks, pose CPU and action starts. This narrows profiling without
  pretending those counters explain all CPU/GPU work.

## Functional checks

**10,093 checks across 95 suites passed** in a clean source copy, plus 22 Python
checks, the runner self-test, Linux release export, normal release smoke and the
packaged animation benchmark smoke. Reports are `.artifacts/ci/checks.json` and
`.artifacts/ci/regression.json`. The extended crouch diagnostic is deliberately
opt-in and retains its known failures; it is not part of this pass's acceptance.

Additional checks exercised pose/handoff behavior and the targeted knee correction
across 30/60/120 Hz physics and 15/30/60/144 FPS. The legacy Knight crouch suite also
passed. New regressions cover cache mutation/rejection, resource lifetime, prepared
combat resources, unchanged cues and the accepted knee trajectory.

Graphify's code/document-section index and the animation semantic fragment were
refreshed; its ten tooling tests pass and the rebuilt graph has no dangling edges.
Eleven older semantic summaries from other documentation were detected as stale
and omitted, with their source sections still indexed. `graphify-out/coverage.json`
lists those gaps; this pass did not silently restamp unrelated summaries.

Steady forward-downhill knee-speed peaks, in m/s:

| Physics | Before | After |
|---:|---:|---:|
| 30 Hz | 7.80 | 2.87 |
| 60 Hz | 8.90 | 4.35 |
| 120 Hz | 9.64 | 4.79 |

These numeric trajectories do not replace visual approval. The fitted silhouette
remained below 0.956 m, weighted skin stayed above the ramp in these accepted
cases, and fitting moved sampled ankles by less than 0.000002 m.
[The wider before/after diagnostic](crouch-knee-comparison.json) records the existing
entry, backward and diagonal failures rather than claiming them fixed.

A separate headless microprobe reduced repeated profile validation from about
152 to 29 ms, appearance validation from 81 to 6 ms, and repeated actor construction
from 275 to 45 ms. A game was running during that probe, so these are component-level
observations, not isolated release performance claims. The contact evaluator's
exact result remains covered within 0.00001 m by its oracle tests.

## Exported real-GPU matrix

Godot 4.6.2 release, Intel i5-1135G7 / Iris Xe, Mesa 25.0.7, X11/GL Compatibility,
1280×720, 60 Hz physics, uncapped rendering and VSync off. Each case has 3 seconds
warm-up and 5 seconds measurement. No other game, Godot test or build process ran.
The simple lit scene includes production characters, movement/actions/equipment,
shadows and spell effects; it excludes full-level rendering and enemy AI.

Whole-frame p95 milliseconds; the 60 FPS budget is **16.67 ms**:

| Characters | Idle | 30° slope | Crouch | Combat/casting | Recovery |
|---:|---:|---:|---:|---:|---:|
| 1 | 5.56 | 6.67 | 5.35 | 5.66 | 4.44 |
| 5 | 9.25 | 12.31 | 14.29 | 10.18 | 9.20 |
| 10 | 13.45 | 22.78 | 31.93 | 14.82 | 14.36 |
| 15 | 20.41 | 44.19 | 177.37 | 24.58 | 25.49 |

Five actors meet that p95 budget in this matrix, but isolated spikes remain:
combat maximums were 52–68 ms, and individual slope/recovery frames reached
149/182 ms. This is not a guarantee of a stable 60 FPS encounter. Ten actors
exceed the budget on fitted movement, and fifteen exceed it broadly. Slow-frame
records show multiple catch-up physics ticks under overload.

Process RSS at measurement boundaries ranged from 217.4 to 239.5 MiB. Startup to
benchmark-ready was 1.771 s, including normal bootstrap. First/second benchmark
construction took 51.3/51.7 ms with resources resident. Five-actor batches took
260–371 ms; fifteen took 679–782 ms. Prepare such populations during loading.

[Raw matrix and bounded spike records](animation-priorities-release.json) retain
percentiles, sample counts, CPU, memory and spawning data. Earlier overlapping
benchmark attempts are explicitly marked invalid in `.artifacts/benchmarks`.
The [historical baseline](ANIMATION_RELIABILITY.md) used an earlier project state;
it is not a controlled before/after comparison isolating one optimization.

The [longer combat trace](combat-priorities-release.json) measured 30 seconds per
case with no competing test/build processes. Five actors recorded p95 **12.94 ms**,
p99 30.89 ms and a 102.49 ms maximum across 199 action starts. Ten recorded p95
**18.44 ms**, p99 51.37 ms and an 81.30 ms maximum across 399 starts. The longer
sample reinforces that spikes remain and ten actors do not reliably meet budget.

A [headless action microtrace](action-startup-microtrace.json) accepted 202 light/cast
starts without reproducing those stalls. Commit ticks including callbacks stayed
below 0.3 ms at p95; capture medians were 0.030–0.032 ms and individual callbacks
peaked below 0.07 ms. These results do not support blaming resource duplication.
Native render/driver work and engine synchronization require a profiler capture;
the frame/action correlation alone does not identify their cause.

## Playtest and next priorities

Run `.artifacts/build/ashen-courtyard.x86_64` with its `.pck` beside it. In the
movement lab, crouch straight down the 30° ramp, stop, reverse direction, reset,
and repeat. Check knee stance, feet and clipping. Also check sword chains, spells,
damage sounds, reset and scene changes. Wider movement defects remain deferred.

1. Profile the native render/driver and engine synchronization work around combat
   action starts before choosing another optimization; the bounded headless trace
   did not reproduce the stalls.
2. Fix the deferred gait-entry, backward and diagonal crouch cases, using the
   preserved extended diagnostic and visual review.
3. Validate a representative full encounter before increasing actor counts; keep
   population construction in loading/preparation. Any future distance/detail
   policy needs explicit sensing and gameplay ownership rules.

Repeat the matrix or a longer combat trace:

```sh
.artifacts/build/ashen-courtyard.x86_64 -- --animation-benchmark --trace-spikes --output=/tmp/animation-matrix.json
.artifacts/build/ashen-courtyard.x86_64 -- --animation-benchmark --counts=5,10 --scenarios=combat --measure=30 --trace-spikes --output=/tmp/combat-trace.json
.artifacts/toolchain/godot --headless --path . --script res://tests/run_crouch_knee_continuity.gd -- --extended-crouch-diagnostics
```

The last command intentionally exposes the deferred failures. Tested release
archive SHA-256: `1f3d4b0e0e364103bb7154afa57e527b370b5b728476eec5267735651f440a06`.
