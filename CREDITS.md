# Third-party asset credits

## Fullplate Armor Knight — Luana Coppio

- Source: https://magicalgothgirrl.itch.io/fullplate-armor-knight
- License: CC0 1.0 Universal — https://creativecommons.org/publicdomain/zero/1.0/
- Includes the creator's idle/walk animations and knight photo texture.
- Original armor photograph: Petr Kratochvil, CC0, https://www.publicdomainpictures.net/en/view-image.php?image=377696&picture=suit-of-armor
- Changes for Ashen Courtyard: mirrored the missing half of the exported GLB,
  swapped left/right skin joint indices for that geometry, converted emission-only
  texture to albedo, adjusted material tint, and added procedural combat poses.
  The Warden is a scaled/tinted variant with original crown, cape, and greatsword.
- Original files are retained under `assets/third_party/fullplate_knight/`.
  `knight_complete.glb` is our repaired derivative, produced by
  `tools/prepare_psx_knight.py`.

## Universal Animation Library — Quaternius

- Source: https://quaternius.itch.io/universal-animation-library
- Free Standard edition, downloaded 19 September 2026, official upload 17958403.
- License: CC0 1.0 Universal — https://creativecommons.org/publicdomain/zero/1.0/
- The creator credits Gonzalo Furnier for animation work on the library.
- Original non-root-motion `UAL1_Standard.glb`, README, and license are retained
  under `assets/third_party/quaternius/`.
- Uses the source `Roll` animation. Changes: retargeted to the knight's 14 bones,
  blended entry/recovery to its idle pose, redirected torso motion to create
  original left/right/back variants, and baked skinned-mesh floor clearance.
- The source pack supplies one roll; the directional variants were created
  locally and are not advertised as separate Quaternius clips.
- Generated clips: `assets/animations/roll_*.tres`; reproducible with
  `tools/build_roll_animations.gd`. Runtime travel remains controlled by gameplay.

- Running uses `Jog_Fwd_Loop` and `Sprint_Loop` from the same CC0 library
  (Godot imports them as `Jog_Fwd` and `Sprint`). Retargeted to the knight,
  horizontal root motion removed, and boot clearance baked locally. Generated
  `assets/animations/anim_legacy_knight_jog_v01.tres` and `sprint.tres` can be rebuilt with
  `tools/build_run_animations.gd`. Slope adaptation, foot planting, and turn lean
  are procedural additions created for this project.

## PSX Dungeon — Modular Asset Pack — Goblinatron

- Source: https://goblinatron.itch.io/psx-dungeon
- License: Creative Commons Attribution 4.0 International (CC BY 4.0).
- License link: https://creativecommons.org/licenses/by/4.0/
- Includes dungeon architecture, floor tiles, props, and texture atlases.
- Changes for Ashen Courtyard: recentered and scaled the meshes when instancing,
  assigned atlas materials, assembled an open courtyard, and applied our PSX
  lighting/fog shader. Source FBX and texture files remain unmodified.
- Files: `assets/third_party/psx_dungeon/`.
- No endorsement by the original creator is implied. The asset license applies
  to these assets and their derivatives; it does not change the game's code license.

## PS1 / PSX Visuals — snotbane

- Source: https://github.com/snotbane/psx_visuals
- License: Unlicense — https://unlicense.org/
- Downloaded source archive commit: 7dbba0d2ac598dda82984d3d1185e12805500fd3.
- The Bayer dithering matrix/order in `shaders/psx_screen.gdshader` is adapted
  from `addons/psx/shaders/psx_postprocess.gdshader`. The adaptation uses virtual
  pixel coordinates, reduced dithering strength, and a runtime effects toggle.
- The full editor conversion plugin is not installed. The surface shader,
  pixelation pass, fog, and integration code are local implementations for this
  project's Godot 4.6.2 Compatibility renderer.

## Original project assets

The earlier generated knight models, swords, cape/crown accents, synthesized
sounds, gameplay, and integration code were created for this project. Earlier
models remain in `assets/models/`; they are not replacements for or copies of
Elden Ring assets. The YouTube demake was used as visual inspiration only.

## Universal Animation Library 2 — Quaternius

- Source: https://quaternius.itch.io/universal-animation-library-2
- Free Standard edition, official upload 17958478, downloaded 24 September 2026 (UTC).
- License: CC0 1.0 Universal — https://creativecommons.org/publicdomain/zero/1.0/
- The creator credits Gonzalo Furnier for animation work on the library.
- Original non-root-motion `UAL2_Standard.glb`, README and license are retained
  unchanged under `assets/third_party/quaternius/ual2/`; Library 1 is preserved.
- The same official archive's unchanged `UAL2_Standard_RM.glb` supplies the mantle.
  Its internal clip is `ClimbUp_1m`; the `_RM` suffix identifies the source-file
  variant. Source root translation is retained in the library and consumed by
  presentation so gameplay collision does not receive a second displacement.
- 43 source clips including the T-pose. No crouch/crawl clips; slide start/loop/exit
  clips are available for future work.
- Player light attacks use `Sword_Regular_A`, `Sword_Regular_B` and both matching
  `_Rec` clips on the unchanged UAL rig. `tools/build_ual_combat_library.gd` copies
  their original tracks and keys to `assets/animations/ual/anim_ual_native_combat_library_v01.tres`.
  Runtime sampling maps their strike landmarks to existing gameplay phases;
  no source retargeting, mesh-dependent rebaking or new modeling is involved.
- [Full clip inventory and provenance](assets/third_party/quaternius/ual2/ANIMATIONS.md).

## PSX Style Going Medieval — valsekamerplant

- Source: https://valsekamerplant.itch.io/psx-style-going-medieval
- Free base download, official upload 16746048; downloaded 24 September 2026 (UTC).
- License: CC0 1.0 Universal, as stated on the publisher page.
- Files: `assets/third_party/psx_going_medieval/`; unchanged GLB models and textures.
- Complete original archive retained under `source/`; publisher license statement
  preserved in `LICENSE_SOURCE.txt`, alongside any original license/readme.
- No gameplay integration or model modifications.

## Retro PSX Nature Pack — Elegant Crow

- Source: https://elegantcrow.itch.io/retro-psx-nature-pack
- Free base download, official upload 5829435; downloaded 24 September 2026 (UTC).
- License: Models: CC0 as stated on the publisher page. Publisher credits AmbientCG for textures and Pixabay for images; retain those source notices.
- Files: `assets/third_party/retro_psx_nature/`; unchanged GLB models and textures.
- Complete original archive retained under `source/`; publisher license statement
  preserved in `LICENSE_SOURCE.txt`, alongside any original license/readme.
- No gameplay integration or model modifications.

## Retro Medieval Kit — Kenney

- Source: https://kenney-assets.itch.io/retro-medieval-kit
- Free base download, official upload 12993664; downloaded 24 September 2026 (UTC).
- License: CC0 1.0 Universal, as stated on the publisher page.
- Files: `assets/third_party/kenney_retro_medieval/`; unchanged GLB models and textures.
- Complete original archive retained under `source/`; publisher license statement
  preserved in `LICENSE_SOURCE.txt`, alongside any original license/readme.
- No gameplay integration or model modifications.

## KayKit Character Animations 1.1 — Kay Lousberg

- Source: https://kaylousberg.itch.io/kaykit-character-animations
- Free 1.1 edition, official upload 15799903; downloaded 24 September 2026 (UTC).
- License: CC0; the original `License.txt` is retained.
- Files: `assets/third_party/kaykit/character_animations/`; unchanged GLB animation
  sets, mannequin models, and texture. Complete archive and provenance in `source/`.
- The downloaded GLBs contain 139 medium-rig and 34 large-rig animation entries;
  these counts include overlapping motions across rigs, not 173 unique actions.
- Medium-rig advanced movement includes `Crawling` and `Crouching`. Crawl posture
  and compatibility with our Knight have not yet been evaluated.
- Full per-file clip inventory: `assets/third_party/kaykit/character_animations/README.md`.
- `Crouching` is now retargeted for the Knight via `tools/build_crouch_animations.gd`;
  baked walk/idle clips are in `assets/animations/`. Original files are unchanged.
  `Crawling` remains unintegrated.

## Medieval Village MegaKit — Quaternius

- Source: https://quaternius.itch.io/medieval-village-megakit
- Free Standard edition, official upload 12563480; downloaded 24 September 2026 (UTC).
- License: CC0, as stated in the downloaded `License_Standard.txt`, preserved unchanged.
- Files: `assets/third_party/quaternius/medieval_village/`; 176 glTF models with buffers
  and textures. This is a subset of the full collection advertised on the website.
- Original archive, publisher page and checksum provenance are retained in `source/`.
- Full model inventory in the pack's `README.md`. No gameplay integration or model edits.

## Fantasy Props MegaKit — Quaternius

- Source: https://quaternius.itch.io/fantasy-props-megakit
- Free Standard edition, official upload 13887750; downloaded 24 September 2026 (UTC).
- License: CC0, as stated in the downloaded `License_Standard.txt`, preserved unchanged.
- Files: `assets/third_party/quaternius/fantasy_props/`; 94 glTF models with buffers
  and textures. This is a subset of the full collection advertised on the website.
- Original archive, publisher page and checksum provenance are retained in `source/`.
- Full model inventory in the pack's `README.md`. The UAL review stages the
  unchanged `Shield_Wooden` geometry/materials and its required textures only;
  this adds no shield combat or final model art. Other pack models remain unused.

## PSX Starter Kit 0.6

- Source: https://dysfunctional-games.itch.io/psx-starter-kit
- Free archive downloaded 24 September 2026 (UTC).
- Publisher permits commercial game use under the custom terms in LICENSE_SOURCE.txt.
- Files and inventory: `assets/third_party/dysfunctional_psx_starter/README.md`.
- Original archives, publisher statements and checksums preserved under `source/`.
- 30 FBX files extracted with textures; no gameplay integration or model edits.

## PSX Sword / Espada PS1

- Source: https://crimsongcat.itch.io/psx-sword-espada-ps1
- Free archive downloaded 24 September 2026 (UTC).
- No license supplied or stated on the page; usage rights unresolved. See LICENSE_STATUS.txt.
- Files and inventory: `assets/third_party/crimsongcat_psx_sword/README.md`.
- Original archives, publisher statements and checksums preserved under `source/`.
- 1 FBX files extracted with textures; no gameplay integration or model edits.

- Verification of the two PSX downloads: sword loads; Starter Kit loads 29/30 FBX
  files. Baconleaf import fails and six starter files have texture-reference
  warnings. See the starter kit README for exact paths and missing files.

## Derived UAL mannequin review assets

The region-partitioned body, chest fitting shell and in-place animations under
`assets/models/ual/` and `assets/animations/ual/` derive from Quaternius Universal
Animation Library 1 Standard (CC0), already preserved with its source license.
The chest is a development fixture, not a separate downloaded armor pack.
Reproduction and modifications are documented in
[UAL mannequin migration](docs/UAL_MANNEQUIN_MIGRATION.md).

The current `native_locomotion.tres` library copies UAL idle, walk, jog, sprint and
crouch source keyframes unchanged. It adds source provenance and observed contact
metadata; terrain correction occurs during playback. Existing derived jump/roll
clips remain explicitly temporary action fallbacks. Rebuild the native library
with `tools/build_ual_native_library.gd`.

The generated `assets/models/ual/runtime_rig.tscn` and `rig_contract.tres` retain
the reference's 65 bone names, hierarchy and rest transforms. They contain no
new modeling or retargeting. Runtime animation libraries preserve source keys;
the build manifest records their original imports, which remain available to
artist tools but are excluded from the release package. See
[animation ownership and builds](docs/ANIMATION_SYSTEM.md).

## UAL carried-equipment review assets

- `assets/equipment/review/azure_sword.scn` extracts the existing project's Azure
  sword subtree, preserving its geometry and materials; this is not a new model.
- `assets/equipment/review/wooden_shield.scn` extracts `Shield_Wooden.gltf` from
  Quaternius Fantasy Props MegaKit Standard (CC0), with its material and used
  textures. The unchanged source and license remain in the pack above. The rest
  of the pack remains excluded from imports and release exports.
- Thin `.tscn` wrappers instance those self-contained scenes. Rebuild each with
  `tools/import_character_asset.gd` and its matching resource in
  `tools/character_imports/`. Output metadata records source hashes/provenance.
- The bow is a labeled attachment marker. No bow mesh, final armor, or final
  character artwork was created for this milestone.

See [UAL foundation](docs/UAL_FOUNDATION.md) for runtime ownership and review.

## Mixamo crawling

The player crawling motion is derived from the user's Mixamo `Crawling.fbx`
download and retargeted to the existing UAL mannequin. Original files are kept
under `assets/animations/Mixamo/`; the approved retarget and provenance are in
`art_source/mixamo/README.md`. The runtime clip is identified as retargeted Mixamo,
separate from the native Quaternius libraries.
