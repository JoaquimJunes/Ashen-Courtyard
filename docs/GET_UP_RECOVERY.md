# Supported recovery — approved option B

The knight gets up in **1.20 seconds after settling**, replacing the previous
0.85-second interpolation toward standing. This is the recovery after a surviving
ragdoll; ordinary heavy landing and successful timed landing rolls retain their
existing behavior.

- **Face down:** brace on the free hand, draw a knee underneath, plant the forward
  boot, transfer weight, rise and bring the trailing leg into stance.
- **Face up:** turn onto the side and plant the free hand, then move into the kneel
  and rise. Side landings choose the closer face-up/down branch once at recovery.
- The sword hand stays away from the supporting hand. Recovery aligns with the
  settled torso instead of the character's facing before the fall.
- The first pose preserves the actual physical bones. A short blend joins the
  authored sequence; the last portion blends back to idle. The character remains
  vulnerable and committed throughout, including after a nonlethal hit.

The original hand/knee/foot poses are authored in Godot Resources for the existing
knight. No new animation assets were downloaded.

## Ownership and files

```text
ReactionController: wait for settlement; choose recovery; own 1.20 s clock
    -> CharacterMotor: validate floor/headroom; restore capsule and facing
    -> RagdollDriver: stop physical collision; supply captured world pose
    -> GetUpPresentation: blend captured pose; sample authored contacts
        -> LimbIK: rotate joints to hand/foot targets without stretching bones
    -> AbilityController: release committed action when recovery completes
```

| File | Responsibility |
| --- | --- |
| `features/reactions/reaction_controller.gd` | Variant/heading selection, lifetime, loss of support and lethal interruption |
| `features/reactions/ragdoll_definition.gd` | Duration, rig orientation axes and presentation definition reference |
| `features/character/character_motor.gd` | Safe standing placement and support normal; sole owner of collision-body movement |
| `features/presentation/get_up_presentation.gd` | Per-instance snapshots, playback and support-plane clearance |
| `features/presentation/limb_ik.gd` | Stateless two-bone constraint solver for presentation |
| `features/presentation/get_up_definition.gd`, `get_up_keyframe.gd`, `knight_get_up.tres` | Shared, read-only pose/contact definitions; normalized key times, pelvis, torso and limb targets |
| `features/character/player.gd` | Prevent ordinary hurt from taking the reaction's action slot; damage still applies |

The same pose and knee directions are used before and after contact correction.
Switching knee directions when the foot plants causes a visible joint snap even
if the foot itself stays still. Clearance correction is followed by the same limb
constraints so a lifted pelvis cannot drag a planted hand or boot off its anchor.

The sampler contains knight bone-name mapping; another skeleton needs its own
mapping and pose definition. The reaction lifecycle and motor do not need to be
copied into an enemy or level. Mutable captures, anchors and clocks belong to each
character, never to the shared Resources.

## Behavior under interruption

The existing 0.30-second settlement and standing-clearance checks still precede
recovery. A low ceiling keeps the character physical. Losing support during
get-up returns to ordinary physical falling. Lethal damage returns to a dead
ragdoll. Pause freezes playback. Completion, reset, death and unloading release
the appropriate action, snapshots and physical ownership.

## Review in Godot

Open `scenes/movement_lab.tscn` and press **F6**, or use **F5 → Esc → Test Grounds**.
In the laboratory menu select a **3 m drop → Drop + hit**, then walk off the
platform. For the dive case use **8 m → Start fall test**, dive forward off the
edge and omit the landing skill check. Surviving falls recover automatically.
Reset the station to repeat. Camera settings and keybindings remain unchanged.

Pose previews below use the production sampler with deliberately staged lying
starts; they are not recordings of physics falls. The third clip is a real
8 m cliff dive, failed timing check, ragdoll and recovery.

![Face-down supported recovery](get-up/face_down.gif)
![Face-up supported recovery](get-up/face_up.gif)
![Actual cliff fall and recovery](get-up/fall-recovery.gif)

## Validation

The new `run_get_up` suite adds **92 checks**: face-up/down selection and heading,
exact world-pose handover, continuous joint paths, support-plane clearance and
planted contact errors at **30/60/120 Hz**, on flat ground and a **20° support
plane**. Actual physics checks cover duration, pause, surviving damage, action
commitment and completion cleanup. Existing ragdoll tests cover low ceilings,
loss of support, lethal hits, repeated resets and unloading.

The slope pose tests inspect presentation against a support plane; they do not
claim every irregular stair or moving surface is a solved contact arrangement.
The real cliff capture ran through Godot 4.6.2 Compatibility on Iris Xe; this is
visual validation, not a release performance benchmark.

Full results: [get-up-final.json](validation/get-up-final.json).

```sh
python3 tools/run_tests.py --report docs/validation/get-up-final.json
# Native render scripts (run with the installed Godot executable):
godot --path . --fixed-fps 60 --resolution 960x540 --script res://tests/render_get_up.gd
godot --path . --fixed-fps 60 --resolution 960x540 --script res://tests/render_cliff_failure.gd
python3 tools/export_get_up.py
```
