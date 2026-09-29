# Cliff dives and the timed landing roll

Implemented in the shared character, Godot 4.6.2, following the user's timing,
stamina and failed-dive ragdoll decisions. Courtyard and Test Grounds use the same
behavior. This refines Movement 02; no later traversal mechanic is enabled.

## Behavior

- A forward dive keeps requesting **11 m/s forward until actual floor contact**.
  Walls still block it. Gravity, launch height, adaptive 0.6 m clearance and the
  locked dive direction are unchanged. No new launch or immunity is granted in air.
- Side/back rolls also retain their horizontal edge-departure speed until contact.
  Their ground braking/playback clocks pause in air; falling no longer ends their
  movement at 0.70 s. See [ground-roll details and current checks](GROUND_ROLLS.md).
- Ordinary flat-ground dives still cover about **5.5 m**. Air travel consumes the
  remaining grounded travel budget, but running out no longer stops an airborne
  dive. After a long fall there is no stored distance to release against a wall.
- While descending, a **fresh Dodge press in the final 0.15 s before contact**
  requests the skill check. Holding/repeating a key does not refresh it.
- On a **heavy or damaging, nonlethal-height impact**, success costs **25 stamina**
  and starts a grounded forward roll: **0.40 s**, **3 m**, no hop. It replaces the
  heavy recovery and applies **50% of the normal fall damage** through the shared
  damage receiver. Costs and timing are editable in `landing_roll.tres`.
- The roll goes forward relative to the knight's body, independently of camera
  aim. It starts from the contact portion of the existing forward-roll clip,
  blending from the real falling/diving pose over 0.08 s. It uses the ordinary
  roll's combat immunity window (0.06–0.32 s from roll start); that immunity never
  supplies the fall-damage discount.
- A cliff dive that **fails the check on a heavy/damaging impact ragdolls**. Missing
  the press, pressing too early, and insufficient stamina all count as failure.
  Full fall damage applies once. A survivor settles and automatically gets up;
  lethal damage leaves a dead ragdoll. Ordinary low dives keep their normal finish.
- Walking/jumping into a heavy fall without success retains normal heavy recovery.
  Soft landings do not spend stamina or launch the skill. Lethal-height impacts
  always take full damage. Even discounted damage can kill a weakened character.
- Ragdoll/get-up and other committed actions (attacks/casts/healing) cannot be
  cancelled into this skill. Reset, interruption, death and unload clear the request.

Impact severity still uses `downward_speed² / (2 × normal_gravity)` with 3/6/15 m
equivalent thresholds. The existing dive uses faster gravity (31.68 vs 22 m/s²),
so an 8 m cliff dive hits harder than an 8 m walking fall. This change deliberately
preserves that tuning; literal platform height alone does not determine severity.
The timing check uses physics time and has normal one-tick contact resolution.

## Ownership

| System | Responsibility |
| --- | --- |
| `forward_dive.gd` | Continue the airborne forward request; consume, but do not stop at, the finite ground-travel budget |
| `character_motor.gd` | Existing gravity, solid collision, contact-speed capture and ragdoll handover |
| `movement_coordinator.gd` | Report actual floor contact |
| `ability_controller.gd` / `action_lifecycle.gd` | Turn a fresh descending Dodge into the existing one-slot buffer; resolve and atomically pay at contact; release previous action ownership |
| `landing_roll_definition.gd` / `data/landing_roll.tres` | Shared read-only timing, cost, recovery, travel, pose start and damage multiplier |
| `landing_response.gd` | Classify unmodified impact, exclude lethal heights, ask for the roll, apply the discount only on acceptance, send one damage request |
| `reaction_controller.gd` | Failed heavy cliff-dive policy; preserve the diving pose and enter physical recovery without charging a second impact |
| `ground_roll.gd` / presentation | Reuse grounded motion and the existing forward animation; blend from the actual contact pose |
| Laboratory | Test platform, reset, binding-aware controls and read-only F3 diagnostics |

The new action uses the same lifecycle and atomic resource owner as attacks,
spells and other dodges. There is no separate landing-input queue, world-specific
controller, animation-driven body movement, or mutable state on shared definitions.
See [decision 008](decisions/008-contact-roll-and-dive-failure.md).

## Test in the game

1. F5 launches the courtyard; use **Esc → Character Test Grounds**. Alternatively
   open `scenes/movement_lab.tscn` and press F6.
2. In the lab Esc menu, select **8 m drop → Start fall test**.
3. Face off the platform and Dodge to dive. Tap Dodge again just before contact.
   Use the displayed binding: fresh defaults use Alt; older saved controls may
   still use Space. A dive plus a successful landing roll costs **50 total stamina**.
4. Repeat without the second press: the missed cliff landing should ragdoll and
   automatically recover if health remains. Walking off instead retains the
   ordinary heavy-landing failure behavior.
5. F3 shows impact severity/damage, timed-roll success and the last request result.
   **Drop + hit** separately tests the existing descending-hit ragdoll exclusion.
6. Reset Station restores resources and ownership. Camera/keybinding settings stay
   intact. No new keyboard action or saved-binding migration is needed.

## Native visual review

- [Successful timing, full trajectory](cliff-landing/timed-landing.gif)
- [Successful timing, close animation view](cliff-landing/timed-landing-close.gif)
- [Missed timing, physical ragdoll and get-up](cliff-landing/failed-landing.gif)
- [Contact/roll/recovery poses](cliff-landing/landing-poses.png)

These are captures of the production character, not a second physics preview.
In the captured 8 m dive, success applies **31.6 damage** versus **63.3** on failure.
The initial upright frame during action replacement was corrected by preserving
the actual diving pose across animation ownership changes. Captured controlled
poses keep the armor above the floor. Physical recovery uses the existing rig.
`cliff-dive.gif` is the intermediate momentum-only capture before the user's
subsequent missed-check ragdoll refinement; the failure footage above is current.

## Validation

Run `python3 tools/run_tests.py --report docs/validation/cliff-landing-final.json`.
Focused suites are `run_cliff_dive` and `run_landing_roll`, alongside existing
movement, jump, ragdoll, camera, input, combat and reset suites. Coverage includes
30/60/120 Hz cliff momentum, walls, retained flat reach, cost, immunity, timing,
insufficient stamina, soft/lethal impacts, low health, eight facing directions,
pose handover, pause, interruption, failed-dive recovery and repeated reset.

The [full report](validation/cliff-landing-final.json) passes **1,710 checks across
27 suites**, with no script/engine errors.
Captured footage is visual evidence, not a release performance benchmark. Review
the 0.40 s recovery and physical failed landing in-game before advancing mechanics.
