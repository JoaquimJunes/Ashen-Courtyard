# Animation ownership and scale

The character keeps one animated skeleton and shared immutable source clips.
Gameplay owns action clocks, damage windows, costs, movement and the one-entry
input queue. Adding a visual clip cannot create a gameplay action or move the body.

## Pose and sensing clocks

`CharacterPoseDriver` restores the last authoritative pose at the start of the
character's physics tick, then publishes one completed pose after movement. Land
presentation is evaluated there. Swimming, forward dives and physical reactions
keep their existing specialized samplers; the driver captures their results
without advancing them a second time. Recovery runs before the player's sensing
boundary. Base locomotion has its own clip/time, independent of sword/spell
sampling through the shared `AnimationPlayer`.

Rendering interpolates completed ordinary land poses and their character frames.
It never advances an action or modifies sensing snapshots. Swimming, crouching,
ledge contacts, dodges and physical recovery retain their completed fitted poses:
interpolating two clear endpoints can otherwise sweep geometry through a floor
or ceiling. A future interpolated constraint solver needs its own visual review.

Combat reads the newest world-space hitbox snapshot strictly older than the
current physics frame. Targets expose the same completed geometry before and
after their own update; old bones are never moved by a newer actor transform.
This adds one fixed tick of sensing delay (about 16.7 ms at 60 Hz). Breathing uses
the owner's newest completed pose instead. Teleport/reset reseeds history; dead
or unloaded characters cannot supply stale hit geometry. External damage restores
the committed pose before transferring to ragdoll, so render interpolation cannot
change its starting pose.

Ragdoll handoff refreshes joint attachment points for the incoming pose while
preserving the configured angular reference and limits. This avoids corrective
impulses from stale setup-pose anchors; it does not change masses, damping or
recovery thresholds. External heavy-charge cancellation likewise captures the
committed physics pose, while callbacks inside the owner's tick keep its fresh
fitted pose.

Reset initializes the base clip without an outgoing blend. It resets posture
before clearing the crouch transition: posture emits a change notification, which
would otherwise capture the old action pose again after cleanup. This order
keeps repeated resets equivalent to a fresh pose, including later ragdoll entry.

`update_pose()` remains an explicit source-preview operation for tools and focused
tests. Production code uses the physics driver. Tests that manually call the
character physics method must not also advance the model pose; `evaluate()` is
idempotent within that character tick. A fixture that instantaneously relocates
an actor must use the motor's teleport interface, which also resets sensing.

## Profiles and movesets

Character profiles require the base locomotion, jump, dodge and swimming aliases.
Action-only profiles may be partial and cannot replace a complete character
profile. Both validate finite timing/key data, pose-only tracks, target bones and
the generated reference hierarchy/rest contract. Failed preparation retains the
working libraries and reports the invalid field or target.

Successful key and mesh validation is shared across instances. Reuse compares
the actual serialized key arrays or geometry/weight arrays, not just a resource
ID or its `changed` signal (some Godot edits omit that signal). Key times are
still checked individually because their in-memory precision exceeds serialized
pose keys. Clip headers, track paths, receiving rigs, bind transforms, sole
metadata and action timings remain live checks. Weak references avoid retaining
source resources solely for validation. Unknown/compressed key formats use the
full validator. This reduces repeat spawning work without accepting stale data.

Installed animation, mesh and skin resources remain immutable runtime assets.
Author edits before preparation; use a new appearance resource with new mesh/skin
resources for a replacement. Mutating a shared installed resource in place also
changes peers and bypasses the existing contact-geometry lifetime contract.

Each character's animation bank stages item profiles under separate namespaces.
The accepted action captures resolved names and clip references; another item
using the same authoring alias cannot substitute a different clip accidentally.
Preparation happens during setup/equipment changes, never during action sampling.
Unused registrations are released after equipment/action ownership ends. Godot's
resource cache shares clip data; this is not an asynchronous asset-streaming
system, and catalog-referenced resources can already be resident at scene load.

Combo length comes from the active moveset. The shipped sword stays A/B; a
three-entry definition can reach A/B/C. Changing movesets resets progression.
Fresh presses, one queued follow-up, payment when starting, dodge replacement,
and damage/death queue clearing retain their existing rules. See
[item authoring](ITEM_SYSTEM.md) for the resource fields.

World combat setup retains the projectile scene and prepares the existing spell
audio cues. Warden setup prepares its cues from its configured attack definitions;
the courtyard prepares its player/boss damage cues before connecting damage signals.
Audio playback creates independent players sharing an immutable prepared waveform;
reset stops those players while keeping preparation valid for the next attempt.
New cue callers must call `prepare_tone()` during setup. Each world accepts up to
32 finite cues of at most two seconds; playback does not synthesize missing cues.

## Contact geometry and runtime assets

The exact clearance evaluator shares immutable flattened mesh/binding data and
uses an independent transform palette for each character. It removes only exact
duplicate samples and zero-weight work. It does not approximate extrema with
loose bounds or rebake animation against a body. Geometry is prepared when the
body is installed; body replacement selects a new cache without affecting peers.

Support queries group vertices by their influencing bones. Conservative projected
bounds reject groups that cannot beat an already evaluated vertex; every remaining
candidate uses the original exact skinning calculation. A bound is never returned
as clearance. Weight-sum ranges, magnitude-based floating-point padding, and exact
fallback on nonfinite bounds keep rejection safe for quantized weights and scaled
frames. This reduces work without reusing a stale pose or lowering the torso from
an approximate body bound. Groups are shared; query bounds and palettes remain
per character.

Foot support likewise omits exact seam duplicates in its runtime index list.
Within one contact update the foot's orientation and ground normal stay fixed,
so its oriented support is scanned once and reused for the three translated
placement checks. It is recomputed on the next update, including weighted toe
and calf deformation; authored sole metadata and IK refresh order are preserved.

Crouch fitting keeps its existing pelvis lowering and foot targets. In deep leg
flexion it gradually adds an outward knee guide, proportional to leg length;
ordinary extension retains the original guide. This avoids the near-aligned
upward pole that made downhill knees rotate rapidly around the hip-to-ankle
axis. The correction is stateless, so resets, backwards playback and independent
actors need no cached knee history. The generic IK solver and source keys stay
unchanged. Clearance and continuous trajectories are tested separately; visual
acceptance still needs an in-game check of the resulting knee stance.

This accepted correction targets forward downhill crouching. Broader probes found
pre-existing gait-entry snaps, fast backward knees, and diagonal contact/skin
problems; the user chose to finish the targeted correction before those changes.
`run_crouch_knee_continuity.gd -- --extended-crouch-diagnostics` retains the wider
matrix and its strict limits. It currently reports those known failures and is
an opt-in diagnostic, not evidence that they have been fixed. The default suite
regresses the accepted downhill behavior, contact preservation and reset.

Body conversion now stores explicit left/right sole vertex IDs. Automatic
selection sums foot/toe influences, including normalized half-weight ties;
runtime support uses the actual skin weights. Missing, duplicate, out-of-range
or wrongly weighted support data rejects before replacing the working body. Old generated bodies
must be regenerated with their conversion config. Armor does not need body sole
metadata. Contact curves are cached, and completed jump entry blends release
their snapshots while keeping necessary clearance checks.

The production mannequin uses a generated mesh-free runtime rig preserving all
65 reference bones and animation track paths. Source GLBs remain available to
artist/build tools but are excluded from release exports. The build-only
`ual_animation_build_manifest.tres` owns the source scene dependency. Native
library builders share rig checks, provenance, serialized-key verification and
atomic output replacement; their existing command entrypoints remain usable.

## Validation and performance

See the [latest implementation results and remaining limits](validation/ANIMATION_PRIORITIES.md).
The [original reliability report](validation/ANIMATION_RELIABILITY.md) records
the historical baseline before these follow-up optimizations.

```sh
python3 tools/run_tests.py --suite run_animation_banks --suite run_skin_contacts --suite run_pose_clock
python3 tools/run_tests.py --suite run_pose_clock --render-fps 15
python3 tools/run_tests.py --suite run_pose_clock --render-fps 30
python3 tools/run_tests.py --suite run_pose_clock --render-fps 60
python3 tools/run_tests.py --suite run_pose_clock --render-fps 144
python3 tools/check_project.py --clean --release --jobs 4 --test-timeout 180
.artifacts/build/ashen-courtyard.x86_64 -- --animation-benchmark --output=/tmp/animation-benchmark.json
.artifacts/build/ashen-courtyard.x86_64 -- --animation-benchmark --counts=5,10 --scenarios=combat --measure=30 --trace-spikes --output=/tmp/combat-trace.json
```

Pose-clock tests exercise 30/60/120 Hz physics under each render rate. Additional
tests cover profile failure preservation, alias collisions, independent movesets,
distributed skin weights, and exact support within 0.00001 m of the old evaluator.

The release benchmark runs 1/5/10/15 actual UAL characters in idle, 30-degree gait,
crouch, combat/casting and physical recovery. It retains production movement,
actions and equipment, using one camera and no duplicate player HUDs. It records
frame percentiles, animation CPU sampling/display time, spawn/startup and memory.
Default warm-up/measurement is 3/5 seconds per case; `--quick` is a short smoke
check. Use native rendering without `--fixed-fps`. Headless microbenchmarks do not
establish the 60 FPS target on the reference i5-1135G7 / Iris Xe at 1280×720.
The launch flag works with the official release template, which disables scene
path overrides. Normal startup runs before the benchmark switches scenes, so its
startup measurement includes that bootstrap and instance timings use already
loaded resources. Release validation also runs the quick benchmark headlessly
to check packaging; GPU performance must still be measured separately.

The optional spike trace records frames above 33.33 ms, with intervening physics
ticks, pose CPU work, action starts and active projectiles (at most 512 per case).
Use these to narrow a dedicated profiler capture; correlation does not attribute
a stall to loading, audio, shaders or GPU work.

This pass retains existing clips and temporary adapters. Downhill knee fitting
is a separate visual correction, not an effect of the clearance optimization.
Playtest attack chains, walk-to-idle, ramps, dodge exit, swimming and ragdoll
recovery before approving the visual result.
