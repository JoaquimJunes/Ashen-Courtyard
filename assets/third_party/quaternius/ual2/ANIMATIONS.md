# Universal Animation Library 2 — Standard inventory

- Official source: https://quaternius.itch.io/universal-animation-library-2
- Official upload: 17958478; downloaded 24 September 2026 (UTC).
- License: CC0 1.0 Universal; original README and license are preserved here.
- Imported source: `UAL2_Standard.glb`, unchanged, without root motion; extracted
  from the archive's `Unreal-Godot/UAL2_Standard.glb`.
- Archive SHA-256: `4008ea208a604773a2b2177d965f0f5d3195498b5bf838c3f5785d68e95f2a68`.
- Model SHA-256: `8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8`.
- Root-motion source installed 26 September 2026 from the same official upload
  and identical archive: unchanged `Unreal-Godot/UAL2_Standard_RM.glb`.
- Root-motion model SHA-256:
  `814eee878f82934992d3ea746c539df25e981487109c591f5efbb8dd03286f99`.
- The root-motion file's internal clip remains `ClimbUp_1m`; the `_RM` suffix
  identifies its source file. It is the root-motion variant requested as
  `ClimbUp_1M_RM`, not the stationary clip from `UAL2_Standard.glb`.
- Imported and included in the release dependency set. The player's light combo
  uses `Sword_Regular_A`, `Sword_Regular_B` and their matching `_Rec` clips.
  Mantling uses the root-motion file's `ClimbUp_1m`. Other UAL2 clips remain
  unintegrated; Library 1 and both source GLBs are unchanged.

## Current sword integration

`tools/build_ual_combat_library.gd` validates the original 65-bone rig and extracts
the four clips to `assets/animations/ual/native_combat.tres`, preserving track
data, keyframes and playback metadata. Runtime source sampling follows the
existing gameplay windup, active and recovery phases; it does not change damage
timing or drive character movement. See
[integration and playtest](../../../../docs/UAL_SWORD_ATTACKS.md).

## Native mantle extraction

`tools/build_ual_action_library.gd` verifies the original 65-bone rig and saves
the root-motion `ClimbUp_1m` unchanged as `climb_up_1m_rm` in
`assets/animations/ual/native_actions.tres`, alongside the selected UAL1 action
clips. It verifies every serialized key, track, duration and loop setting before
replacing the library. The clip lasts 0.666667 seconds and its root travels from
`(0, 0, 0)` to `(0, 1, 1.676378)` in imported Godot coordinates. Runtime
presentation removes this root displacement before fitting the sampled pose to
the existing gameplay-owned mantle path; the animation does not move the capsule.

## Crouch, crawl and future sliding

This Standard file has no crouch or crawl clips. Library 1 already includes
`Crouch_Idle_Loop` and `Crouch_Fwd_Loop`; hands-and-knees crawling still needs
an animation source. Library 2 includes `Slide_Start`, `Slide_Loop`, and
`Slide_Exit` for the future sliding milestone. These are source animations,
not implemented game mechanics.

The online viewer includes clips outside the Standard downloads. Godot may
strip loop suffixes from imported animation names; the list below records
exact names from the source GLB.

## Included clips

43 clips, including the T-pose:

- `A_TPose`
- `Chest_Open`
- `ClimbUp_1m`
- `Consume`
- `Farm_Harvest`
- `Farm_PlantSeed`
- `Farm_Watering`
- `Hit_Knockback`
- `Idle_FoldArms_Loop`
- `Idle_Lantern_Loop`
- `Idle_No_Loop`
- `Idle_Rail_Call`
- `Idle_Rail_Loop`
- `Idle_Shield_Break`
- `Idle_Shield_Loop`
- `Idle_TalkingPhone_Loop`
- `LayToIdle`
- `Melee_Hook`
- `Melee_Hook_Rec`
- `NinjaJump_Idle_Loop`
- `NinjaJump_Land`
- `NinjaJump_Start`
- `OverhandThrow`
- `Shield_Dash`
- `Shield_OneShot`
- `Slide_Exit`
- `Slide_Loop`
- `Slide_Start`
- `Sword_Block`
- `Sword_Dash`
- `Sword_Heavy_Combo`
- `Sword_Regular_A`
- `Sword_Regular_A_Rec`
- `Sword_Regular_B`
- `Sword_Regular_B_Rec`
- `Sword_Regular_C`
- `Sword_Regular_Combo`
- `TreeChopping_Loop`
- `Walk_Carry_Loop`
- `Yes`
- `Zombie_Idle_Loop`
- `Zombie_Scratch`
- `Zombie_Walk_Fwd_Loop`
