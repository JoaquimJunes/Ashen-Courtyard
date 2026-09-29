# Soulbound HUD — editable visual preview

Saved **28 September 2026**. Open [index.html](index.html) in a current browser.
Everything needed to display it is embedded: it works offline, with no server,
Godot, Node, or Codex installation required. Use **Frame close-up**, the lighting
selector, resource sliders, and action buttons to review it. **Evolution** selects
one of six forms; **Compare six forms** shows them at equal fill. The background
selector checks contrast on courtyard, dark and light backdrops.

This is the canonical project copy of the approved interactive preview. It is
**not connected to gameplay**. The game's existing HUD, resources, damage,
healing, and save behavior have not been changed by this archive. `.gdignore`
keeps preview materials out of Godot's asset import.

## Files and ownership

| File | Purpose |
| --- | --- |
| [Editable preview](soulbound-crystal-hud-preview.html) | Authored HTML, CSS, SoulController, canvas geometry, and rendering. Edit this source, not the generated export. |
| [Evolution model](src/mana-evolution.js) | Six-stage profiles, capacity-preserving upgrades and full-mana effect state. |
| [Evolution rendering](src/mana-evolution-renderer.js) | Rune, circle, aura and comparison layers embedded by the builder. |
| [Evolution guide](docs/MANA_EVOLUTION.md) | Approved progression, layering, controls and tuning instructions. |
| [index.html](index.html) | Generated standalone page. Double-click to view; rebuild after source edits. |
| [Original stone artwork](assets/starting-frame-v1.png) | Transparent high-resolution painting, 1633×963; editable in an image editor. |
| [Lossless display artwork](assets/starting-frame-v1-lossless.webp) | Current frame texture embedded during a build. |
| [Background](assets/courtyard-preview.jpg) | Embedded review backdrop. |
| [Artwork notes](assets/starting-frame-v1-notes.md) | Provenance, generation prompt, asset separation and clarity improvements. |
| [Development progress](docs/DEVELOPMENT_PROGRESS.md) | Approved decisions, modification map, remaining work and integration boundary. |
| [Soul behavior](docs/SOUL_BEHAVIOR.md) | Implemented timing, refill effects and validation. |
| [Dark stone VFX plan](docs/DARK_SOUL_VFX_PLAN.md) | Future leaking-aura implementation; not completed game functionality. |
| [Build tool](tools/build_preview.py) | Embeds local art and exports one offline HTML file using the included renderer. |
| [Controller tests](tests/soul-controller.test.cjs) | 20 deterministic behavior scenarios, including conservation and frame-rate checks. |
| [Browser tests](tests/soul-preview.test.cjs) | Controls, VFX, layout, high-density rendering and reduced motion. |
| [Standalone tests](tests/standalone.test.cjs) | Offline exported-file loading, embedded art, controls and source parity. |

The earlier lossy [WebP](assets/starting-frame-v1.webp) is retained for provenance;
the build never uses it. Keep all editable art and code in this project folder.
The Desktop export is a delivery copy; editing it would be overwritten by a new
export. No changes are saved from the preview's controls between browser sessions.

## Modify and rebuild

From this folder:

```sh
python3 tools/build_preview.py
node tests/soul-controller.test.cjs
node tests/mana-evolution.test.cjs
```

Open or reload `index.html`. Python 3.10+ is required to rebuild; Node 18+ is only
needed for tests. No additional Python packages are needed.

To edit the stone, preserve its transparent canvas, proportions and orb hole in
`assets/starting-frame-v1.png`. Export a **lossless WebP** to
`assets/starting-frame-v1-lossless.webp`, then rebuild. If ImageMagick is installed:

```sh
magick assets/starting-frame-v1.png -define webp:lossless=true assets/starting-frame-v1-lossless.webp
python3 tools/build_preview.py
```

The asset builder replaces the existing embedded image automatically. Changing
its silhouette or canvas dimensions also requires aligning the anchors described
in the modification guide. Avoid lossy re-encoding: it softens carved stone edges.

For full browser checks, install development dependencies once:

```sh
npm install
npx playwright install chromium
npm run test:browser
```

Or use an already installed Chromium with `CHROMIUM_PATH=/path/to/chromium`.
On the current workstation, the existing bundled runtime can be reused without
installing anything:

```sh
export NODE_PATH=<USER_HOME>/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules
export CHROMIUM_PATH=/usr/bin/chromium
node tests/soul-preview.test.cjs
node tests/mana-evolution-preview.test.cjs
node tests/standalone.test.cjs
```

Browser screenshots go into ignored `.artifacts/`. The browser is launched with
`--no-sandbox` for local automated checks of this trusted preview only.

## Export and continue later

After rebuilding, copy `index.html` to the desired location. It carries its own
assets. The saved Desktop delivery is:
`<USER_HOME>/Desktop/Ashen Courtyard/Artistic style/UI/Soulbound HUD.html`.

For a future assistant or collaborator, start with this README and the
[development snapshot](docs/DEVELOPMENT_PROGRESS.md), inspect the named source
functions, and run the controller, evolution, browser and export checks before changing visuals or behavior.
The project [architecture](../../../ARCHITECTURE.md) and
[graph guide](../../../GRAPHIFY_GUIDE.md) explain how this preview relates to
the game. After code or documentation edits, refresh Graphify from the project
root using that guide; never label preview behavior as integrated gameplay.

## Approved mana evolution

The [strongest concept](concepts/strongest-mana-v1.png) was approved before the
six forms were implemented. The [comparison strip](concepts/evolution-six-stage-strip.png)
uses the actual renderer with equal fill. Each unlocked reserve adds 40 maximum
mana, from 100 to 300; acquisition creates no Soul. Rune, circle and aura effects
follow permanent upgrades, while emission requires both actual and displayed
main Soul to be full. The separate refill-completion eye cue stays unchanged.
See the [evolution guide](docs/MANA_EVOLUTION.md) for code ownership and tests.
