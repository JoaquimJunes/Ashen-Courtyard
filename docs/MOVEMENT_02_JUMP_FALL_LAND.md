# Movement 02 — jumping, falling, landing and ragdoll

Implemented in the shared character with Godot 4.6.2. This is the next playable
review milestone; crouching and other traversal mechanics have not started.

Current refinement: [cliff momentum, timed landing rolls and failed-dive ragdoll](CLIFF_DIVE_LANDING.md).

## Confirmed design

- Fresh/default bindings: **Space jumps; Alt dodges**. Existing saved bindings
  are preserved. An older Space dodge gets Jump on Alt, or the next free fallback
  key if Alt is occupied. Both actions appear in Keybindings.
- Immediate, fixed **1.2 m** jump, measured at the collision body's feet. Holding
  the button does not increase height; there is no double jump.
- **15 stamina**, **0.10 s edge grace**, **0.12 s pre-landing input buffer**.
  A committed action, insufficient resources or heavy landing prevents takeoff.
- Keep takeoff momentum with very little steering. Releasing input applies no
  ground friction in flight. Initial air acceleration is 1.5 m/s²; ground sprint
  exertion ends in the air, while its existing horizontal momentum remains.
- Jump owns a **0.10 s takeoff action**, then releases the primary action slot.
  Existing light/heavy attacks and spells explicitly support airborne use.
  Their physical ground lunge does not replace airborne momentum.
- Landing severity uses downward impact speed: `equivalent_height = speed² / (2g)`.
  At gravity 22 m/s² the jump starts at approximately 7.266 m/s.
- Up to 3 m equivalent: safe, soft landing without action commitment.
  Above 3 m through 6 m: heavy landing. Above 6 m: health damage, increasing
  linearly to full maximum health at 15 m. At/above 15 m: lethal.
  Numerical contact integration means actual drop-height boundaries have a
  small physics-tick tolerance; the configured rule is speed-based.
- Initial heavy recovery is **0.55 s**, or **0.85 s** on damaging impacts.
  Dodge immunity never prevents fall damage. A heavy impact replaces the active
  action and clears its buffered follow-up, except for the newly authorized
  timed landing roll. A failed heavy cliff dive now ragdolls; ordinary walking/
  jumping failures retain heavy recovery. See the refinement above.
- Approved Quaternius source poses are retargeted to the existing knight.
  Landing playback starts at actual contact. Soft landings are shallower/faster;
  heavy landings use the deeper pose and longer recovery.
- An accepted combat hit **while descending** triggers ragdoll. Rising/grounded
  hits retain ordinary hurt behavior. A lethal landing also triggers ragdoll.
  Surviving ragdolls settle, then automatically get up if standing space is clear.

## Ownership and code

| Component | Owns |
| --- | --- |
| `features/abilities/jump_definition.gd`, `data/jump.tres` | Shared height, cost, buffer and takeoff timing |
| `features/abilities/ability_controller.gd` | Jump acceptance/launch request; primary action and landing/reaction commitment |
| `features/character/character_motor.gd` | Gravity, collision, weak air steering, step settlement and physical-body handover |
| `features/character/movement_coordinator.gd` | Ground/air transitions, edge grace, consumed jump and actual landing notification |
| `features/character/landing_response.gd`, `data/landing.tres` | Impact classification and one damage request per landing |
| `features/presentation/jump_presentation.gd` | Pose selection and blending from observed movement/landing state |
| `features/reactions/reaction_controller.gd` | Descending-hit policy, physical reaction and recovery lifecycle |
| `features/reactions/ragdoll_driver.gd`, `knight_ragdoll.tres` | Per-instance physical rig, authored body dimensions/masses/joints, pose handover |
| `features/presentation/get_up_presentation.gd` | Authored face-up/down supported poses blended from the physical snapshot |
| `features/laboratory/fall_test_rig.tscn` | Reusable adjustable drop platform; no character physics |

Animation never supplies the jump's displacement. A successful automatic step
keeps walking steering for its brief, bounded capsule-settling interval; it does
not acquire ordinary airborne steering or an extra jump impulse. This preserves
the existing diagonal ramp-entry behavior.

The input buffer waits only for an explicitly supported physical requirement.
It spends nothing until acceptance. Ragdoll/get-up rejects buffered actions.
Definitions remain shared, read-only authoring Resources; clocks, poses, physics
bodies, health and consumed-input state belong to each character instance.

## Ragdoll behavior

See [the ownership decision](decisions/007-ragdoll-handover.md).
The knight uses ten physical bodies with hinge/cone constraints and collision
against the environment. Bones forward damage to their explicit character
receiver, preserving the normal strike deduplication and health/death signals.
The original capsule is disabled while physical bones own motion. Only the motor
updates the logical character position used by the camera and other systems.

A surviving ragdoll must remain settled for 0.30 s, then pass a nearby floor and
standing-capsule clearance query. Get-up takes 1.20 s (approved option B). Physics collision is disabled
before the capsule is restored, preventing self-collision during handover. Loss
of support or lethal damage during get-up returns to physical simulation.

The get-up now uses original Resource-authored hand-plant, kneeling and rising
poses, with separate face-down and face-up entries. Contact constraints keep the
supporting hand and boot anchored while the pelvis rises. See
[supported recovery, architecture and latest clips](GET_UP_RECOVERY.md).

Courtyard death retains its retry screen while the physical body continues.
A lethal fall in the lab shows the ragdoll for 2.5 s before station reset; a manual
reset cancels that delayed recovery. All active bodies, action ownership and
presentation state are released on reset/unload.

## Run and review

1. Press **F5** for the courtyard, or open `scenes/movement_lab.tscn` and press **F6**.
2. Use **Esc → Go to station → 02 Jumping** for gaps, platforms and ceiling tests.
3. In the lab Esc menu, choose a drop height and **Start fall test**. Walk forward
   off the platform. **Drop + hit** enables a temporary combat test and applies
   one five-damage hit when descending, exercising the actual damage/reaction path.
4. **F3** displays vertical speed, impact severity/equivalent height and damage.
5. Reset Station restores resources and control. Saved camera and binding settings
   remain in use; use Keybindings → Restore defaults to opt into Space/Alt.

Review footage: [jump](jump-02/jump.gif),
[heavy landing](jump-02/heavy_landing.gif),
[falling hit and get-up](jump-02/hit_recovery.gif),
[lethal landing](jump-02/lethal_landing.gif).
The source references in `docs/jump-02/source-*.png` are Quaternius mannequin
poses, not gameplay recordings. The other footage is rendered from the actual
shared character on Iris Xe. These captures are not a release performance benchmark.

## Validation

The pre-change baseline was **1,347 checks / 22 suites**. The jumping/ragdoll baseline report (**1,553 checks / 25 suites**)
is [jump-ragdoll-final.json](validation/jump-ragdoll-final.json).
Focused suites cover apex/timing at 30/60/120 Hz, all eight momentum directions,
weak air braking, ceilings, grace/buffering, insufficient stamina, airborne
attacks/casting, heavy commitment, damage, repeated reset, two-character isolation,
keybinding migration and lab fixture selection.

Ragdoll checks exercise descending/rising/grounded triggers, lethal impact,
automatic recovery at 30/60/120 Hz, continued vulnerability, one damage event per
physical fall, pause, low ceilings, support loss during get-up, lethal recovery
interruption and repeated reset/unload. Existing camera/combat/dodge/ramp checks
remain part of the same runner.

```sh
python3 tools/run_tests.py --report docs/validation/jump-ragdoll-final.json
```

Review feel and the prototype get-up before changing another mechanic.
