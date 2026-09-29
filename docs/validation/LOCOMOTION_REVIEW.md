# Locomotion review — 25 September 2026

Scope: the running animation pipeline, UAL source/baked assets, leg placement,
and relevant player regression paths. This is not an exhaustive project audit.
No gameplay speed, stamina, collision, or action duration changes.

## Findings and fixes

- **P2 — cadence did not match the clip.** Playback divided physical speed by
  gameplay top speed (4 or 6.5 m/s), assuming each source cycle matched that speed.
  It now uses measured backward stance-foot velocity, retarget scale, and visual
  scale. `tools/gait_bake.gd` stores the median in immutable clip metadata;
  `scripts/psx_knight.gd` reads it. Runtime motion still belongs to the motor.
- **P2 — foot locking could oppose the gait.** A fixed ankle-height threshold
  ignored the source clip's swing/contact phases. Resetting a stretched anchor
  mid-stance could introduce a hitch. Baked contact weights now gate planting,
  swing feet release, and excessive anchor distance smoothly removes influence.
- **P2 — leg IK unintentionally rotated the boot.** Moving hip/knee bones changes
  the ankle's world orientation. The solver now restores its sampled orientation
  before adding surface alignment. Clearance targets use the sampled sole height
  rather than pulling every rig toward a fixed 8.5 cm ankle height.
- **P2 — UAL mannequin bounce was flattened during baking.** Per-frame floor
  normalization forced a low point onto the floor throughout the cycle. Jog and
  sprint now receive one constant vertical clearance offset for the entire clip.
- **P2 — an additional pose filter delayed articulation.** Continuous filtering
  after AnimationPlayer sampling altered the authored gait/contact relationship.
  Measured gait clips now use the existing transition blend and cadence filter
  without another per-bone low-pass pass. This also removes repeated bone
  interpolation/cache work during running; no GPU/FPS improvement is claimed.
- **P2 — dive preparation undid its own foot constraint.** Whole-body clearance
  ran after leg placement, moving supported ankles again (up to about 4.9 cm in
  the UAL 60 Hz check). Supported feet are now solved after that clearance shift.
  The lean also exceeded the shorter UAL leg reach; presentation now lowers the
  pelvis only as much as leg geometry requires, without moving collision.
- **Test portability:** dive-preparation and preview tests looked up Knight-only bone
  names when run on UAL, producing invalid indices. It now uses semantic rig roles
  with the same anatomical/contact assertions.

Both rigs use the bundled UAL `Jog_Fwd` and `Sprint`: the existing Knight uses
retargeted resources; the isolated mannequin uses native-rig resources. The
normal player/Warden model selection remains as before this review.

## Verification and manual review

Baseline: 80 checks across running and UAL-model suites passed. Those existing
checks did not measure source vertical-motion fidelity or swing-foot release.
The added `run_gait_contacts` suite covers both gaps, preservation of sampled
ankle orientation, floor clearance, correct source identity/duration and cadence
metadata at 30/60/120 Hz sampling. Existing running checks exercise flat ground,
ramps, turns, stopping, pause, reset and interruptions on both rigs.

Run F5, open Test Grounds, and choose **01 Running**. Compare jog/sprint,
start/stop, switching speeds, S-turns, and all three ramps. Review the mannequin
through `scenes/ual_validation.tscn` with F6. Visual feel still needs in-game review;
automated geometric checks are not a substitute for that review.

Remaining limitation: target-facing lateral/backward movement still samples a
forward locomotion cycle. Dedicated directional clips/blending would be separate
visual work. This change does not introduce those animations or change facing.

Validation results: full standard regression run **4,405 checks / 55 suites**
passed (`.artifacts/tests/gait-regression.json`). UAL running/momentum/lock checks
passed **140 / 3**; crouch, jump, ground roll, get-up, ledge poses and model checks
also passed. The added rig-neutral dive tests exposed the reach/order issue above;
after correction, dive preparation, clearance, poses and preview passed **150 / 4
on each rig** (`gait-dive-final.json` and `gait-ual-dive-final.json`). These targeted
checks cover the final dive changes made after the full run. Graph checks: 9 pass.

## Follow-up: 30-degree ramps

Reproduced a stance sole gap of about 13 cm and target reach error up to 24 cm on
the long 30° ramp. The IK target was valid but below the rear leg's reach, and exit
blends could alter the completed IK pose. The presentation layer now evaluates
both targets before applying bounded, smoothed pelvis lowering, measures the
sole against the surface plane in its final orientation, and applies locomotion
correction after exit blends. No motor or collision changes.

Added `run_ramp_contacts`: 144 checks over both rigs, uphill/downhill, jog/sprint,
and 30/60/120 Hz simulation steps. It limits stance gap to 6 cm and target error to
6.5 cm including contact transitions, checks penetration and reset, and requires
actual stance samples (no empty measurements passing by accident).
