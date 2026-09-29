# UAL character and equipment foundation

The normal player now uses the UAL mannequin, following Neth's approval to switch
it for the UAL2 sword attacks. `scenes/models/ual_player.tscn` inherits the canonical
mannequin with a sword-only loadout; the Warden retains the original Knight model.
The separate `res://scenes/ual_validation.tscn` keeps the armor and equipment review
loadout. Open it in Godot and press **F6**, then **Escape → Appearance** for its
controls. Final character artwork still requires design and visual review.

This milestone adds no final art, inventory, equipment statistics or bow/shield
combat. It reuses the mannequin, chest fitting fixture, existing sword and shield;
the bow is explicitly a labeled attachment marker.

## Rig and pose ownership

`character_rig.gd` is an editable Resource. `data/ual_rig.tres` identifies the
unchanged `ual1_65_v1` armature, semantic bone roles, model scale, contact/reaction
settings and named equipment sockets. The old Knight has its own profile. The
UAL and Knight adapters are siblings over `character_model.gd`; UAL no longer
inherits an adapter that loads and configures the old Knight asset. Runtime models
instantiate `assets/models/ual/runtime_rig.tscn`, a lightweight copy of the exact
65-bone hierarchy and rest pose with the existing `Armature/Skeleton3D` track path.
It carries no original source mesh or animation bank. The mesh-free
`rig_contract.tres` validates names, parents and rest transforms at profile setup;
the authoring sources remain behind `tools/ual_animation_build_manifest.tres`.
`tools/build_ual_runtime_rig.gd` regenerates both runtime rig and contract from the
versioned reference and verifies serialized rest transforms.

`animation_profile.gd` declares native clips, compatibility aliases, temporary
action clips, fallback labels and actions requiring free hands. Playback state
belongs to each character's AnimationPlayer; immutable clip resources are shared.
Full character profiles validate required movement aliases before an atomic
replacement. Item action profiles prepare separate namespaced banks and capture
resolved clips when an action starts; see [moveset authoring](ITEM_SYSTEM.md#add-a-moveset-with-different-animation-clips).
The character pose driver advances and completes poses on physics ticks. Rendering
interpolates completed snapshots; it does not advance action or locomotion clocks.
`tools/build_ual_native_library.gd` extracts the six native locomotion clips from
the unchanged UAL source import without resampling or rewriting their keyframes.
Original source-scene imports remain usable by the legacy bake tools.

Native roles are idle, walk, jog, sprint, crouch idle and crouch walk, plus the
light combo's UAL2 `Sword_Regular_A` / `Sword_Regular_B` and matching `_Rec` clips.
`tools/build_ual_combat_library.gd` validates the UAL2 rig against the 65-bone
reference and copies these four unchanged clips into `native_combat.tres`.
Editable attack definitions map source strike landmarks to the existing gameplay
phases. [Sword attack integration](UAL_SWORD_ATTACKS.md) explains the timing and
playtest. `native_actions.tres` adds UAL1 sword idle/heavy, the four simple-spell
stages and UAL2's root-motion mantle. [Native action playback](UAL_ACTIONS.md)
documents source names, clock mapping and review checks. Jump, directional dodges,
healing, hurt, ledge grab/hang/shimmy and get-up still use explicit temporary
adapters. The review panel lists the distinction.

Motor movement and action timing remain authoritative. Terrain foot placement
operates after sampling grounded walking/running clips, including crouch-walk.
Idle and action animations clear foot locks and retain their authored leg motion;
mantle keeps its separate hand contacts. Presentation blending and corrections
never rewrite imported clips or move the collision body.
Changing body geometry must not require rebaking native animation assets.

## Appearance and equipment interfaces

`CharacterAppearance` owns body regions and armor. Its default slots are head,
torso, hands, legs and feet, configurable at setup. Skinned body and armor meshes
bind to one skeleton; coverage is the union of equipped items' hidden regions.
Replacement validation completes before valid existing appearance is removed.
The review node exposes an `armor_samples` array in the inspector. The Appearance
page selects a sample and equips/removes its declared slot, so imported armor can
be reviewed without editing code. Generated resources are not selected
automatically; see the explicit assignment steps in the Blender guide.

An editable `EquipmentLoadoutDefinition` resource selects the items, available
held layouts and initial layout; the UAL model exposes it alongside its body
appearance in the inspector. An `EquipmentVisualDefinition` declares an item ID, scene or explicit review
marker, held/stowed sockets, occupied hands and local fitting transforms. A
socket definition names its bone and local attachment frame. Rigid carried items
need valid sockets and transforms, not a copy of the 65-bone skin manifest.

`EquipmentVisualController` provides `configure`, `set_loadout`, `set_layout`,
`request_hand_release`, `release_hand_release`, `freeze_for_death` and `reset`.
The chosen layout survives temporary hand-release reasons. Socket changes do
not restart animation, create another skeleton or alter gameplay collisions.

The normal player starts with the sword held in the right hand and stows it at the
left hip when hands must be free. The review loadout defines three layouts:

| Layout | Sword | Shield | Bow marker |
| --- | --- | --- | --- |
| All stowed | Left hip | Back shield socket | Back bow socket |
| Sword and shield | Right hand | Left hand | Back bow socket |
| Bow | Left hip | Back shield socket | Left hand; both hands reserved |

Traversal requests the `traversal` hand-release reason. The equipment action
bridge observes committed action lifecycle events and requests `action_hands`
for bolt, burst and heal, as declared by the animation profile. Reasons overlap;
ending one cannot release another's claim. Items switch sockets immediately.
Authored draw/sheath animations are future work.

Death freezes current placement before reaction callbacks can restore equipment.
Ragdoll retains the items on the skeleton. Player reset clears temporary reasons
and restores the requested layout; unload disconnects lifecycle observers before
the model is freed. The legacy Knight retains its original traversal stowing.

## Artist import and reproducibility

Keep editable Blender files under ignored `art_source/`. Export GLB files to
their declared asset folders. The converter accepts an explicit config resource:

```sh
.artifacts/toolchain/godot --headless --path . --script tools/import_character_asset.gd -- --config res://tools/character_imports/body_reference.tres --validate-only
```

Omit `--validate-only` to write the validated runtime output. The config declares
the source, output, kind, selected mesh-node regions, slot/coverage or rigid
attachment, and provenance. The converter preserves sources and materials and
embeds required dependencies in its runtime result. Invalid input must leave an
existing valid output intact.

The checked-in `body_reference` and `chest_reference` GLBs under
`art_source/import_fixtures/` come from the existing mannequin and chest, with no
new modeling. Their matching configs output to `.artifacts/import_examples/`.
Regenerate these examples with `tools/build_character_import_fixtures.gd`.
`azure_sword.tres` and `wooden_shield.tres` reproduce the staged review equipment.

Skinned exports include the reference armature, but conversion keeps their
geometry, skin bindings and compatibility metadata for the one runtime skeleton.
Rigid equipment exports contain no skeleton. Validate hierarchy/rest/bind data,
four normalized skin influences, region declarations and required sockets before
using an asset. Only selected existing assets are extracted from ignored packs;
their full source libraries stay excluded from imports and release exports.

This converter supports fixed body shapes and dense four-influence skin accessors
(float or normalized unsigned 8/16-bit weights). Blend shapes and sparse skin
accessors reject explicitly. Armature and skinned-mesh object transforms must
export as the reference identity transforms. Import metadata uses canonical bone
names such as `hand_r`; runtime equipment definitions use socket IDs such as
`right_hand`. These are distinct names, not interchangeable identifiers.

Follow the [Blender character workflow](BLENDER_CHARACTER_WORKFLOW.md) for fitting,
weight painting, source axes, export and review. Record the actual Steam Blender
version during the first walkthrough. Consult Neth before creating any new
character or equipment model.

## Acceptance and playtest

Automated checks cover native keyframe preservation, rig compatibility, body and
armor replacement, equipment layout conflicts, actor independence, lifecycle
interruptions and reset/unload. Movement/presentation checks exercise the supported
30/60/120 Hz rates. The packaged-release smoke test visits the UAL review scene,
loads its body/chest/equipment, changes layouts, exercises movement and returns to
the normal courtyard. Run the complete pipeline described in
[Development](DEVELOPMENT.md).

Neth's playtest still decides whether feet, grips, armor seams, clipping,
transitions, ragdoll and recovery look acceptable. A matching rig and green tests
do not establish art approval. The original
[mannequin migration](UAL_MANNEQUIN_MIGRATION.md) records historical development;
this document is the current foundation contract.
