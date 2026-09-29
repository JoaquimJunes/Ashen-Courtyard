# UAL2 player sword attacks

The normal player now uses the UAL mannequin with native UAL2 regular-sword A/B
light attacks, following Neth's explicit approval to switch models. The Warden
keeps the legacy Knight. No Blender models or source artwork are changed.

## Playtest

1. Restart the game and press **F5** in Godot to run the courtyard.
2. With default controls, **left-click** for A, then tap again early in its swing.
   B should follow directly, without A's recovery animation between swings.
   Press during B to continue with A. Let the combo expire to return to A.
3. Hold the button: only one attack should play. Press several times during one
   swing: only one follow-up should be remembered. Stop pressing and check that
   the last swing plays its matching recovery.
4. Queue a follow-up, then dodge: the sword follow-up should be replaced by a
   dodge after the current attack finishes. Check low stamina and taking damage:
   neither should cause a delayed attack after the character becomes available.
5. Try attacking while moving, locked on, airborne and immediately after landing.
   Check swing readability, sword grip, feet and the return to locomotion.
6. Check interruption, death/retry and travel to the Test Grounds. Climbing,
   casting and healing still stow the sword and restore the requested layout.

The normal player's loadout contains only its existing sword. For armor, shield,
bow-marker and socket controls, open `scenes/ual_validation.tscn`, press **F6**,
then **Esc → Appearance**. These layouts do not enable bow/shield combat.
Automated checks cover behavior; Neth's playtest judges the visual result.

## Light-attack queue and timing

Each light attack remembers **one fresh follow-up press** for the rest of that
attack. Additional presses during the same attack do not reserve a third swing,
and holding the button does not repeat light attacks. Light input is resolved on
release of a quick tap; holding starts heavy sword pullback instead. Releasing
during that charge cancels without a swing (see
[attack controls](UAL_ACTIONS.md)). The sequence alternates
**A → B → A → B** while the player keeps pressing during successive swings.

A queued follow-up starts after **0.22 s windup + 0.16 s active damage window +
0.08 s follow-through = 0.46 s**. The light action's `chain_after_active` setting
owns that follow-through duration. Presentation blends from the current swing
into the next, skipping the stopping recovery. This intentionally makes a chained
combo faster than separately completed attacks; damage windows and stamina costs
remain unchanged. Without a follow-up, the action lasts its full **0.66 s** and
plays its matching `_Rec` clip before returning to locomotion. A late press after
0.46 s starts the follow-up on the next physics tick, blending from whatever
recovery pose is already visible.

Stamina is charged when the next attack starts, never when its press is queued.
If stamina is insufficient at the transition, the follow-up is discarded and the
current attack finishes its normal recovery. It cannot start later when stamina
returns. A dodge replaces a queued light attack and waits for the current
attack's full 0.66 s to finish; its ground requirement is checked again when it
starts. A later fresh input can replace the pending request.

Damage interruption, death, ragdoll, reset and scene unload clear the queue.
Other actions retain their existing short input windows (**0.20 s** for heavy
attacks and casting); this persistent follow-up queue applies only to light
attacks and their replacement dodge.

## Source clips and ownership

`assets/third_party/quaternius/ual2/UAL2_Standard.glb` remains unchanged.
`tools/build_ual_combat_library.gd` validates its skeleton against the canonical
65-bone UAL reference and writes `assets/animations/ual/anim_ual_native_combat_library_v01.tres` from
`Sword_Regular_A`, `Sword_Regular_B` and their matching `_Rec` clips. Original
tracks, keys and playback metadata are preserved; the clips are shared between
characters while playback state remains per instance.

`features/presentation/data/ual_animation_profile.tres` orders the two light
attacks. Its `attack_animation_definition.gd` resources declare source-time strike
landmarks: A uses **0.166667–0.3 s**, B uses **0.2–0.3 s**. Presentation maps each
clip's preparation, strike, follow-through and recovery onto the existing action
timeline: **0.22 s windup, 0.16 s active, 0.28 s recovery**. Entry/exit blends are
**0.06/0.08 s**. The first 0.08 s after the active phase provides the follow-through
for a queued chain; the remaining stopping recovery is used when the combo ends.
Editing a source landmark changes how the pose fits that timeline; it does not
change the damage window, action cost or collision movement.

`features/presentation/sword_attack_presentation.gd` samples from the committed
gameplay clock and releases its pose ownership when that action ends or is
cancelled. During airborne attacks the upper body swings while the lower body
keeps the flight pose. The equipped sword follows its hand socket. Heavy attack
now uses UAL1 `Sword_Attack`, with source strike landmarks **0.333333–0.5 s** and
its own remaining recovery inside the same clip. Its gameplay timing stays
**0.65 s windup / 0.22 s active / 0.55 s recovery**. Heavy attacks do not use the
persistent light-attack follow-up queue. Sword idle, spells and mantle are covered
in [native action playback](UAL_ACTIONS.md); remaining fallbacks are listed there.

`scenes/models/ual_player.tscn` inherits the canonical mannequin and assigns
`features/presentation/data/player_equipment_loadout.tres`. The review mannequin
retains the separate review loadout; normal gameplay does not carry its shield
or bow marker.

## Rebuild and checks

From the project directory, after imports finish:

```sh
.artifacts/toolchain/godot --headless --path . --script tools/build_ual_combat_library.gd
python3 tools/run_tests.py --suite run_light_attack_buffer
python3 tools/run_tests.py
python3 tools/check_project.py --clean --release
```

The library builder checks rig compatibility before writing its output. Keep its
generated runtime library and the source import configuration with the code so
a clean checkout and exported release use the same clips. Follow
[development checks](DEVELOPMENT.md) for toolchain setup and report locations.
