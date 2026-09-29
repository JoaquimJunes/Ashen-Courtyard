# Decision 008 — contact resolves the landing skill and failed-dive reaction

Status: implemented for the user's cliff-dive/landing refinement.

A descending Dodge press becomes a `landing_roll` request in the existing single
input buffer. The 0.15 s window is the ability's authored buffer duration. Input
records intent; it neither predicts a landing nor spends early. Actual contact
classifies full impact first. Only heavy/damaging nonlethal-height impacts can
accept the request. Payment, action serial, signals and cancellation use the
shared lifecycle's atomic pending-request resolver.

Successful contact starts a separate grounded roll variant, rather than relaunching
the adaptive dive. The motor remains the only collision-body mover; the old
airborne action releases its pose and action ownership. Presentation captures the
current pose before that release so stopping an AnimationPlayer cannot insert a
standing frame. Contact-started actions begin with zero elapsed movement time.

LandingResponse applies half damage only after acceptance and routes it through
DamageRequest. The player distinguishes typed fall damage from ordinary hurt so
impact damage cannot overwrite the selected landing recovery. Health/death and
physical reaction still receive the same accepted-damage notification.

ReactionController owns the failed-dive policy. An airborne forward dive with a
heavy/damaging impact and no accepted roll becomes ragdoll; lethal dives also use
physical handover. Soft ordinary dives keep their existing finish. The controlled
motor has already reported the impact, so handover does not arm a duplicate bone
impact. Later genuine falls can still report new impacts. Surviving physical
characters use the existing settle/clearance/get-up lifecycle.

Airborne forward requests no longer expire at a distance/time budget. Finite
distance still bounds the grounded finish and is consumed by requested travel
even against walls; it cannot accumulate behind obstructions. Launch height,
gravity, adaptive queries and initial dodge immunity remain unchanged.

All timing, pose and cost state is per character. Definitions remain shared and
read-only. Worlds supply fixtures and diagnostics only. No new global manager or
parallel action slot is introduced.

See [behavior, ownership, footage and validation](../CLIFF_DIVE_LANDING.md).
