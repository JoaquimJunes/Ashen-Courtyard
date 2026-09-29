# Section 2 — ownership follow-up

**20 September 2026 · Godot 4.6.2.stable.official.71f334935 · Compatibility**

The recommended next step was to close the verified ownership gaps before adding
another movement mechanic. This implements those gaps and connects the existing
Warden to the same lifecycle and request interface.

| Audit finding | Implemented change | Main owner |
| --- | --- | --- |
| Burst used Bolt recovery; execution looked up mutable slots | Capture the definition on acceptance and use its timing, damage, healing and delivery properties | `features/abilities/ability_controller.gd` |
| Mode restrictions were only checked at startup | Revalidate on movement-mode change; cancel by default, with explicit continue policy | `features/abilities/action_lifecycle.gd` |
| Direct actions bypassed ongoing resource costs | All routes queue; the real physics tick pays ongoing costs before atomic action costs | `features/abilities/action_lifecycle.gd` |
| Animation used keyboard state and the dive owned skeleton blending | Use resolved sprint state; move pose sampler/blending into presentation | `scripts/psx_knight.gd`, `features/presentation/dive_presentation.gd` |
| Damage bypassed resource health events | Damage/healing/reset publish through one resource owner and character forwarding signal | `features/character/character_resources.gd`, `scripts/combatant.gd` |
| Boss commitment and spell aiming were not reusable | Warden execution extends the shared lifecycle; spells receive world-space aim | `warden_actions.gd`, `warden_controller.gd`, `combat_services.gd`, `aim_request.gd` |

`scripts/boss.gd` now assembles components and orders ticks. Its controller still
chooses the two-swing combo, overhead and distant lunge. The normal boss does not
cast spells. Projectile damage remains owned by the released projectile, so
cancelling an already released cast cannot erase it; cancelling before release
prevents the projectile.

## Validation

**869 checks across 19 suites pass, with no reported engine/script errors.**
The previous baseline was 828 checks across 18 suites. The 41 new ownership checks
cover real queued requests, cost ordering through direct/intent/keyboard routes,
pending-result cleanup, expiry, pause/resume, captured recovery, actual ledge
transitions, health signals, camera-free AI casting, cancellation, capability/mode
rejection, normal AI selection, freeze and unloading.

Existing combat, camera, settings, reset, movement, animation, step, gap and dodge
regressions remain passing, including the established 30/60/120 Hz movement checks.
Tests that previously started actions synchronously now await a real character
tick. Old scene entry points and tuning aliases remain available.

Run from the project folder:

```sh
python3 tools/run_tests.py
python3 tools/run_tests.py --suite run_ownership
```

[Machine-readable report](validation/section2-ownership.json).
Native courtyard, Test Grounds and shared-preview screenshots were recaptured on
Iris Xe and reviewed. The raised-gap replay still lands at **0.4167 s**, completes
at **0.9667 s**, and travels **5.2413 m**, matching the preceding implementation.
These are rendering/motion checks, not a release performance benchmark.

## Review in the game

Restart the running game. **F5** launches the courtyard; use **Esc → Character
Test Grounds**, or open `scenes/movement_lab.tscn` and press **F6**. Test both dodge
variants, station resets, sprinting, spells and the Warden's attack openings.
Open `scenes/dive_clearance_preview.tscn` and press **F6** for raised-gap replay.

![Actual shared-character dive](dive-clearance/raised-gap-sequence.png)

## Remaining scope

The current systems are more consistent with Section 2. This does not mean every
planned system exists. Interaction/equipment/progression, new movement modes,
world streaming/destruction and gameplay saves remain later milestones. Existing
compatibility adapters and scene-specific composition remain deliberate; there is
no new ECS or generic ability graph. The next gameplay gate is the user's review
of running/dodging before starting the next movement mechanic.

See [architecture](../ARCHITECTURE.md), [ADR 004](decisions/004-action-lifecycle.md)
and [development roadmap](../DEVELOPMENT_ROADMAP.md).
