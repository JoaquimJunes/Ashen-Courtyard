# Fitted damage sensing and head immersion

The shared player uses 17 animated sensing regions for both its UAL appearance
and the supported legacy Knight appearance. Open **Esc → Debug → Fitted hitboxes /
breath** to see the shapes, green mouth/nose marker, head-water state and orange
last accepted contact. The separate **Collision capsule** option shows the shape
that moves against the environment. These displays do not run collision queries
or advance animations.

## Geometry and damage

The editable profiles in `features/combat/ual_hitboxes.tres` and
`knight_hitboxes.tres` cover head, neck, chest, abdomen, pelvis, upper arms,
forearms, hands, thighs, shins and feet. They were fitted from each body's mesh
and bone-local geometry with small joint overlaps. A rounded capsule fits the
head; capsules fit the neck and limbs; boxes fit the trunk, hands and feet.
Orthogonal local scaling allows narrower limbs without flattening their depth.
Equipment and accessories do not add regions.

Each rig references a `HitboxProfile`. Each `HitRegion` stores a stable region
name, bone name, shape and bone-local transform. Runtime snapshots, breathing
history and last contacts belong to each character, never these shared Resources.
Region labels are diagnostic: all regions take the same damage.

`character_hitboxes.gd` captures two completed world-space snapshots tagged with
their physics frames. Combat reads the latest snapshot strictly before the
current frame, giving the same geometry regardless of character update order.
This intentionally adds one physics tick of delay (about 17 ms at 60 Hz).
Breathing uses the owner's newest completed snapshot instead. Teleports and
resets reseed both snapshots; death and unload invalidate combat sensing.

The per-character pose driver evaluates land animation once in physics, after
movement and before sensing. Swimming advances once before its motor step and
fits the body to the accepted capsule transform before capture; physical ragdoll
snapshots use the driver's actual world-space bones. Rendering interpolates
ordinary completed land poses without advancing animation clocks or changing
stored hit geometry. Constraint-fitted poses retain their completed pose. Native
source clips and keys are unchanged. See [animation ownership](ANIMATION_SYSTEM.md).

`hit_geometry.gd` supplies segment intersections and closest-point tests for the
supported primitives. `damage_queries.gd` enumerates compatible characters in the
observer's physics world, once per character, with no fixed result-count cap.
For fitted characters it excludes their movement and physical-bone colliders
from projectile queries, then compares the nearest fitted contact with the world
ray result. A wall still blocks a shot; a ray through a clear limb gap misses.
Melee and burst attacks confirm contacts against the fitted geometry within
their existing range and facing limits. Strike tokens still apply damage only
once per character, even when several regions overlap an attack.

These are analytical sensing shapes, not new physics bodies or blocking Areas.
`CharacterMotor` still owns the environment capsule and all displacement.
Unprofiled combatants, including the current Warden composition, retain their
existing receiver path. Other model compositions can opt into the component by
supplying a matching rig profile and capturing it after their completed pose.

## Breathing

`features/swimming/head_water_detector.gd` exposes `head_submerged`,
`breathing_position` and `head_submerged_changed`. The profile's breathing offset
places the marker between the visible mouth and nose, attached to the head bone.
Ragdoll sensing uses the physical head. Crouching, falling and ledge transitions
can submerge the marker independently of swimming movement mode.

The marker must move **2 cm below** the surface to enter the submerged state and
**2 cm above** it to regain air. Each tick splits the travelled segment at water
bounds and both thresholds, returning chronological wet/dry time intervals. A fast
crossing with dry endpoints still counts its time underwater. Teleports reset
history rather than sweeping across the map. Removed water, reset and unload clear
stale state; worlds and characters are isolated.

Resources retain **20 seconds of breath**, a **3-second full refill** and existing
**10% maximum-health drowning damage per second** after expiry. Only air intervals
refill breath. Drowning uses shared damage/death even with lab combat disabled and
does not stagger. Floating presentation aligns the mouth 12 cm above the surface
once the entry blend completes. Camera immersion only controls tint.

## Verification and playtest

`run_fitted_hitboxes` and `run_head_water` cover 30/60/120 Hz body-region contacts,
native movement poses, silhouette and limb-gap misses, fast projectile sweeps,
wall occlusion, area contacts, equal damage, strike deduplication, ragdoll heads,
fractional immersion time, head-only drowning, refill and lifecycle cleanup.
The swimming suites cover actual movement, surface stability, exhaustion, input
rebinding, pause, water exits and locomotion/equipment restoration.

Run `python3 tools/run_tests.py --suite run_fitted_hitboxes --suite run_head_water`
for focused checks, `python3 tools/run_tests.py` for regressions, and
`python3 tools/check_project.py --clean --release` for clean import, export and
packaged smoke validation.

In **Test Grounds → Swimming (05)**, inspect the shapes while standing, crouching,
swimming and climbing. Complete **float → dive → stop at depth → resurface → climb
out** and watch the green marker and breath meter. Automated geometric checks do
not replace the final hands-on judgment of fit and animation transitions.
