# Dark soul stone: VFX implementation plan

Status: proposed for game integration after visual review. The current preview changes the crown, connecting arch, stone transition, and crystal geometry. Its existing simple wisps are placeholders; the effect described here is not implemented in the game.

The implemented [mana evolution aura](MANA_EVOLUTION.md) is a separate preview
effect around the orb and crown, active only at full main mana. It does not
implement this continuous dark leakage along the health frame.

## Appearance

Frame distinction: the Mana Frame is the orb surround, crown, and gothic arch. The Health Frame is the horizontal heart holder, including its stone transition. The latest reference-matching preview restores the reference artwork's small health-frame markings with explicit user confirmation. It also shows five reserves (three full, two empty) for visual comparison. The separate Gameplay start preset retains zero unlocked reserves; game integration has not occurred.

The stone contains a restrained dark presence. Near-black violet vapor escapes through broken edges, briefly curls outward, then dissolves. A thin violet highlight catches some curls and fissures. Keep the stone silhouette sharp and the hearts, mana level, eyes, and bindings unobscured. Avoid a uniform glowing outline, billowing smoke, or constant bright sparks.

Health capacity determines the stone's length and strength. Maximum mana determines the strength of its supernatural appearance. Spending health or mana does not reverse this visual progression.

## 1. Prepare the artwork and masks

- Keep the crown, gothic bridge, mana-to-health shoulder, repeating heart rails, and fractured end as separate 2D pieces with matching attachment points.
- Author stone opacity, crack emission, and permitted leak masks in the same local coordinates. Include an outward flow direction for each leak area.
- Concentrate leaks at the broken right tip, with smaller leaks at the shoulder and crown fractures. Exclude heart interiors, the crystal, reserve vessels, and text from the emission mask.
- Supply transparent padding beyond each broken edge, initially 24–40 logical pixels at the preview's 1280×720 scale. Reposition the end piece when capacity changes instead of stretching its texture.

## 2. Compose the effect in layers

Suggested order: dark aura behind the frame → stone artwork → masked crack glow → resource symbols and text. The crystal retains its separate flat-shaded presentation.

Use one small local effect surface per active leak region, sharing the same shader. Scroll two low-frequency noise samples through the leak mask at different speeds; use the flow direction to stretch them away from the fracture. Fade opacity with distance and break up the outer tips with noise. Build narrow curls into the mask so the result is directional rather than a generic fog cloud.

Use normal alpha blending for the dark vapor. Additive blending alone cannot create a dark cloud; reserve it for the faint violet highlights. Godot's CanvasItem shaders support both modes. [CanvasItem shader documentation](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/canvas_item_shader.html)

Start without particles. If review calls for detached motes, add one capped emitter with 8–12 small motes near the end fracture. Expand its visibility bounds to contain their full travel. [GPUParticles2D documentation](https://docs.godotengine.org/en/4.6/classes/class_gpuparticles2d.html)

## 3. Tune an authored effect profile

These are initial review values, not measured final settings:

| Parameter | Starting value / rule |
|---|---|
| Idle smoke opacity | 0.12–0.28, depending on mana progression |
| Outward travel | 12–28 logical pixels |
| Drift speed | 4–9 logical pixels per second |
| Curl lifetime | 1.5–3 seconds, staggered |
| Violet highlight opacity | 0.05–0.15 |
| Accepted mana gain | Gentle 0.35-second pulse in the receiving vessel's runes |
| Accepted cast | Brief 0.15-second crack glow, then idle |
| Insufficient mana | Existing frame shake; no additional bright flash |

Expose intensity, tint, speed, reach, and masks through a reusable presentation profile. Cap combined transient pulses so repeated events cannot turn the frame into a bright flickering patch. Use per-HUD material parameters so preview controls cannot modify another HUD instance.

## 4. Connect presentation to gameplay

Observe accepted action and resource-change events. Do not infer casts, kill rewards, or reserve transfers from animation timing. Read effective maximum mana and heart capacity only when they change. An enemy kill with no accepted mana because all vessels are full should not show a refill pulse.

Keep all aura nodes under the same HUD transform so shaking and resizing move the stone and vapor together. Pause the effect with the game, stop it when the HUD is hidden, clear transient pulses on death/reset, and rebuild leak anchors when the frame layout changes. Use an explicit effect-time parameter so pause and reduced-motion behavior are controlled consistently.

Reduced motion keeps a static faint aura and crack tint, with no drifting particles or pulsing. Effect quality may change the number of noise samples or disable detached motes, but must not alter resource readability.

## 5. Validate before integration is complete

- Review start, mid, and maximum progression on bright and dark gameplay backgrounds; test every heart-capacity layout.
- Check 0–5 reserves, partial reserves, low-mana eyes, depleted hearts, and gold overlays. Aura must not appear to represent resource fill.
- Exercise repeated casts, failed casts, mana overflow, pause, death, retry, resizing, and HUD hiding. Check that no effect remains at an old anchor.
- Inspect native HUD size as well as enlarged views. Check for rectangular shader boundaries, clipped smoke, visible tiling, edge halos, and unreadable runes.
- Profile on the actual target renderer and minimum hardware. Initial goal: no full-screen effect pass, no node per wisp, at most three small leak regions, and no per-frame geometry rebuilding. Set the final time budget from measured baseline performance.

## Preview geometry audit

The crystal is a projected front hemisphere with 28 shared geometric vertices, 38 triangles, and a 16-edge silhouette. Its open outer boundary is intentional; it is not a closed 3D sphere.

The original audit found no degenerate or reversed triangles, non-manifold edges, or missing projected coverage. Adjusting interior ring placement increased the smallest 3D triangle angle from 23.24° to 25.66° without adding triangles. Lighting normals now account for the slightly taller displayed shape, and the stone ring keeps clearance as it thickens. The current preview still uses Canvas rendering; a future actual 3D mesh would need deliberately split shading normals for flat faces and a rear surface only if visible.
