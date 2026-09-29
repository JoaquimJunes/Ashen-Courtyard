# Decision 006 — jump is takeoff; landing is collision feedback

Status: implemented for Movement 02, following the user's eight design answers.

Jump owns a short paid takeoff action. The motor integrates its trajectory and the
movement coordinator tracks ground/air transitions and a single-use edge grace.
Airborne movement is not itself a committed action, so compatible attacks and
spells may run without replacing physical momentum.

The motor records downward velocity before collision removes it. Actual floor
contact emits a landing event. LandingResponse converts impact speed to equivalent
height using the configured gravity, requests a forced landing commitment when
needed, and sends fall damage through the shared receiver. The fall damage type
bypasses dodge immunity and the laboratory's ordinary combat restriction.

Costs remain atomic and follow ongoing costs. Input buffering keeps a request
pending until landing rather than paying early; hard landing/reset/death clears
that pending request. Physical reset invalidates stale floor/grace state.

The new input is migrated without overwriting saved controls. An old Space dodge
keeps Space, and Jump receives the first available fallback (Alt, then F, etc.).
Fresh/default bindings use Space jump and Alt dodge.

See [implementation and review](../MOVEMENT_02_JUMP_FALL_LAND.md).
