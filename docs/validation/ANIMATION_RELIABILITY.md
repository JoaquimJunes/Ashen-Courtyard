# Animation reliability validation — 2026-09-27

The five implementation stages are in place: transactional rig/profile validation,
physics-owned poses and historical hitboxes, namespaced movesets and variable-length
combos, exact cached skin/contact work, and a lightweight runtime rig with verified
library builders. Existing source clips, gameplay timing and the UAL skeleton remain.
See [ownership and authoring](../ANIMATION_SYSTEM.md) for the contracts.

Functional checks pass. The reference GPU run does **not** establish 60 FPS for
5–15 characters in every workload. Crouching and slope/recovery work remain the
main scaling limits. Visual acceptance still requires the user's in-game review.

## Functional evidence

- **8,831 checks in 90 suites passed**, including a clean source import, 20 Python
  tooling tests, runner self-check, release export and production release smoke.
  Reports: `.artifacts/ci/checks.json` and `.artifacts/ci/regression.json`.
- Pose, handoff and swimming alignment were additionally tested at 15/30/144 FPS
  with 30/60/120 Hz physics: 228 checks per render rate. The full regression includes
  the 60 FPS variants. Ragdoll/recovery matrices passed at all four render rates;
  get-up coverage also passed at 60/144 FPS (680 additional reaction checks).
  Reports: `.artifacts/tests/{pose,reaction}-canonical-reset-*fps.json`.
- The skin/contact suite passed 347 checks, comparing the optimized exact evaluator
  against the retained original within **0.00001 m** across clips, blends, slopes,
  rotations and body replacement. Weighted sole selection and invalid metadata
  rejection are covered.
- The final opt-in release benchmark launch flag was added after the full
  regression. Its focused world/lab tests (82 checks), fresh clean import, Python
  tests, export, normal smoke and benchmark smoke all passed afterward. Reports:
  `.artifacts/tests/benchmark-startup-context.json` and
  `.artifacts/ci/benchmark-build.json`. No later gameplay changes were made.

## Real GPU measurements

Godot 4.6.2 **release**, Linux X11, GL Compatibility, Intel i5-1135G7 / Iris Xe
(Mesa 25.0.7), 1280×720, 60 Hz physics, uncapped rendering and VSync off. Each case
has 3 seconds warm-up and 5 seconds measurement; no concurrent test processes.
This is one run of a simple lit scene with production player models, actions,
movement, equipment and shadows, with one shared camera. It excludes full-level
rendering and enemy AI. Short windows and low frame counts under overload limit
percentile precision; these are measured scenarios, not encounter guarantees.

Whole-frame **p95 milliseconds** (95% of recorded intervals at or below this value).
The 60 FPS frame budget is **16.67 ms**; p95 alone does not rule out visible spikes.

| Characters | Idle | 30° slope | Crouch | Combat/casting | Recovery |
|---:|---:|---:|---:|---:|---:|
| 1 | 5.54 | 6.87 | 8.26 | 5.11 | 6.29 |
| 5 | 9.04 | 14.18 | **33.36** | 11.29 | 14.42 |
| 10 | 13.60 | **129.70** | **208.00** | 14.98 | **32.32** |
| 15 | **17.93** | **163.85** | **300.00** | **36.24** | **109.38** |

Summed character pose CPU **p95 milliseconds per physics tick**:

| Characters | Idle | 30° slope | Crouch | Combat/casting | Recovery |
|---:|---:|---:|---:|---:|---:|
| 1 | 0.84 | 3.44 | 3.51 | 0.77 | 3.65 |
| 5 | 1.86 | 6.85 | 12.56 | 2.85 | 10.12 |
| 10 | 2.68 | 15.45 | 22.08 | 3.75 | 13.56 |
| 15 | 3.46 | 16.79 | 31.55 | 5.13 | 17.97 |

Physics and render CPU figures are separate samples and cannot be added directly
to predict a frame. Pose display p95 stays below 1.38 ms across this run. At ten
and fifteen crouched actors, pose evaluation alone exceeds the physics budget;
multiple catch-up ticks per rendered frame amplify overload. Whole-frame timing
also includes other gameplay, physics, rendering and scheduling costs.

The process used 208.8–233.2 MiB RSS at measurement boundaries (233.2 MiB high-water
mark); this is process memory, not per-character memory. Startup to benchmark
ready was 1.865 s, including normal game bootstrap. First/second benchmark instance
construction took 73.8/72.4 ms with resources already resident. Synchronous batch
spawns ranged from 0.43–0.55 s for five actors to 1.15–1.30 s for fifteen; do this
during loading. Combat maximum frame intervals were 60–100 ms across counts;
their cause needs a dedicated trace before assigning them to loading or shaders.

The [raw measured report](animation-release.json) retains p50/p95/p99/max, sample
counts, animation CPU, memory, startup, spawning and completed action/recovery
counts for all 20 cases. There is no equivalent pre-change GPU run, so these
measurements do not establish a before/after frame-rate improvement.

## Follow-up priorities and playtest

1. Profile and reduce repeated exact clearance work, first through reuse keyed to
   an unchanged pose/contact frame, then a native batched evaluator if needed.
   Preserve the exact oracle; do not replace support with loose bounds. A bounded
   scalar-projection experiment stayed accurate but was 4–18% slower in GDScript
   and was not adopted.
2. Move multi-character construction to encounter preparation; investigate combat
   spikes with a longer trace. Introduce visual distance/detail policies only with
   explicit hit-sensing and gameplay ownership rules.
3. Repeat this benchmark and a representative full encounter before increasing the
   supported active-character count. Shared libraries allow many available clips;
   that does not make many simultaneously fitted skeletons inexpensive.

Run `.artifacts/build/ashen-courtyard.x86_64` with its `.pck` beside it. In the
movement lab/review scene, check walk-to-idle, 30° ramps, chained light attacks,
heavy cancellation, spell transitions, mantle/dodge exits, swimming and ragdoll
recovery. Repeat after reset and scene changes. Combat intentionally senses the
previous completed physics tick (about 16.7 ms delay at 60 Hz). The known downhill
crouch knee instability is a separate visual issue and is **not fixed by this pass**.

To repeat the performance run from the project directory:

```sh
.artifacts/build/ashen-courtyard.x86_64 -- --animation-benchmark --output=/tmp/animation-release.json
```

Tested archive SHA-256:
`749688dd83e22482c253ee0913bc423f471ce59297024036c7b93d6fe1ccbe33`.
