# Grounded side and backward rolls

**20 September 2026.** The user selected the existing left/right/back pose
references and **0.70-second** playback. These directions now start rolling on
the floor immediately, with no physical hop. The adaptive forward dive remains
unchanged. These rolls also support the current jumping/falling/landing systems.
The cliff-momentum correction below fixes their separate movement executor.

## Behavior and controls

Restart the game, open **Esc → Character Test Grounds**, and tap **A/D/S + Dodge** (Alt for fresh defaults; follow saved bindings)
from rest to try left/right/back. Direction is relative to the knight's facing at
acceptance, and stays fixed through recovery; holding movement first can turn
the knight. Optional hub practice provides a lock-on target. Use **F3** for phase,
grounded state and travel, and **F4** to inspect without PS1 effects.

The old hop and comparison switch have subsequently been removed. Side/back
rolls and the adaptive forward dive are shared by the courtyard, laboratory and
preview. Standing still selects the forward dive everywhere.
See [the shared-dodge review](UNIFIED_DODGE.md).

| Setting | Side/back roll |
| --- | --- |
| Playback | 0.70 s of supported ground contact |
| Flat-ground requested reach | 4.34 m |
| Physical upward launch | None |
| Stamina | 25, paid once |
| Immunity | 0.06–0.32 s from action start |
| Entry blend | 0.08 s |
| Braking | Smooth braking over the final 30% |

Existing step-up supports obstacles up to 0.60 m with full-capsule headroom
checks. The roll does not gain a flight arc to cross a gap. Losing the floor
causes ordinary falling, pauses roll playback and blends to the compact air pose.
Landing resumes the remaining animation without a new lift or immunity window.
Ground braking and playback both pause in the air. The roll retains its actual
horizontal speed when it leaves the edge, even after 0.70 s or exhaustion of the
flat-ground distance budget. A roll already braking does not accelerate again.
Air requests still consume the remaining ground-travel budget, including against
walls; landing cannot release stored blocked travel. Heavy impacts and the timed
landing skill use the shared landing response. Use the adaptive forward dive for
the tested raised-platform/gap crossings.

## Code ownership

- `features/abilities/data/dodge_ground.tres` is the shared, editable definition.
- `ability_controller.gd` selects the definition using body-relative direction
  and retains the common cost, buffering, interruption and release lifecycle.
- `ground_roll.gd` owns per-instance travel timing, integrates its braking curve
  and captures per-instance edge speed for falling. It requests horizontal velocity
  through the motor and never moves the collision body directly. Reset, damage,
  death and unloading clear this retained speed with the rest of action ownership.
- `character_motor.gd` remains the sole body mover; the player enables its
  existing grounded step handling while this action is active.
- `character_presentation.gd` starts the pose; `scripts/psx_knight.gd` plays the
  original `roll_left.tres`, `roll_right.tres` and `roll_back.tres` clips.

The referenced clips already contain their own hip and limb motion. Those poses
are preserved; the additional 0.60 m collision-body hop is removed. No source
asset downloads, rebakes or new skeletons are involved. Shared definitions do
not contain mutable action clocks.

## Validation

**1,812 checks across 28 suites pass.** The latest falling-roll validation is [roll-falling-final.json](validation/roll-falling-final.json).
The additional `run_roll_falling` suite covers five side/back headings at 30/60/120
Hz, late edge departure during braking, walls, timing-skill acceptance, pause,
ragdoll interruption, reset and unloading. Flat-ground roll checks still verify
0.70 s, 4.34 m, no hop and one-time costs.

Historical baseline after removing the legacy hop: **1,347 checks / 22 suites**.

At the original ground-roll change: baseline **947 checks / 21 suites**, updated
**1,175 checks / 22 suites**, with
no engine/script errors. The new 228-check suite covers left/right/back and back
diagonals with combat enabled and disabled at **30/60/120 Hz**: immediate grounded clip
playback, no physical lift on flat ground, 0.70 s duration, 4.34 m reach, fixed
heading, resource spending and immunity. It also covers steps, blocked headroom,
falls, walls, input buffering, pause, damage, death, reset and unloading.

Existing reference-pose clearance and animation continuity checks pass. Forward
dive and raised-gap, courtyard combat, camera, keybinding, running and laboratory
regressions pass. Existing tests that required side/back hops now assert the new
grounded behavior. The subsequent cleanup retires legacy-hop-only suites;
current checks cover the shared dive and ground rolls.

[Machine-readable report](validation/ground-roll-final.json).

![Actual player rolls](ground-rolls/ground-rolls.gif)

Native frames use the real character, action and collision motor, recorded at
60 Hz on Iris Xe with Godot **4.6.2.stable.official.71f334935**, Compatibility.
The GIF includes short holds between clips; the roll itself plays at normal
speed. This is visual verification, not a release performance benchmark.

To rerun checks: `python3 tools/run_tests.py --suite run_ground_roll`.
To recapture: run Godot with `--fixed-fps 60 --path . --script
res://tests/render_ground_roll.gd`, then `python3 tools/export_ground_rolls.py`.


## Cliff-momentum review

The earlier forward-dive fix did not cover `ground_roll.gd`: that executor's
travel timer still ran out while its animation was paused in the air. It now
captures collision-resolved horizontal speed at each edge departure, keeps that
request until contact, and pauses only ground braking/playback. The existing
motor handles gravity and collision. No definition gains mutable state.

In the Test Grounds, choose **Esc → 8 m drop → Start fall test**. From rest, tap
left/right/back with the displayed Dodge binding to roll off a side of the
platform. The roll should retain horizontal motion all the way to the lower
floor. Repeat with a late Dodge press to check the existing timed landing skill.

[Native left/right/back cliff footage](ground-rolls/falling-rolls.gif).
Run `python3 tools/run_tests.py --suite run_roll_falling --suite run_ground_roll`
for the focused checks. `tests/render_roll_falling.gd` captures the shared player,
without a separate preview physics implementation.

## Shared motion architecture follow-up

Airborne retention and distance accounting now live in the shared
`MotionResolver` / `MotionBudget`, used through `CharacterSimulation` by the
player and Warden. The roll executor keeps its phase and pose clocks. See
[the implementation walkthrough](MOTION_PIPELINE.md),
[latest validation](validation/motion-contract-final.json) and
[new native capture](motion-contract/right-roll-falling.gif).
