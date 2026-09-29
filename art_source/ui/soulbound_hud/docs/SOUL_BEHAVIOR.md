# Soul animation preview

Implemented in the [editable preview](../soulbound-crystal-hud-preview.html). This is standalone preview behavior; no game scripts, saves, or combat balance were changed.

## Cycle

| Phase | Behavior |
|---|---|
| Draining | Deduct an accepted spell's full cost immediately, then lower the drawn level over 0.3 seconds with a damped slosh. |
| Cooldown | Wait 0.5 seconds after the level-drop animation completes. |
| Refilling | Move half of the main vessel's capacity per second from reserves into the main vessel. Illuminate branching cracks toward the orb and gather Soul in a small internal spiral. |
| Idle | Stop at full, when reserves run out, or on death. A depleted vessel with available reserves becomes eligible automatically. |

Only the main vessel funds spells. Successful casts interrupt transfer immediately and start a fresh drain/cooldown cycle; failed casts neither interrupt nor queue. Partially used reserves retain their remaining Soul, are consumed left to right, and feed the next vessel without another cooldown. Kill rewards retain main-first, left-to-right overflow and do not restart existing timers.

Actual mana and the displayed liquid level are separate. The embedded `SoulController` owns payment, transfer, phase timing, and slosh state; both display scales render that same state. It handles phase-boundary time precisely and uses a damped oscillator for consistent movement at different frame rates. Tiny floating-point remnants are clamped to empty to avoid faint filled reserve icons.

The partial Strongest reference opens at 150/300 and refills automatically after
0.5 seconds; the full Strongest preset opens at 300/300. Use **Cast · E** repeatedly to interrupt the flow, **Frame close-up** to inspect sloshing, and **Reset preview** to restore the last selected preset. Manual resource edits clear prior animation state. The gameplay-start preset still has no reserves. Hidden-tab and offscreen-preview time is paused and discarded when returning. Reduced motion keeps level changes and transfer timing, with static illuminated cracks and a stationary spiral; it removes slosh, moving motes, and the completion pulse/ripple.

## Magical refill presentation

The implemented sequence is: **reserve → illuminated stone cracks → internal spiral → brief eye glow and a settling ripple**.

1. Precomputed branching fissures follow the stone rim from each reserve to the orb's lower edge. Only the active reserve's route lights up. Two larger Soul wisps travel along it with pale heads and bending violet tails. Main fissures are wider and brighter while side branches remain fine, making the movement easier to see at gameplay size.
2. Two narrow spiral strands gather inside the lower part of the orb, below the eyes. A faint lavender light pools at the bottom during refill, preserving the visible crystal facets. Both share the liquid and crystal clipping masks, so Soul cannot escape the vessel or appear above its current fill. Casting stops the spiral, bottom light, and connecting wisps immediately. Reduced motion retains the steady light and fissures without travelling wisps.
3. When reserve transfer reaches full, the eyes glow once over 0.4 seconds and an expanding inlet ripple fades over 0.6 seconds. Otherwise the eyes are white with no emitted halo, and still disappear at low Soul. The glow requires the displayed main vessel to be full. This is a presentation cue, not an additional resource phase: transfer has already stopped and spells remain available. Full presets and depleted reserves do not trigger it. Accepted casts, reset, manual Soul edits, and death clear it; failed casts leave it alone.

The controller records the exact completion time at the transfer boundary, even if a frame crosses that boundary. Rendering derives the short glow and ripple from that timestamp. This keeps the effect consistent across frame rates without changing resource quantities or refill timers. The same rendering functions serve gameplay size and close-up views.

The main liquid surface has a shallow projected oval, a darker far edge, broad restrained reflections, and a bright near lip. The body fill follows that near edge, and both edges share the existing slosh deformation. The oval narrows toward empty/full and stays clipped inside the crystal. Reduced motion preserves the depth while keeping the surface still; Soul quantities and refill timing are unaffected.

Crystal lighting is a separate transparent outer-shell pass drawn after the liquid surface, internal effects, and eyes. Diffuse facet lighting, sharp reflections, and edge light span each complete triangle, so the meniscus cannot hide them. Interior pigment and Soul emission remain underneath. Light is added once per facet without stroked seams to avoid double-bright edges between adjacent faces.

The separate [mana evolution](MANA_EVOLUTION.md) layer observes actual and
displayed fullness. Full presets and kill rewards can activate its aura without
triggering the refill-only eye glow. Evolution never changes the casting cycle
or pays costs; acquiring a reserve increases capacity without granting Soul.

## Validation

Run from the package root (`art_source/ui/soulbound_hud`):

```sh
node tests/soul-controller.test.cjs
node tests/soul-preview.test.cjs
```

The model suite covers 20 timing, interruption, conservation, reward, lifecycle, frame-rate, completion-cue, and reduced-motion scenarios, including 1,000 randomized action/reward updates. The browser suite exercises actual controls, all five fissure routes, immediate VFX cancellation, completion brightness, readouts, resource edits, visibility events, real-time animation, eye clipping, reduced motion, and 320/360/736/1024-pixel layouts. It also verifies the canvas backing resolution on a 2× pixel-density display at three preview widths. Browser checks use Playwright and Chromium; see [setup instructions](../README.md).

Visual review covered illuminated fissures, the internal spiral, the completion glow/ripple, mid-drain slosh, an empty vessel, normal gameplay size, and the enlarged view. Soul stays clipped to the crystal; the active reserve and connecting flow share the HUD transform.
