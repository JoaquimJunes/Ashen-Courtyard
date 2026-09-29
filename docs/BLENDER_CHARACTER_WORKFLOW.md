# Making a character for the UAL rig

This guide prepares your own meshes for the game's existing animation skeleton.
It does not authorize creating the final knight or armor. Before modeling a new
piece, agree on its references, proportions, clothing, and intended equipment slot.
The mannequin and chest in the review scene are fitting fixtures, not final art.

## The three things to keep separate

- **Mesh:** the vertices and surfaces you model.
- **Armature:** Blender's bones; Godot calls the imported object `Skeleton3D`.
- **Skin weights:** how strongly each bone moves each vertex.

The character's body and deforming armor share one animated skeleton. A rigid
sword or shield follows an attachment point and does not need skin weights.
Using the same skeleton lets meshes share animations; it does not automatically
make armor fit a different body or give a mesh good deformation.

## Start from the project reference

1. In your Steam Blender installation, open **Help → About Blender** and record
   the exact version in your source file's notes. Steam's public release channel
   can update; it is not a fixed exporter version. During a guided walkthrough,
   give this number before following version-specific panel instructions.
2. Save your working `.blend` under `art_source/`, which Godot ignores. Keep
   Blender source files; export a separate GLB for the game. CI uses GLB files
   and does not need Blender installed.
3. Import `assets/third_party/quaternius/UAL1_Standard.glb` with Blender's glTF
   importer. Keep an untouched reference copy of the file. UAL2 has the same
   skeleton in the project's downloaded version, but UAL1 is the rig reference.
4. Save this imported scene as your own starting file. Keep the original
   armature, its 65 bones, names, parent relationships and rest pose unchanged.
   Do not rename, delete, move, resize or reconnect its bones in Edit Mode.
   Do not apply the current animated pose as a new rest pose.

Blender's scene uses Z as up; GLB exports and Godot use Y as up. Import/export
handles that conversion. Fit around the **imported** armature rather than rotating
bones by eye to match a coordinate convention. In exported source coordinates,
the reference faces +Z and is measured in metres. The existing model instance
applies a uniform scale of **0.96** and a **180° Y rotation**. Do not bake those
game-instance adjustments into your new mesh a second time.

## Fit and bind your mesh

1. Once the design is approved, fit the mesh around the reference in its rest
   position. Match shoulders, elbows, hips, knees, wrists and ankles to the
   corresponding joints. Change the mesh to fit this rig; a different bone
   layout or rest pose requires a separate rig migration.
2. Before skinning, keep the new mesh's object transforms consistent with the
   imported reference. Apply transforms to the new mesh only when appropriate;
   do not blindly apply transforms to an already bound armature or reference.
3. Bind the new mesh to the existing armature. In Object Mode, select the mesh,
   select the armature last, and use **Parent → Armature Deform → With Automatic
   Weights** as a starting point. Confirm that its Armature modifier targets the
   reference armature. Automatic weighting is a starting estimate, not approval.
4. For clothing closely fitted to an already weighted body, transferring the
   body's vertex-group weights is often a better starting point. Match groups
   by bone name, check the transfer in difficult areas, then paint corrections.
5. Limit deformation weights to **four influences per vertex**, normalize them,
   and remove unweighted vertices. Do not delete unused bones to simplify an
   armor export: the complete reference armature is part of validation.
6. Test shoulder raises, bent elbows, gripping fingers, deep crouches, knees,
   hips and torso twists. Watch for pinching, detached seams and vertices pulled
   toward the wrong limb. Correct weights before adding more armor pieces.

When exporting, keep the armature in its reference rest position. Preserve all
65 bones, including non-deforming reference/root bones; do not enable an export
filter that drops them. Use the exporter's rest-position option when available.
The asset validator, not the appearance of bone widgets in Blender, determines
whether rest and skin bindings survived the round trip.

## Body regions and armor

The first version has five appearance slots: `head`, `torso`, `hands`, `legs`,
and `feet`. A slot may contain several meshes. The body has these hideable regions:

`head`, `torso`, `pelvis`, `upperarm_l`, `upperarm_r`, `forearm_l`, `forearm_r`,
`hand_l`, `hand_r`, `thigh_l`, `thigh_r`, `calf_l`, `calf_r`, `foot_l`, `foot_r`.

Use separate named mesh objects for body regions and declare their node paths in
the import configuration. Preserve matching positions, normals, UVs and weights
at seams. Keep intended base clothing/underwear in the approved body design.
The pipeline must not guess your final region boundaries from bone weights.

An armor piece declares which regions it completely covers. The runtime hides
the union of covered regions and restores them when the covering items are
removed. Partial coverage should not hide a whole region with exposed skin;
adjust the approved mesh/coverage design rather than masking the problem.

Export deforming armor with the reference armature and its own skin weights.
At runtime the importer keeps its meshes and skin bindings, not another animated
skeleton. Armor retains its own materials. Equipment does not change gameplay
collision dimensions in this milestone.

## Rigid weapons and shields

Rigid assets have no armature requirement. Model and export in metres with a
documented local origin/grip orientation. Their definition supplies fitting
offsets for each attachment; do not scatter offsets through gameplay scripts.

The review character has right/left hand sockets, a left-hip sword socket, and
separate back sockets for the shield and bow. A bow marker represents missing
art; it is not a usable bow. Socket switches currently happen at action boundaries.
Drawing/sheathing animations require a later animation consultation.

## Export, validate, review

- Export selected intended meshes plus the reference armature for skinned assets.
  Use GLB with named skin bindings, four normalized influences, the unchanged
  rest pose, and image-based materials supported by glTF. Export body/armor
  assets without bundled animation tracks; shared animation libraries own them.
- Put GLB exports in a dedicated asset folder, separate from `.blend` files and
  generated runtime resources. Configure explicit source/output paths, mesh-node
  regions, slot, coverage and provenance in the project asset-import resource.
- Run the project's `tools/import_character_asset.gd` with its `--config` option
  and `--validate-only` first. Resolve the reported bone, transform, weight,
  region or material errors. Then run without `--validate-only` to generate the
  runtime resource. Source files remain unchanged.
- Assign the generated resource before previewing; conversion does not replace
  the mannequin automatically. For a **body**, create an inherited model scene
  from `scenes/models/ual_mannequin.tscn` and assign its root's `body_appearance`.
  In your review-scene copy, set `player_visual` to that model scene. For
  **armor**, add the generated appearance resource to the `AppearanceReview`
  node's `armor_samples` array, then choose it in the Appearance page. Give each
  resource a friendly Resource Name in the inspector. For a **rigid item**, set
  an equipment visual definition's `visual` to its generated `.scn`, configure
  its sockets/offsets, and include it in the model's `equipment_loadout` resource.
  Copy the review loadout before changing it if you want to preserve the fixtures.
- Inspect the asset in `res://scenes/ual_validation.tscn` (open it and press F6).
  Open **Esc → Appearance** for its controls.
  Check the body alone, with armor, with all carried items, and in extreme poses.
  Recheck crouching, slopes, rolls, ledges, ragdoll and recovery at 30/60/120 Hz.
- Keep a small successful round-trip example and record Blender/export settings
  before exporting a whole collection. Revalidate that example after Steam
  updates Blender. Source keyframes and the armature reference remain separate
  from mesh-fitting work.

The supplied `body_reference.tres` and `chest_reference.tres` configurations in
`tools/character_imports/` demonstrate this round trip using existing geometry.
They write to `.artifacts/import_examples/`. The converter currently accepts fixed
meshes with dense four-influence weights; it explicitly rejects blend shapes and
sparse skin accessors. Keep armature and skinned-mesh object transforms consistent
with the untouched reference. Read a validation error before changing the rig.

For a guided session, start with one task such as “bind this torso to the UAL
armature” and your Blender version. Work through one operation and inspect its
result before moving to the next. Final appearance and promotion to the normal
player require your playtest approval.

References: [Blender glTF workflow](https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html),
[Godot skin bindings and animation libraries](https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html).
