# Soulbound HUD development snapshot

**28 September 2026 — implemented in the interactive preview only.** The project
copy and its standalone export preserve the latest reviewed design. The game
still uses [scripts/hud.gd](../../../../scripts/hud.gd) and the existing
[UI feature](../../../../features/ui/pause_menu.gd). This archive does not
wire the preview into Godot, change resource rules, or rescale combat.

## Approved appearance and current implementation

- **Mana Frame:** the main orb's stone rim, crown and connecting gothic arch.
  **Health Frame:** the horizontal heart holder and fractured right end. Keep
  these terms distinct when discussing edits. The latest reference-matching
  preview intentionally includes small markings on the health stone, overriding
  the earlier request to omit them for this preview.
- Original transparent stone art with a pointed rune crown, bridge, chips,
  mana-to-health transition and broken end. The heart frame extends by repeating
  its middle section; the crown and end are not stretched. Fully authored stone
  progression stages remain future work.
- A projected, flat-shaded crystal hemisphere: 28 shared vertices, 38 triangles,
  16 silhouette edges. It is Canvas geometry, not an exported Godot 3D mesh.
  The open back is intentional. Pointer position and lighting presets affect
  facet highlights; the reserve frames remain flat.
- Near-black violet Soul with a shallow oval top, darker far edge, bright near
  lip, ripples and slosh. Crystal lighting is composited **over** the liquid and
  eyes, so the meniscus cannot cover a lit triangle.
- White angular eyes disappear at low Soul. They have **no constant halo**.
  Reserve transfer reaching full triggers one 0.4-second glow and a final
  0.6-second ripple; ordinary full presets or kill rewards do not trigger it.
- Stone cracks carry larger pale Soul wisps from the active reserve. A small
  internal spiral and faint purple light appear at the bottom during refill.
  Casting stops these immediately. Resource timing is independent of effects.
- Stone clarity uses the original lossless WebP and a canvas backing resolution
  matching displayed size × device pixel ratio, capped at 3. Logical coordinates
  remain 1280×720; glow radii scale with backing resolution. High-quality
  downsampling preserves detail without introducing artificial sharpening halos.
- Each heart has four 1-HP sectors. Start: three hearts / 12 HP. Up to ten red
  hearts support ten gold overlays in the **same positions**, reaching 80 HP.
  Gold drains first, revealing the underlying red sectors.
- Six approved mana forms add rim runes, crystal glyphs, a stationary angular
  circle and a full-mana purple aura. Unlocked reserves set progression; spending
  Soul never removes upgrades. The aura is separate from the brief refill eye
  glow. See [mana evolution](MANA_EVOLUTION.md) for exact layering and tuning.
- Up to five simple rune reserve vessels follow the main rim's curvature.
  Used reserves stay visible and empty; unlocked count and stored amount differ.
- Spell and flask are freestanding symbols. Exhausted flasks desaturate and hide
  their count. Labels show intended bindings; use the preview buttons to act.
- Camera-side shoulder stamina uses four base sectors and one outer quarter per
  upgrade (four upgrades demonstrated). Outer sectors drain first; at full,
  the gauge fades. Boss name and bar appear only with the boss-fight option.

## SoulController contract

The [source](../soulbound-crystal-hud-preview.html) embeds a rendering-independent
`SoulController`. Actual mana pays costs; `displayMana` animates the visible
level. The four phases are `idle`, `draining`, `cooldown`, and `refilling`.

1. Accepted cast deducts its full cost once from the main vessel, cancels transfer
   and retargets the current displayed level over 0.3 seconds without snapping.
2. After the drop, wait 0.5 seconds. Slosh can continue independently.
3. Transfer at `manaMax / 2` Soul per second, left to right through partial
   reserves, with no new cooldown between reserves. Credit equals debit exactly.
4. Stop at full, exhaustion, or death. Any under-full main vessel with reserve
   Soul becomes eligible automatically, including when a preset opens.

Failed casts spend nothing, shake the frame, preserve refill/cooldown and are not
queued. Kill rewards fill the main vessel first, then reserve overflow left to
right, without restarting timers. Presets and manual resource edits reset old
animation state. Reset restores the selected preset. Hidden/offscreen previews
pause without catching up. Reduced motion keeps transfer timing and gradual
levels, but removes tilt, moving wisps and the completion pulse/ripple.
See [Soul behavior](SOUL_BEHAVIOR.md) for detailed visual layering and tests.

## Presets and illustrative values

| Preset | Health | Main Soul | Unlocked reserves / stored full-vessel equivalents | Stamina upgrades |
| --- | --- | --- | --- | --- |
| Strongest full (`strongest`, default) | 12 / 12 | 300 / 300 | 5 / 3 | 0 |
| Strongest partial (`start`) | 12 / 12 | 150 / 300 | 5 / 3 | 0 |
| Gameplay start (`gameplay`) | 12 / 12 | 100 / 100 | 0 / 0 | 0 |
| Strengthened (`grown`) | 25 / 28 | 125 / 220 | 3 / 2 | 2 |
| Gold overlay (`gold`) | 65 / 80 | 220 / 300 | 5 / 3 | 4 |

Every reserve has the same capacity as the main vessel. Capacity is linked to
unlocked reserves: `100 + 40 × reserves`. Upgrades preserve absolute quantities
and start new vessels empty. The partially depleted reference Soul begins
refilling after 0.5 seconds, so its opening screenshot is transient. Preview
spell costs are 25 and 40, and the kill button awards 35; these are demonstration
values, not a finished enemy difficulty/reward table.

## Where to make changes

Use symbol search in the [editable fragment](../soulbound-crystal-hud-preview.html);
embedded image data makes line-oriented navigation less convenient.

| Change | Source location / rule |
| --- | --- |
| Stone pixels and crown silhouette | [Original PNG](../assets/starting-frame-v1.png); retain alpha and dimensions; export [lossless WebP](../assets/starting-frame-v1-lossless.webp), then rebuild. |
| Stone sizing / repeat / crop | `drawReferenceStone`, `drawReferenceAssembly`; adjust crystal and reserve anchors together if artwork proportions change. |
| Reserve placement and rune shape | `drawReferenceReserve`, `glyph`, reference assembly coordinates. Keep the connecting crack routes aligned. |
| Crystal topology and normals | `crystalMesh`, `crystalColor`, `drawCrystalLighting`; keep winding, shared boundaries and complete projected coverage. |
| Soul color / surface depth / eyes | `drawVessel`, `liquidSurfacePoint`, `drawLiquidSurface`; retain the crystal clipping masks and outer lighting order. |
| Wisps, cracks and inlet light | `soulCrackNetworks`, `drawTrappedSouls`, `drawSoulFlow`, `drawSoulInletLight`, `drawSoulSpiral`. |
| Eye completion cue | `SoulController.settling`, `drawSoulSettling`, eye pass in `drawVessel`; require full displayed mana. |
| Payment / cooldown / transfer | `SoulController.tryCast`, `advance`, `gain`, `reset`; keep controller extraction markers used by tests. |
| Mana evolution / full aura | [Pure profile model](../src/mana-evolution.js) and [layer renderer](../src/mana-evolution-renderer.js); edit these sources, then rebuild their embedded copies. |
| Starting state / buttons | `presets`, `applyPreset`, `action`; fields use `normalize` and `update`. |
| Hearts / stamina / boss | `heart`, `staminaFills`, `drawStamina`, `drawBoss`. |
| Sharpness and resolution | `resizeCanvasToDisplay`, resize observer, `renderScaleX`; do not restore a fixed low-resolution backing canvas. |

The file retains earlier procedural frame drawing helpers for comparison, while
the current reference assembly uses the painted texture. Trace the active draw
path before changing a helper; editing unused geometric artwork will not change
the displayed reference. Keep `hudReview` testing hooks for deterministic QA.

## Validation and delivery

Run [controller tests](../tests/soul-controller.test.cjs) after behavior changes;
they cover 20 scenarios, including a 1,000-step randomized conservation check.
Run [evolution model tests](../tests/mana-evolution.test.cjs) for its 16 progression
and effect-state scenarios, and [evolution browser checks](../tests/mana-evolution-preview.test.cjs)
for the 22 integration checks plus comparisons, backgrounds and responsive layouts.
Run [browser tests](../tests/soul-preview.test.cjs) after visual/control changes
and [standalone tests](../tests/standalone.test.cjs) after exports. Browser checks
cover refill interruption, all five stone routes, eye clipping and brightness,
real-time playback, hidden-state pause, reduced motion, 320/360/736/1024 widths
and 2× pixel-density resizing. Review gameplay size as well as close-up.

The [build tool](../tools/build_preview.py) keeps local artwork and embedded data
in sync, then exports `index.html`. The exporter is included for reproducibility;
unused network helpers have been omitted. Source and exported page are checked
for parity. See the [README](../README.md) for exact run commands.

## Deferred integration and next work

The user approved these **future gameplay rules**, but this preview has not
implemented them in Godot: start at 12 HP with proportionally rescaled enemy
damage/healing; remove automatic mana regeneration; award mana on enemy kills
according to difficulty; start with zero reserves and unlock up to five; send
kill overflow to reserves left to right; refill automatically using the cycle
above. The earlier reserve-assisted cast rule is superseded: only current main
mana can pay at acceptance.

When integration is resumed, connect accepted actions and resource events from
[ActionLifecycle](../../../../features/abilities/action_lifecycle.gd) and
[CharacterResources](../../../../features/character/character_resources.gd).
Preserve atomic payment and per-character ownership; never let animation timing
decide whether a spell is paid. Reuse the
[item system](../../../../docs/ITEM_SYSTEM.md) for selected icons, slots and flask
uses. Port the pure controller tests as part of integration and verify death,
retry, pauses, difficulty rewards and both game worlds.

The [dark stone leaking-aura plan](DARK_SOUL_VFX_PLAN.md) is still proposed; current
painted edge wisps, animated refill cracks and the mana-only full aura do not
implement continuous leakage along the health frame.
Audio, a reserve-start rune flare, a full progression art set and production
performance validation on Godot's Compatibility renderer also remain open.
