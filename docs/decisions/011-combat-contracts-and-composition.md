# ADR 011 — request notifications, world lifetime and character composition

The action queue installs its replacement before notifying the superseded
ticket. A listener may submit a newer request or cancel the replacement. The
latest request wins, each caller receives its own ticket, and every displaced
ticket resolves once. Player-specific early rejections use the base lifecycle's
`reject_request()` so diagnostics receive the same notification contract.

Player and Warden composition preserve an injected combat context. Standalone
instances ask GameSession for a context owned by their containing world beneath
the viewport. Characters in that world share it; released projectiles survive
individual caster removal. Insertion is deferred because authored child scenes
can become ready before their parent finishes assembly. World exit cleans up
both pending contexts and released transients. Running a character as the whole
scene uses viewport hosting with cleanup tied to that preview scene's lifetime.

`Combatant.setup(hp, body_definition)` configures resources, collision and the
motor. It does not select a model, require a weapon pivot, or acquire session
services. `BodyDefinition` stores radius, height, collision layer and mask;
each actor creates its own mutable capsule. Player and Warden select their
existing body definitions and model scenes independently.

`KnightVisuals` owns setup for the shared knight model family, locomotion tuning,
hit feedback and the existing death tilt. Player/Warden keep their public model
and sword references for current consumers. Damage history expiration remains
in Combatant and can run without presentation. Gameplay costs, tuning, model
paths, collision sizes and masks, and the ordering of reaction/presentation
updates remain unchanged.

Regression coverage: `run_request_contracts`, `run_world_combat_context`, and
`run_combatant_composition`, plus the existing ownership, combat, movement and
physical recovery suites. The former `large` setup flag and `visual_tick()`
entry point had no scene/resource references; their known callers were migrated.
