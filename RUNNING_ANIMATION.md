# Dynamic running animation

Open **Esc → Character Test Grounds**, then **Esc → Go to station → 01 Running**.
Use your movement bindings and hold Sprint (default Shift). Compare flat running,
10°/20°/30° ramps, sharp corners, and alternating left/right steering through the
S-turn fixtures. F4 (by default) disables PS1 effects for a clearer inspection.

The existing CC0 Quaternius library supplies distinct jog and sprint cycles.
They are adapted to the knight's skeleton, play in place, and blend with idle.
Switching between jog and sprint preserves the cycle phase. Transitions blend
for 0.30 seconds; stride cadence eases over 0.16 seconds. UAL gait clips retain
their authored articulation without a second continuous pose filter. Playback
uses actual displacement divided by measured stance speed, scaled to the rig;
pressing into a wall settles to idle. Baked source contact curves release each
foot during its swing instead of using a fixed ankle-height threshold.

On ramps, the torso leans into the climb and changes posture when descending.
A two-joint leg solver adjusts knees and ankles to nearby ground, aligns soles,
and accounts for the long armored boots. IK preserves the sampled foot orientation
before applying slope alignment. Brief foot planting reduces sliding; an
overextended anchor fades out without snapping to a new position mid-stance.
Turn rate drives a limited, smoothed lean, which reverses through S-turns;
the torso also turns slightly toward the travel direction. Stopping settles
these offsets rather than snapping the body upright.

The visible forward lean scales with actual speed (up to 10° of added lean at
full sprint). Reversing the turn direction within one second temporarily applies
1.15× turn lean, capped at 16.1° rather than the normal 14° cap.

Movement now accelerates at 16 m/s² and brakes at 20 m/s² when input is released.
From a 6.5 m/s sprint, stopping takes about 0.33 seconds and roughly one meter.
Only a full 180° reversal triggers sharp-turn braking: the knight slows along
the old path at 26 m/s² to almost a complete stop, then accelerates back.
Turns below 180° do not trigger this braking stage.
Turns below 180° steer without reducing speed. Speed and heading are updated
separately, so diagonal input and S-turns retain the same 4 / 6.5 m/s top speeds
as straight movement. Heading steers at up to 720°/s while body facing continues
to ease toward travel direction. Input is normalized to avoid a diagonal boost.

Top speeds (4 / 6.5 m/s), collision, stamina costs, and camera behavior are
unchanged by running tuning. Dodge now has separate airborne and grounded
animation phases; see DODGE_HOP.md for its revised timing. Dodges and combat actions interrupt momentum immediately;
wall contacts remove velocity into the wall.
Attacks, casting, damage reactions, and rolls suspend the running corrections.
Station resets clear foot anchors, gait filtering, and motion history. Boss
animation is retained.

## Lock-on movement

Press Lock on (default Q), then move sideways or away from the enemy. The
camera and knight keep facing the enemy while walking or idle. Hold Sprint
(default Shift) with movement input to face the direction of travel, even when
stamina is exhausted. Release Sprint to smoothly face the enemy again. Holding
Sprint without movement input still faces the enemy.

Attacks, spells, dodges, climbing and physical reactions retain their existing
facing control. Free airborne movement uses the same lock/run rule. Unlocking
or losing the target restores ordinary movement-facing without snapping the body.

Body turning uses the existing exponential response, configured by
`move_turn_response`. `features/character/player.gd` supplies the desired facing
through the existing motion request; the shared simulation and motor apply it.

## Files and tuning

- `scripts/psx_knight.gd`: selects/blends cycles and applies animation layers.
- `features/presentation/knight_locomotion.gd`: speed-based lean, S-turn detection, and foot-placement corrections.
- `scripts/player.gd`: acceleration, stopping, and sharp-turn braking; rates
  are editable through `data/combat.tres` / `scripts/tuning.gd`.
- `data/locomotion.tres`: editable lean limits, smoothing, blend duration, and
  foot placement strength, cadence smoothing, and pose smoothing; defaults are in `scripts/locomotion_tuning.gd`.
- `assets/animations/anim_legacy_knight_jog_v01.tres` and `sprint.tres`: retargeted animation resources.
- `tools/build_run_animations.gd`: rebuilds the Knight clips from bundled
  UAL `Jog_Fwd` and `Sprint`. `tools/gait_bake.gd` measures contact/cadence metadata.
- `tools/build_ual_animations.gd -- --locomotion`: rebuilds only the mannequin
  jog/sprint resources. A constant floor offset retains source pelvis bounce.
- `tests/run_gait_contacts.gd`: source fidelity, swing release, foot orientation,
  and clearance on both rigs at 30/60/120 Hz sampling.
- `tests/run_running.gd`: focused movement and animation checks.
- `tests/render_running.gd`: captures flat running, all ramps, and both turns in
  `/tmp/run-*.png` for visual review.

## Automatic step-up

Walk or sprint into an obstacle up to **0.60 m high** to climb it automatically.
No additional key is needed. The running station has labeled **0.25 m**, **0.60 m**,
and **0.70 m** blocks near its back edge; the last is deliberately too tall.

The player probes the contacted ledge for a walkable top, checks the rise, then
sweeps the full character collision shape upward and onto the landing. Low ceilings
or blocked landings prevent the step. This also handles diagonal approaches and
successive steps. Horizontal movement stays under the normal controller, so
step-up does not add a speed boost. Dodge now uses a separate physical 0.60 m
hop on every grounded launch, rather than this obstacle-triggered step assist.
See [DODGE_HOP.md](DODGE_HOP.md) for timing, clearance, gap practice, and validation.

Ramp sides also support step-up. The clearance sweep accounts for the capsule's
rounded bottom on an inclined surface and the higher near edge when approaching
diagonally downhill. The **ledge** must still be at most 0.60 m high; extra capsule
clearance does not permit taller ledges or bypass ceilings.

`max_step_height` in `scripts/tuning.gd` / `data/combat.tres` controls the limit.
`try_step_up` in `scripts/player.gd` performs the checks before movement.
`tests/run_steps.gd` covers height limits, both running speeds, ceiling clearance,
diagonals, consecutive steps, reset, and restrictions during airborne/combat states
(27 checks). `tests/run_roll_steps.gd` now tests the physical hop (78 checks),
and `tests/run_dodge_lab.gd` tests actual lab gaps, access stairs, and ramp landings
(23 checks). `tests/run_ramp_steps.gd` retains walking/sprinting ramp-side checks;
its revised 110-check suite passes after the landing-roll redesign. The new
`tests/run_landing_roll.gd` adds 54 checks for contact-driven phases and pose blending.

```sh
godot --headless --path . --script tests/run_steps.gd
godot --headless --path . --script tests/run_roll_steps.gd
godot --headless --path . --script tests/run_ramp_steps.gd
```

## Validation

26 focused checks pass: distinct cycles, speed bounds, skinned-mesh clearance
across flat ground and all three uphill ramps, finite leg poses, downhill lean,
sharp turns, repeated S-turns, settling, pause, reset, dodge, and attack transitions.
The sampled clearance threshold allows at most 4 cm of skin penetration during
motion.

`tests/run_lock_movement.gd` covers both shoulders, target-facing idle and walking,
running and smooth return to target-facing, cadence, combat aim, target loss,
horizontal overlap, free airborne tracking, and committed dodge ownership.
Exhausted running requests are checked at 30/60/120 Hz.
`tests/run_ledge_lifecycle.gd` verifies that lock-on and running requests do not
override attached wall-facing.
`tests/run_momentum.gd` covers speed-based lean, stopping distance, braking
before a 180° reversal, re-acceleration, S-turns, resets and dodge interruption.

```sh
godot --headless --path . --script tests/run_running.gd
```

Review the running, braking, and turning feel in game before starting the next
mechanic. Other test-station abilities remain inactive.

See [the September 25 locomotion review](docs/validation/LOCOMOTION_REVIEW.md) for findings and validation limits.

### Steep-ramp contact correction

On uneven ground, the presentation layer prepares both foot targets against their
surface planes, then lowers the visual pelvis enough to keep stance targets within
leg reach. The adjustment is smoothed and capped at 0.35 m; it never moves the
collision body. `max_pelvis_lowering` and `pelvis_response_seconds` are editable in
the locomotion definition. Flat-ground gait bounce remains authored by the clip.
Contact correction runs after landing/crouch/ledge exit blends so those blends
cannot undo foot placement. Reset and airborne/action transitions clear the offset.

`tests/run_ramp_contacts.gd` measures stance hovering, target reach, penetration,
contact availability, and reset on a sustained 30° slope. It covers both rigs,
uphill/downhill jog/sprint, and 30/60/120 Hz simulation steps. The older ramp test
only checked clipping and finite poses, so it missed overstretched, hovering feet.
