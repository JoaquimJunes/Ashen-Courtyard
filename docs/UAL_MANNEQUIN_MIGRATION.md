# UAL mannequin player migration and modular armor foundation
Historical migration record. The current native-animation, equipment and artist
pipeline contract is [UAL_FOUNDATION.md](UAL_FOUNDATION.md); the original bake
details below describe the earlier review build.

Status: isolated review build implemented; default-player promotion awaits Neth’s playtest review. Prepared September 24, 2026 using graphify and direct current-source/GLB inspection.

## Objective and boundaries
Temporarily substitute the UAL mannequin for the playable Knight while Neth develops an original fixed protagonist. Establish the UAL skeleton as the lasting animation and equipment foundation. The mannequin must actually support equipping and removing armor, demonstrated with one simple chest piece. Later replace only the visible body with the approved custom character skinned to this skeleton.
Preserve current gameplay rules, collision dimensions, speeds, stamina, damage, action timing, input, camera lock and action-facing ownership. Existing crouch and ledge/shimmy/mantle behavior must remain functional. Do not add crawl, slide, stealth, inventory, armor stats, weight, loot, persistence, new attacks or a character creator. Preserve the original Knight and Warden and all third-party source files. No purchases or additional asset downloads.

## Verified dependencies and implications
Project root: <PROJECT_ROOT>.
- features/character/player.gd:6 exposes model_scene; use this existing substitution point. Canonical player scene and inherited wrapper serve courtyard, laboratory and previews.
- scenes/models/psx_knight.tscn imports fullplate_knight/knight_complete.glb and scripts/psx_knight.gd. That adapter is specific to the old rig; its imported visual has a PI Y rotation.
- features/presentation/knight_visuals.gd:configure assembles both player and Warden and expects WeaponPivot and locomotion.tuning. Preserve this contract.
- scripts/psx_knight.gd:_ready, update_pose, apply_combat_pose, attachment and dodge helpers own clip loading, manual sampling, weapon attachment, pose composition and model-specific material setup. Do not apply the Knight's texture globally to the mannequin or armor.
- features/presentation/character_presentation.gd orchestrates dive, jump, get-up, mantle and crouch, consuming the model interface.
- knight_locomotion.gd:20 and psx_knight.gd:120 assume the first skinned mesh is the whole body. Modular appearance invalidates that assumption. Pose clearance and foot contact must explicitly use registered body/contact geometry, independent of child order.
- knight_locomotion, forward_dive_pose, jump_presentation, get_up_presentation, mantle_presentation and downstream shimmy use old bone names and/or old idle clip names. These require rig-aware access, not a global bone rename.
- reaction_controller injects knight_ragdoll.tres into ragdoll_driver. The driver selects its torso using parentless-bone detection, which is wrong for UAL's non-anatomical root. Use an explicit pelvis anchor with a UAL-specific physical-bone configuration.
- build_roll_animations, build_run_animations and build_jump_animations bake UAL sources onto the old 14-bone rig. build_crouch_animations bakes KayKit onto that rig. Existing baked .tres tracks must not be blindly reused on UAL.

Graph evidence: graphify queries for psx_knight, knight_locomotion, get_up_presentation, mantle_presentation and ragdoll_driver located these relationships, then current source confirmed them. Coverage reports 1,682 nodes, 3,360 edges and zero dangling edges; six stale semantic documents are listed (ARCHITECTURE, CREDITS, DEVELOPMENT_ROADMAP, GAME_CONTEXT, README, RUNNING_ANIMATION). Queries were budget-truncated and dynamic calls are incompletely indexed: this is a dependency guide, not proof of exhaustive isolation. No graph artifacts were changed in Plan Mode.

## Skeleton and animation contract
Use assets/third_party/quaternius/UAL1_Standard.glb as the canonical source. Binary inspection confirms a Mannequin mesh and 65 skin joints. Preserve names including capitalized Head, hierarchy, rest transforms, bind poses and scale. UAL2 has matching joint names, but matching names alone are not proof of identical bind/rest transforms.
Provide a model-local rig profile resolving semantic roles to bone indices and storing basis corrections, attachment offsets and physical/contact settings. Old Knight retains its own profile. UAL roles: pelvis for whole-body pose offset and ragdoll anchor; spine_02 for torso articulation; Head; upperarm/lowerarm/hand_l and _r; thigh/calf/foot_l and _r; spine_03 for back equipment. Preserve the root as the animation reference. Never map every old Body operation to a single bone: separate pelvis motion from torso articulation.
Create a separate UAL adapter implementing the existing consumed model surface: skeleton, animation, locomotion, WeaponPivot, hand attachments, casting/dodge state, pose sampling, reset and dodge helpers. Shared helpers use rig roles; animation aliases isolate legacy k_idle/k_walk and namespaced action clip expectations. Keep the scope local to presentation and reaction configuration; do not rewrite simulation/actions.

Base UAL clips verified locally:
- idle: Idle_Loop; walk: Walk_Loop; jog: Jog_Fwd_Loop; sprint: Sprint_Loop.
- jump: Jump_Start, Jump_Loop, Jump_Land.
- crouch: Crouch_Idle_Loop, Crouch_Fwd_Loop.
- dodge source: Roll.
Use these for the mannequin. Derive directional roll variants from Roll using the existing directional transformation/contact-timing approach adapted to the UAL pelvis/root chain. Preserve forward-dive phase sampling, current recovery behavior and gameplay clocks. Keep procedural combat/cast/heal pose intent and existing action timings; do not opportunistically replace combat with different UAL attack clips.
Keep manual animation advancement and the existing pose ownership/priority. Remove net horizontal locomotion from derived animation tracks; visual vertical articulation must not double-apply physical jump height. Only the existing motor and ragdoll handover control physical movement.
Store derived UAL animations separately from Knight bakes; duplicate resources before editing per-instance state. Record source-to-runtime aliases and deterministic build steps. Absence of full crawl clips is not a reason to add or fake crawling.

## Appearance and armor
One runtime Skeleton3D and one pose driver animate the body and all skinned armor. Equipped assets must not add independently animated skeletons. Rebind skin resources by names/rest transforms to the canonical skeleton and validate compatibility before displaying.
Use a focused appearance component with set_body, equip and unequip operations. Appearance resources carry the body scene or equipment scene, compatible rig identifier, slot and covered body-region list. Slots: head, torso, hands, legs, feet; one item per slot. This is a visual API, not an inventory system.
Prepare a derived mannequin body with independently hideable head, torso, upper arms, forearms, hands, pelvis, thighs, calves and feet regions; left/right limb regions separately addressable. Preserve weights, normals and UVs along region boundaries. Keep source GLB unchanged. Underwear remains part of the body appearance for the final character.
Skinned clothing binds to the one skeleton; rigid helmets/weapons use configured BoneAttachment3D sockets. Existing weapon/casting/back-stow attachments must remain usable during combat and mantle.
Implement a simple skinned chest-piece fitting fixture derived from the CC0 mannequin torso. It covers the torso region and proves equip, replace and unequip. Do not assume the existing fused Knight armor can be reused without fitting and skinning.
Compute hidden body regions as the union of all equipped items' coverage, restoring them correctly on removal. Validate a replacement before replacing a valid item; invalid rig/slot leaves current appearance intact and reports a useful error. No new colliders or gameplay effects for armor.
Use registered base-body contact geometry for existing physical clearance behavior even while covered. Equipment does not change capsule dimensions in this phase. Reset pose/contact caches on body change; ordinary armor swaps must not restart animation or create extra pose drivers. Keep materials local to each body/equipment asset.

## Delivery sequence
1. Capture baseline regression results. Build the UAL model and rig profile in an isolated validation scene using the existing player composition/model_scene injection.
2. Adapt presentation, derived clips, sockets, foot contact, ragdoll and recovery. Keep legacy defaults working for Warden and comparison tests.
3. Add modular body regions and the chest fixture with a laboratory-only equip/unequip control; no new production keybinding.
4. Validate the complete acceptance checklist. Preserve the original Knight scene as rollback. After Neth's mannequin playtest review, set the canonical player's model_scene default to UAL so all normal player hosts use it. Warden keeps its original model.
5. Later supply the approved custom body as a new appearance resource with the same rig and region contract. Keep this body replacement separate from the migration implementation.

## Tests and acceptance
Automated rig/import checks: model loads without script/track errors; all required roles resolve; rest/bind compatibility passes; attachments follow intended hands/back; one skeleton/pose driver; two actors do not share mutable appearance/animation state.
Armor tests: equip, replace, unequip, invalid asset rejection, coverage union and restoration; animated body and chest remain aligned; reset/death/reload clean up attachments; body replacement uses a different mesh layout without relying on first-child mesh ordering.
Behavior tests on UAL plus retained legacy/Warden checks: idle/walk/jog/sprint, starts/stops/reversals, lock-on and running-facing override including depleted stamina, slopes/steps, jump/fall/land, all directional dodges and airborne transitions, crouch and blocked stand-up, light/heavy/combo combat, cast/heal, hit/death, descending-hit ragdoll, get-up, ledge grab/hang/shimmy/mantle and weapon stowing.
Preserve behavior assertions; update tests that hard-code old rig names to use the rig contract. Add UAL import/appearance suites to discovery.
Run focused running, lock movement, dodge/ground roll/dive, jump, crouch poses, combat/cast lifecycle, ragdoll/get-up, ledge/shimmy/mantle and motion-contract suites, then the full runner. Use tools/run_tests.py with repeated --suite arguments; full command from project root: python3 tools/run_tests.py --godot "<USER_HOME>/Desktop/Ashen Courtyard/Godot_v4.6.2-stable_linux.x86_64". Report actual results, not historical counts.
Neth playtests courtyard and Test Grounds at 30/60/120 Hz, clothed and unclothed, checking feet, knees, shoulders, weapon grip, body intersections, armor seams and transitions; pause/reset/retry must remain sound. Automated green tests do not establish visual approval. Do not generate showcase videos/GIFs unless requested.

## Final character handoff and documentation
Give Neth the canonical armature/rest-pose reference with scale, forward/up axes, mesh origin, material and body-region conventions. The broad muscular character must be skinned to this rig, preserving its transforms for this first substitution; do not silently resize bones to fit. Keep the PSX low-resolution texture direction.
Same skeleton preserves the animation contract, but different body proportions still require weight-paint, armor fit and deformation review. Refit the chest fixture to the final body. Test shoulders, elbows, hips, knees, finger grip and extreme poses before approval. Final character artwork/model creation is outside this migration.
When implementation is authorized, save this spec as docs/UAL_MANNEQUIN_MIGRATION.md, update architecture/context/credits and animation-source documentation, and rebuild with the project-specific tools/build_context_graph.py using the interpreter recorded in ../graphify-out/.graphify_python. Run test_context_graph.py; review stale summaries before refreshing their hashes. Include changed files, run instructions, source credits, validation results and remaining visual limitations in the handoff.


## Implementation notes and review instructions

The validation scene is `res://scenes/ual_validation.tscn`. Open it in Godot and
press F6. It reuses Test Grounds with a UAL player override. Esc releases the
mouse through the usual pause menu; the review panel above the menu provides
Wear/Remove buttons. Resume to exercise the same movement and combat controls.
The normal player and Warden remain on the original Knight pending visual review.

The armature and its bind/rest transforms are unchanged. The visual instance
uses uniform scale 0.96 and a 180-degree Y rotation to fit the existing 1.8 m
standing capsule and face gameplay forward. Author replacement meshes in the
source armature's coordinates; do not bake this scene scale into them twice.
The rig identifier is `ual1_65_v1`; rest and bind transform components use a
0.0001 tolerance. Equipment resources contain meshes and bind metadata, never
another animated skeleton. Rigid equipment names its attachment bone and offset.

`tools/build_ual_appearance.gd` assigns complete source triangles to regions by
summed skin weights. It keeps positions, normals, UVs and weights at shared seams.
The chest is an expanded torso shell, a fitting/test fixture rather than final
armor art. Both body and chest retain Quaternius CC0 provenance. Source files are
unchanged. The full hidden body mesh supplies contact geometry independent of
visible region count or equipped pieces.

`tools/build_ual_animations.gd` writes separate animation resources under
`assets/animations/ual/`. Godot removes source `_Loop` suffixes during import;
the builder uses the actual imported names (Idle, Walk, Jog_Fwd, Sprint, Jump,
Crouch_Idle and Crouch_Fwd). Aliases preserve the existing presentation contract.
Crouch idle samples a fixed supported pose to avoid foot drift. Action clips
normalize to one second for the existing phase samplers, without changing action
duration. Root travel is removed; jump height comes from the motor.

Rebuild either derived asset set using Godot 4.6.2 with `--headless --path .
--script res://tools/build_ual_appearance.gd` or `build_ual_animations.gd`.
Use an explicit writable `--log-file` when running in a sandbox.

The test runner accepts `--player-model res://scenes/models/ual_mannequin.tscn`
with selected `--suite` arguments. It substitutes the player scene in each
isolated test process, without changing the saved scene or production default.
Baseline before changes: 3,125 checks passed across 53 suites.

### Rig-specific pose tuning

UAL foot contact includes toe joints as well as the ankle. Recovery uses its own
pose resource, proportioned to the mannequin rather than the taller original
Knight legs. The physical rig explicitly anchors the pelvis and accounts for
its rest orientation when selecting face-up versus face-down recovery. Traversal
uses a small model-only clearance offset and a wrist-to-surface offset; physical
ledge anchors and gameplay travel remain unchanged.

### Artist deliverables

Use the unchanged `UAL1_Standard.glb` armature as the rest-pose reference. Preserve
all 65 names, hierarchy and rest transforms; export mesh-only body/equipment data
with named skin binds and up to four normalized influences per vertex. Source
coordinates are metres, Y-up, facing +Z before the scene's Y rotation. Keep UVs
and pixel textures independent of the old Knight materials. Use the same region
IDs as the generated mannequin: head, torso, pelvis, plus upperarm, forearm,
hand, thigh, calf and foot with `_l` and `_r` suffixes.

Adapt the approved broad muscular body around this armature, then review skin
weights at shoulders, elbows, hips, knees and gripping fingers. Refit each armor
piece and test deformation; matching the skeleton is not automatic clothing fit.
Do not change bind/rest transforms without a separately reviewed rig migration.
The final body asset and final armor art are not included in this review build.

## Verification results — 24 September 2026

- Baseline: **3,125 checks / 53 suites**, all passed.
- Full regression including the new appearance suite: **3,179 checks / 54 suites**, all passed.
- Final UAL substitution run after mannequin-specific physical/pose adjustments:
  **1,535 checks / 19 suites**, all passed.
- Validation scene: headless load and five-frame smoke check passed without errors.
- Context-graph builder tests: **9 passed**. Graph rebuilt with current code and
  document excerpts. Six older semantic document summaries remain excluded as
  stale; their hashes were not restamped without reauthoring those summaries.

Reports: [baseline](validation/ual-migration-baseline.json),
[full regression](validation/ual-migration-regression.json), and
[UAL compatibility](validation/ual-mannequin-focused.json).

**Pending user review:** native in-game appearance, chest fitting, weapon grip,
transition quality and performance at 30/60/120 Hz. Automated pose checks at
these rates passed; they do not substitute for Neth’s visual approval.
Default-player promotion is intentionally pending that review. Do not interpret
this status as approval of final character art or production armor quality.
