# One shared dodge across all levels

The old hop dodge and its comparison switch are removed. The courtyard,
Test Grounds and animation preview use the same player, ability selection and
focused definitions. See the later [cliff-dive/landing refinement](CLIFF_DIVE_LANDING.md)
for current falling behavior. This completes the user's requested cleanup; ask before
any further development.

| Input relative to body facing | Action in every level |
| --- | --- |
| No movement or forward | Adaptive forward dive; 5.5 m ordinary flat-ground reach, 0.55 s grounded finish |
| Left/right/back | Reference ground roll; no physical hop, 4.34 m reach, 0.70 s playback |

Both actions keep their 25 stamina cost. Forward immunity remains 0.06–0.32 s
after takeoff; ground rolls measure that window from action start. Existing
animation, launch/clearance, collision, buffering and interruption settings remain.

## Architecture

- `features/session/game_session.gd` creates the common player and supplies world
  services. It no longer accepts a forward-dive/legacy-dodge choice.
- `features/abilities/ability_controller.gd` selects a definition from input and
  facing, pays through the common lifecycle and delegates execution.
- `forward_dive.gd` and `ground_roll.gd` own individual action state. Their shared
  `.tres` definitions contain tuning only. The old hop resource and executor are
  deleted, rather than hidden behind another option.
- The motor remains the sole collision-body mover. Presentation owns skeleton
  sampling and blending. Preview scenes use the real character.
- The lab menu and practice guide no longer offer a comparison switch. Camera
  and keybinding preferences retain their existing storage and behavior.

## Run and review

Restart the game with **F5** for the courtyard. Open **Esc → Character Test
Grounds**, or open `scenes/movement_lab.tscn` and press **F6**. The displayed Dodge binding from standing
dives forward in either level (Alt for fresh defaults). Tap A/D/S + Dodge from rest for side/back rolls;
selection follows body facing, so moving first can turn the knight.

Open `scenes/dodge_preview.tscn` with F6 for replay, pause and frame stepping.
The existing raised-gap preview also uses the same default ability.

The 0.5/0.6 m gaps between 0.60 m and 1.00 m platforms remain supported. The 3 m
gap lane from a 0.45 m setback exceeds the current low dive's airborne reach;
missing it triggers the existing catch/reset. No movement tuning was changed to
make the new dive imitate the deleted hop.

## Checks

**1,347 checks across 22 suites pass**, with no script/engine errors on Godot
4.6.2. The prior baseline was 1,175 checks across 22 suites. Retired hop-specific
checks were replaced by 297 host-consistency checks; eight current pose checks
retain floor-clearance and animation-continuity coverage.

Run `python3 tools/run_tests.py`. The consistency suite compares all eight input
directions plus standing across the three hosts at 30/60/120 Hz, on identical
calibration geometry. It checks selected definitions, one-time cost, requested
reach, motion, phase clocks, immunity and released ownership. Separate suites
exercise actual courtyard/lab surfaces and adaptive raised-gap fixtures.

Legacy-hop-only suites and capture code are removed. Their reusable flat test
fixture is now independent of any retired implementation, and current pose
clearance/continuity checks are retained. Previous validation reports and images
are historical evidence; the current report is
[unified-dodge-final.json](validation/unified-dodge-final.json).

[Architecture decision and review boundary](decisions/005-shared-dodge.md).
