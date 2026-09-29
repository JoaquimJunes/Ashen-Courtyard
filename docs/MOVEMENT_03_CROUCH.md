# Movement 03 — crouching

Implemented for in-game review. Crawling, sliding and stealth remain deferred.

## Approved behavior

- Tap the remappable Crouch / stand binding (fresh default **C**). Holding it does
  not repeat the toggle. Existing saved bindings are preserved; if C is occupied,
  migration picks an unused key. Controls lists this under Movement.
- Move at 2 m/s with ordinary grounded stamina regeneration and no crouch cost.
  Lock-on keeps the body facing the enemy. Free movement faces travel.
- The collision capsule immediately becomes **0.96 m** tall, feet anchored; the
  visual transition still blends over 0.20 seconds. Crouch height is capped at 1 m.
- A nominal **1.00 m** tunnel is usable, including local floor or ceiling
  variations reducing clearance to **0.98 m**. Collision margins remain enabled.
  Smaller passages block safely; there is no crawling mechanic. Both supported
  appearances lower the pelvis and bend the legs to keep the visible body below
  the capsule height while retaining sampled foot contacts. Equipment is separate.
- Standing requires full-volume clearance. A blocked toggle stays crouched and is
  discarded; leaving the tunnel does not stand automatically. Press again.
- Sprint, jump, dodge, melee, spells and healing stand first when clear. Committed,
  disabled, unaffordable or blocked requests do not pay or launch. Holding Sprint
  continues to request sprint, so it can stand once space is available.
- Falling retains crouched collision and the normal momentum/impact calculation.
  Soft landings remain crouched. Heavy recovery tries to stand, retaining the low
  collider if blocked. Falling hits/lethal landings use the existing ragdoll;
  standing get-up still requires supported, clear space.
- Reset restores standing, resources and camera follow. Crouching does not occupy
  the committed action slot after the toggle has resolved.

## Ownership and request flow

1. Keyboard or `CharacterIntent.action = &"crouch"` requests the shared lifecycle.
2. `AbilityController` resolves `data/crouch.tres` and validates commitment/ground.
3. The lifecycle's `prepare_start` hook performs physical preparation before payment.
   Crouch toggles `CharacterPosture`; an ability declaring `requires_standing` asks
   the same component to stand. Validation also checks clearance without mutating it.
4. `CharacterPosture` owns persistent stance. It requests shape
   changes from `CharacterMotor`; only that motor edits collision. Temporary ledge
   tucks keep their existing automatic restore behavior, unlike persistent crouch.
5. Player composition supplies the posture speed to the existing motion resolver.
   Movement modes remain grounded/airborne/etc.; no crouch mode or permanent action
   is added. Posture tuning is a shared Resource, runtime state is instance-local.
6. `CrouchPresentation` reads posture, samples animation and blends the camera anchor.
   Animation does not move the body. Diagnostics reports stance and request failures.

Files: `features/character/character_posture.gd`, `posture_definition.gd`,
`data/knight_posture.tres`, `features/presentation/crouch_presentation.gd`.
The existing action lifecycle, motor, player composition and input settings are the
integration points; the courtyard and laboratory use the same player scene.

## Animation source and limits

The UAL player uses its native UAL crouch idle/walk clips. The legacy Knight uses
KayKit Character Animations 1.1, CC0, Medium `Crouching`. Original GLB is unchanged.
`tools/build_crouch_animations.gd` bakes `assets/animations/anim_legacy_knight_crouch_walk_v01.tres` and
`crouch_idle.tres` onto the existing 14-bone Knight. It maps torso/head/arms, removes
world travel, and uses the existing two-bone IK solver to adapt the longer legs with
forward-bending knees. Idle uses a sampled upper-body pose with both feet planted.
Backward movement reverses the walk cycle. This first pass has no separately authored
sideways crouch clips; lateral footwork and general feel need in-game feedback.

The source has no dedicated enter/exit clips. Transitions blend captured Knight poses
for 0.20 seconds. The source assets and animation keys remain unchanged. Runtime clearance adaptation
uses the skinned body height and two-bone leg IK after sampling. Completed fitted
poses blend when stopping, so the adjustment is not applied recursively to the
previous frame. A per-rig torso lean keeps the legacy Knight’s armored shins clear
of the floor; knee bend directions remain above the support. This keeps
the feet grounded and fitted damage regions follow the corrected bones. The motor
sweeps the whole capsule upward and forward when stepping, including roof clearance.

## Run and review

Use **F5 / Run Project** for the courtyard, or open `scenes/movement_lab.tscn` and
press **F6**. The courtyard menu also offers Test Grounds. Esc → Go to station →
03 Crouching. The active binding is in Settings → Controls → Movement.

Review:

- Walk, stop, reverse and strafe while locked on; inspect knees, boots and sword.
- Cross the entire 1.0 m, 1.2 m and 1.5 m tunnels on each camera shoulder. Try C, Sprint, Jump, Dodge,
  attacks and healing under its roof; no standing action may launch or spend.
- Walk back out, stay crouched, and press C to stand. Check the lowering blend while
  approaching the entrance, especially when pressing C very late.
- Check small falls, heavy recovery, damage interruption, pause/resume and resets.
- Hold the crouch control for 0.5 seconds to enter the [implemented crawling stance](CRAWLING.md).

The `run_tunnel_clearance` suite crosses the full laboratory 1 m tunnel in both
directions at 30/60/120 Hz and both shoulder cameras. It adds separate 2 cm floor
and ceiling variations, stop/reverse/stand/sprint attempts and a 0.85 m obstruction
with safe retreat. Run it for UAL and with
`--player-model res://scenes/models/psx_knight.tscn` for legacy compatibility.

Automated suites: `tests/run_crouch.gd` (30/60/120 Hz, actions/resources, collision,
falling, ragdoll, both level hosts, key migration, two instances and resets) and
`tests/run_crouch_poses.gd` (baked bounds, forward knees, planted idle feet and blends).
Full validation report: `.artifacts/tests/crouch-final.json` (local ignored artifact).

Validation on 24 September 2026: **3,121 checks across 53 suites passed**, including
267 new crouch/pose checks. Existing baseline was 2,853 checks across 51 suites;
one existing menu suite also gains coverage from the added binding. Baked poses were
inspected in a virtual display; this is visual verification, not a hardware
performance benchmark or a substitute for the user's combat-feel review.

A final camera-height correction caps the crouched pivot below the low roof while
preserving saved settings. Its follow-up passed **379 checks across 4 suites**
(crouch, camera, fast camera and lock movement), including both shoulders at camera
heights 1.2/1.65/2.2 m. Report: `.artifacts/tests/crouch-camera-final.json`.
