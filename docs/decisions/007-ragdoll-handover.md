# Decision 007 — physical reactions use an explicit motor handover

Status: implemented prototype. The user selected descending hits only and
automatic get-up after surviving, landing and settling.

Ragdoll is a forced reaction, not a voluntary movement ability. ReactionController
asks AbilityController to interrupt the current action and hold the primary slot.
It hands collision motion to RagdollDriver. The character motor suspends its
ordinary integration and disables the capsule; physical bones simulate separately,
while the motor alone follows their anchor with the logical character body.

The rig uses Godot's [PhysicalBoneSimulator3D](https://docs.godotengine.org/en/4.6/classes/class_physicalbonesimulator3d.html)
and [physical bones with constrained joints](https://docs.godotengine.org/en/4.6/tutorials/physics/ragdoll_system.html).
`knight_ragdoll.tres` contains per-bone shared authoring definitions: names,
collider dimensions, masses and joint limits. Each character creates separate
runtime bones. A new skeleton supplies an appropriate rig definition; it does not
need a copy of damage, jump or reaction policy.

PhysicalBone collision hits delegate through an explicit DamageReceiver link.
Melee queries deduplicate the returned characters; projectiles use the same
receiver resolution. Being ragdolled does not grant immunity. One physical fall
reports one landing through the existing LandingResponse, rather than damaging
once for every contacting limb.

Recovery order is deliberate:

1. Confirm sustained low motion and physical floor contact.
2. Ask the motor for a nearby, supported, unobstructed standing capsule placement.
3. Capture the physical bone pose, then disable physical-bone collision.
4. Restore the capsule through the motor and snap it to validated support.
5. GetUpPresentation blends the captured pose to standing while the reaction keeps
   action ownership. The camera continues smoothing and keeps its prone pivot
   above nearby floor geometry.
6. Release the action and physical ownership after the get-up; clear all transient
   state on reset/death/unload. If support disappears during get-up, return to physics.

Lethal landing damage triggers a dead ragdoll; there is no get-up. Death releases
primary action ownership but the character-owned physical rig can continue until
the scene's existing retry/reset policy removes it. World hosts own that policy,
not the rig or character motor.

No live character body is animated by root motion. Physical-bone motion is an
explicit alternate motor authority; animation remains a consumer. The get-up
presentation is a first procedural pose blend and remains subject to visual review.
Boss-specific rigs, directional hit impulses and large numbers of simultaneous
ragdolls need their own content setup and performance measurements.
