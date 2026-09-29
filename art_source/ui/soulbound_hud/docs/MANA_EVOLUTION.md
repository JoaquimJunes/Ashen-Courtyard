# Mana evolution — preview implementation

Status on 28 September 2026: **approved visual direction, implemented in the
interactive preview and offline export**. The user's concept review was
“Use this visual direction.” Godot integration remains deferred.

## Strongest concept and review order

The approved [strongest concept sheet](../concepts/strongest-mana-v1.png)
shows full Soul, partial Soul and gameplay proportions using the same three
hearts. [Generation provenance and prompt](../concepts/strongest-mana-v1-prompt.md)
record how the built-in imagegen tool produced it. The generated image is a
design reference, not a replacement texture for the interactive orb.

The [six-stage comparison strip](../concepts/evolution-six-stage-strip.png) is
rendered from the actual preview, with every main vessel full and each unlocked
reserve half full. **Compare six forms** opens the same comparison interactively.
The existing frame artwork, crystal silhouette, dynamic Soul and outer lighting
are preserved. The generated concept's incidental refill stream is not an idle
effect: the actual preview shows it only during reserve transfer.

## Approved progression rules

| Form | Unlocked reserves | Main capacity | New rim runes | Crystal glyphs | Circle | Aura strength |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| Start | 0 | 100 | 0 | 0 | None | 0 |
| Restored | 1 | 140 | 1 | 0 | None | 0 |
| Awakening | 2 | 180 | 2 | 0 | None | 0.22 |
| Empowered | 3 | 220 | 3 | 1 | None | 0.45 |
| Ascendant | 4 | 260 | 4 | 2 | None | 0.70 |
| Strongest | 5 | 300 | 4 | 3 | Complete, with connectors | 1.00 |

The two original crown runes remain. Additional glyph counts accumulate.
Aura-strength values are editable presentation tuning.
The stage follows **unlocked count**, never remaining reserve contents.
Health still controls the heart frame's stone progression.

`main capacity = 100 + 40 × unlocked reserves`. Each reserve shares that capacity.
Acquisition preserves absolute stored Soul in all existing vessels and starts
the new reserve empty. The old fractional reserve representation is converted
against the new capacity; keeping the fractions unchanged would create Soul.
The next controller reset re-evaluates automatic refill eligibility at the new
capacity, without changing existing payment rules.

Reducing progression is a preview-only edit: remove the locked storage and clamp
remaining amounts to the reduced capacity. It does not represent normal gameplay
consumption or loss of an upgrade.

## Model and ownership

[src/mana-evolution.js](../src/mana-evolution.js) contains the immutable six-entry
profile table and rendering-independent helpers:

- `profileFor(unlocked, profiles)` selects permanent appearance/capacity.
- `changeReserves(state, unlocked, profiles)` returns replacement state while
  preserving absolute Soul on acquisition. It does not mutate live state.
- `resolve(state, displayMana, profiles)` separates the permanent stage from
  alive/full conditions. Full requires both actual and displayed mana at capacity.
- `Aura.sample(resolved, time)` uses `SoulController.time` to produce a four-second
  breath and a 0.2-second residual fade after spending. It cannot spend/grant Soul.
  Emission stops immediately when the main vessel becomes under-full. Death,
  reset, stage changes and clock resets clear old residuals.

Full presets and kill rewards activate the aura even with empty reserves. The
existing eye glow still requires completion of a reserve transfer and is never
driven by the breathing aura. Reduced motion produces steady full glow/static
aura, with no breathing. Hidden-preview pause belongs to the Soul clock, so
resuming does not catch up effect time.

## Controls and rendering layers

The **Evolution** selector links reserve count and capacity. The full Strongest
preset starts at 300/300 with five unlocked reserves (three full, two empty).
The partial Strongest preset starts at 150/300 with the same reserves, so refill
begins after 0.5 seconds. Gameplay start has 100/100 and zero reserves. Capacity
and unlocked count are readouts; stored quantities remain editable. Reset returns
to the selected preset. Progression edits clear old animation state and recheck
refill eligibility. Comparison snapshots never advance or replace live state.

[src/mana-evolution-renderer.js](../src/mana-evolution-renderer.js) supplies separate
layers in the existing Canvas renderer. In back-to-front order:

1. Purple aura ribbons and the angular circle, clipped to the mana region.
2. Crystal pigment, Soul surface, refill effects, eyes and crystal glyphs.
3. Outer crystal lighting, spanning whole facets above the liquid and glyphs.
4. Painted stone, added rim glyphs, hearts and flat reserve vessels.
5. Active reserve-to-orb flow along the stone.

The complete circle is visible only in Strongest (five unlocked reserves).
It stays stationary behind the ornaments and reserves. At full, added inscriptions emit light;
below full they remain dimly engraved. Nine deterministic ribbon sites form the
strongest aura, limited to the orb/crown region so hearts, symbols and text stay
clear. Emission stops on an accepted cast; existing ribbons freeze and dissolve
over 0.2 seconds. Reduced motion keeps a fixed faint aura and steady light.

**Frame close-up**, the lighting selector and the courtyard/dark/light background
selector support visual review. Both display scales use the same Soul state.
All six comparison tiles keep identical health and lighting.

## Modification map

| Change | Edit |
| --- | --- |
| Stage names, capacity, inscription counts, aura intensity | `profiles` in [mana-evolution.js](../src/mana-evolution.js). Keep reserve/capacity rules and tests synchronized. |
| Full condition, breathing or fade | `resolve` and `Aura.sample` in that model. Never grant or spend Soul here. |
| Rune shapes and positions | `evolutionRunePaths`, `evolutionRimAnchors`, `evolutionCrystalAnchors` in [mana-evolution-renderer.js](../src/mana-evolution-renderer.js). |
| Aura extent, color and circle geometry | `drawEvolutionAura`, `drawEvolutionCircle`; preserve the mana-only clip and transparent padding. |
| Equal-fill comparisons | `renderEvolutionSnapshot`, `drawEvolutionGallery`; preserve their isolated state and try/finally restoration. |
| Controls, presets, crystal draw order | [soulbound-crystal-hud-preview.html](../soulbound-crystal-hud-preview.html). |

Edit the two standalone JavaScript sources rather than their embedded copies.
[tools/build_preview.py](../tools/build_preview.py) embeds them between named
markers, embeds local artwork, and rebuilds [index.html](../index.html). The
offline export loads no external resources. Regenerate comparison captures after
appearance changes; save the reviewed strip in `concepts/`.

## Validation

[tests/mana-evolution.test.cjs](../tests/mana-evolution.test.cjs) passes 16 scenarios:
exact stage mapping, cumulative ornaments, conservation through every acquisition,
empty new reserves, manual downgrades, invalid inputs, no downgrade on exhaustion,
actual/displayed full gating, unchanged Start, reward/preset versus refill eye
cues, accepted/failed casts, four-second periodicity, frame rates, pause, death,
reset, reduced motion and automatic refill at the new capacity.

Run from the HUD package root:

```sh
node tests/mana-evolution.test.cjs
node tests/soul-controller.test.cjs
python3 tools/build_preview.py
node tests/soul-preview.test.cjs
node tests/mana-evolution-preview.test.cjs
node tests/standalone.test.cjs
```

Browser setup is documented in the [README](../README.md). The 22 evolution
integration checks cover controls, capacity conservation, live-state isolation,
pixel-identical health frame, aura interruption, eye completion, death/reset and
reward activation. They also render all forms against bright/dark backgrounds,
verify 320–1280px layouts and reduced motion, and capture full/partial/gameplay
views plus the strip. Existing Soul and standalone checks preserve timing,
refill VFX, crystal lighting, high-density clarity and offline/source parity.

Remaining work is Godot integration and target-hardware profiling. The separate
[dark stone leaking-aura proposal](DARK_SOUL_VFX_PLAN.md), including leakage at
the health frame's broken tip, has not been implemented by this mana-only aura.
