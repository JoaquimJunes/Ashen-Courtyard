# Native UAL actions

The player uses unchanged source clips on the canonical 65-bone UAL skeleton.
The Warden retains the legacy Knight. No modeling or source keyframe edits are
part of this change.

| Presentation | Source | Runtime behavior |
| --- | --- | --- |
| Sword idle | UAL1 `Sword_Idle` | Selected while grounded with the sword actually in the right hand; stowing or being airborne leaves that stance. Playback advances the walk-to-idle blend normally and wraps only at the clip endpoint, per character, without changing the shared clip's loop flag. |
| Heavy sword | UAL1 `Sword_Attack` | Source strike 0.333333–0.5 s maps to the existing 0.65 s windup / 0.22 s damage window / 0.55 s recovery. |
| Spell preparation | UAL1 `Spell_Simple_Enter`, `Spell_Simple_Idle_Loop` | Enter occupies 70% of the existing windup; idle occupies the rest. Godot imports the loop under `Spell_Simple_Idle`. |
| Spell release and recovery | UAL1 `Spell_Simple_Shoot`, `Spell_Simple_Exit` | Shoot starts at the gameplay release moment, uses 55% of recovery, then exit uses 45%. |
| Mantle | UAL2 RM file, `ClimbUp_1m` | Samples through source time 0.5 s, then blends the top pose into idle during the remaining accepted action. Authored root displacement is consumed locally rather than added to collision movement. |

Left attack is **tap for light / hold for heavy**. A quick tap (under 0.15 s)
requests light; holding past that detection window commits the ordinary heavy
action and pays its cost once. The native sword pullback (source 0–0.333333 s)
plays across the heavy's 0.65 s windup: this is the charge itself. The strike
opens automatically at the end, without replaying the windup.

Releasing during that pullback cancels without attacking or refunding stamina.
A nonlethal combat hit before charge completion applies health damage, cancels
the heavy and blends the displayed pose back to guard over 0.15 s. Death and
physical reactions retain priority. Once the strike opens, ordinary commitment
and damage-reaction rules apply. Holding/releasing after the strike adds no
attack. Pause freezes charge; releasing in a menu cancels it on resume. Reset,
water entry and unload clear charge ownership. The separate heavy binding still
starts the same heavy directly, with the same interruptible pullback.

Casting remains **tap-to-cast**. Bolt keeps 0.4 s windup, Burst 0.8 s; both keep
0.4 s recovery. The shoot clip begins with the casting hand already extended,
so its first frame aligns with actual spell release. Animation cannot create
projectiles, spend resources or move the actor. Airborne sword/spell actions keep
the flight pose in the lower body. Damage, death, ragdoll, reset and unload release
the active pose. Equipment still stows during casting and climbing.

## Mantle finish

The source clip lasts about 0.667 s; its final 0.5–0.667 s returns to a stride
after the pull-up. The editable `mantle_source_end_seconds = 0.5` in the UAL
animation profile selects the last climbing pose. Playback keeps its existing
rate up to that pose, then blends into idle through the rest of the mantle.
This removes the extra step at the top without changing the imported keys or the
motor's lift, over and stand timing. Hand contacts still release with the action;
the motor continues to reject blocked destinations.

## Slope contact

The contact solver keeps a consistent knee bend direction and eases support
strength around the source animation's contact phases on inclines. Contact
weights also blend between walking/running gaits; changing gait phase defers pose
application until the normal animation blend.

When a stride reaches too far, the solver brings its foot target closer along the
support surface. A second ground probe verifies that the adjusted target still
has support, including near edges. The pelvis lowers only for remaining reach
shortfalls. Current defaults limit that adjustment to **8 cm**, reserve **4 cm**
of leg reach to keep knees from locking, and cap added slope lean at **6°**.
This keeps the torso close to its authored height while the feet adapt to the
ground. These presentation settings do not change movement speed or collision.

Crouch-walk keeps its original contact weights. A separate follow-up remains for
fast knee motion during tightly folded downhill crouch steps; its clearance,
body-height and stopping checks do not establish smoothness throughout that gait.

Terrain foot placement runs only for grounded walk, jog, sprint and crouch-walk.
Idle, crouch idle and actions clear the previous foot locks and pelvis correction.
Stopping blends from the last displayed gait pose without continuing terrain IK.
Sword attacks, casting and mantle retain their authored leg motion. Native mantle
keeps ledge hand contacts, with no separate knee/ankle placement against the wall.

The motor also covers the current frame's projected downhill descent while
already grounded. Extra snap is bounded by capsule radius and requires continuing
walkable support at the midpoint and destination. Jump launch, committed actions,
cliffs and gaps retain their existing departure rules. This fixes the 30 Hz case
where one downhill sprint step exceeds Godot's default 10 cm snap distance.

## Files and rebuilding

`features/presentation/data/ual_animation_profile.tres` chooses the aliases,
editable sword/spell timing definitions and mantle source endpoint.
`sword_attack_presentation.gd` and `spell_presentation.gd` own per-character
playback. The native mantle helper works with the existing traversal presentation
and collision path.

`tools/build_ual_action_library.gd` verifies both source rigs and copies seven
animations into `assets/animations/ual/anim_ual_native_actions_library_v01.tres`. Validation compares
all serialized tracks, keys, interpolation, duration and loop metadata before
atomically replacing the output. Original scene imports stay available.

```sh
.artifacts/toolchain/godot --headless --path . --script tools/build_ual_action_library.gd
python3 tools/run_tests.py --suite run_ual_actions --suite run_ual_sword_attacks --suite run_light_attack_buffer
python3 tools/run_tests.py --suite run_native_mantle --suite run_ramp_contacts --suite run_foot_placement_scope
python3 tools/check_project.py --clean --release
```

The requested root-motion clip comes from the official Standard archive's
`Unreal-Godot/UAL2_Standard_RM.glb`. `_RM` is the file variant; its internal clip
name is `ClimbUp_1m`. It is not the similarly named non-root-motion clip.
[Vendor provenance](../assets/third_party/quaternius/ual2/ANIMATIONS.md) records its
origin, license and hash.

## Playtest

1. Press **F5**. Stand still with the sword held, then walk and stop. Check the
   sword grip and transition back to the armed idle.
2. Use the configured heavy-attack button. Check the windup, strike and return;
   light A/B chaining should behave as before.
3. Cast each spell once. Check enter, preparation, shoot and exit, sword stowing,
   restoration, interruption and casting while airborne.
4. In Test Grounds, mantle a supported wall. Check hand contact, knee lift and
   foot clearance, then a smooth return to standing without an extra stride at
   the top. Try interruption and a blocked destination; animation must not
   bypass collision.
5. Walk, jog and sprint uphill/downhill on the 30° ramp, then stop or jump.
   Check that the torso keeps a natural height, knees stay stable and feet plant
   and release smoothly. Repeat at ramp edges and while changing speed; stopping
   should return smoothly to idle without keeping a slope crouch.

Jump/fall/land, directional dodges, healing/hurt, ledge grab/hang/shimmy and get-up
remain explicitly temporary adapters. Automated checks establish functionality;
the player's visual review establishes whether the movement feels right.
