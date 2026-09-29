# ADR 001 — character composition and independent action state

**Accepted: 20 September 2026.**

The prototype combined movement, action timing, resource spending and presentation
in one player script, while its motion preview simulated a separate body.

Use a shared CharacterBody3D scene with focused, explicitly configured components.
The motor alone moves the body. Movement mode and committed action remain separate,
with one primary action initially. Direct calls request work; signals report results.
Resources hold authoring data; per-character objects hold live values. Keep legacy
script/property adapters during migration so established regressions remain useful.

This enables a scripted controller to use the same intent/action interface and
prevents the preview from drifting away from playable physics. It costs some
composition and compatibility code. A full ECS, general-purpose ability graph and
parallel action scheduler are not justified for the present prototype.

References: [Godot scene organization](https://docs.godotengine.org/en/4.6/tutorials/best_practices/scene_organization.html),
[implemented architecture](../../ARCHITECTURE.md).

## Subsequent decision

[Decision 005](005-shared-dodge.md) removes the legacy hop and world-specific
dodge selection. All hosts now share the forward dive and grounded directional
rolls. Further development requires asking the user first.
