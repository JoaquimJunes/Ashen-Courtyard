# ADR 004 — one action lifecycle for player and AI

**Accepted: 20 September 2026.** Implements the Section 2 ownership follow-up.

## Problem

Player requests could start immediately and bypass sprint costs. Burst recovery
looked up Bolt's timing, movement restrictions were only checked at startup,
animation read device input, and damage bypassed resource notifications. The
Warden also had a separate commitment/timing implementation.

## Decision

`ActionLifecycle` owns validation, the one-slot buffer, atomic payment, captured
definition, strike token and lifecycle/result signals. `AbilityController` and
`WardenActions` extend it with character-specific execution. An executor never
charges costs itself. Warden decision and presentation components remain separate.

Every input route queues a request. The character physics tick pays ongoing costs
before resolving it. The original `begin()` entry point now returns **queued**,
not started. Production code observes the result or lifecycle signals:

```gdscript
var result: RefCounted = character.request_action(&"heavy")
if not result.resolved:
    await result.completed
if not result.accepted:
    print("Action rejected: ", result.reason)
```

Early rejection is already resolved. Queued requests may later be rejected by
changed conditions, expiration, supersession, reset, death or unload. Keyboard
and intent requests permit the existing short buffer during commitment; direct
requests reject commitment immediately. The buffer does not accumulate actions.

Definitions stay read-only during play. The active definition, captured at
acceptance, supplies timing, damage, healing and spell delivery until completion.
Replacing a definition slot affects the next action. Invalid combined costs
spend nothing. Movement changes cancel an incompatible active action by default;
`ModeExit.CONTINUE` is an explicit authoring exception. Interruption does not refund
paid costs. Death/unload override ordinary continuation rules.

Presentation owns skeleton sampling/blending; it consumes resolved sprint state
and dive phases. Damage/healing/reset pass through `CharacterResources`, whose
health signal is forwarded by the character. Spell services receive an explicit
`AimRequest(origin, point)`; only the player aim adapter reads a camera.

## Consequences

Direct callers must wait for the next physics tick rather than assuming immediate
acceptance. `tests/action_test_driver.gd` does this for older test scenarios. The
preview also waits for `started`; it still runs the actual character simulation.

Both actors use the same lifecycle without requiring identical action animations
or an elaborate AI framework. The default Warden keeps its three melee patterns;
camera-free AI casting is covered as a reuse test, not added to the encounter.

Flight costs and mana-exhaustion transitions remain future work. This change
establishes their ordering boundary without claiming those mechanics exist.

Evidence: [Section 2 review](../SECTION2_REVIEW.md),
[`run_ownership.gd`](../../tests/run_ownership.gd).
