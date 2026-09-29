# 010 — Persistent attachment, constrained motion and regeneration policy

Status: accepted and implemented, 20 September 2026.

The user approved a bounded jump-to-ledge feature and the architecture extensions
proposed in the ledge plan. A hanging character needs support after its short grab
action ends; a pull-up needs collision-checked vertical and horizontal movement.
The old free-action regeneration condition would also refill stamina in the air.

Use a per-character SurfaceAttachment owned by MovementCoordinator, separate from
ActionLifecycle. Grab acquires it, hanging retains it, and Mantle requests targets
under its token. CharacterSimulation selects one normal or constrained motor step.
The motor reports actual motion/contact through MotorStepResult and owns temporary
collision posture. Animation changes bones only. Exit, surface invalidation, hit,
death, reset and unload release the attachment and action independently.

ResourceRegenerationPolicy evaluates support/action/reaction eligibility. Resource
amounts and atomic spending remain in CharacterResources. Both player and boss
compositions use this policy. Hanging and ordinary airborne travel do not regenerate
stamina; future flight magic must supply an explicit exception when implemented.

This adds no free wall travel or moving-platform support. Static surfaces are
revalidated and weakly referenced, so a destroyed or moved structure cannot leave
a stale attachment. Shared definitions contain no runtime state. Detection, path
execution, presentation and laboratory tooling remain separate feature components.

Future climbing should reuse the attachment, checked posture and constrained
motor path; it must not add another body mover or infer support from stale floor
flags. See [implementation, equations and tests](../LEDGE_GRAB_PLAN.md).
