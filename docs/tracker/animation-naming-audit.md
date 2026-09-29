# Animation naming and duplicate audit — 29 September 2026

The Art Book now indexes **486 model clips**, including the **40 newly discovered
Mixamo files**. Display names are separate from playback identifiers. The rename
migration changed **86 individual asset filenames** and **55 import sidecars**;
bundled UAL/KayKit filenames and internal animation names remain unchanged.

## Verified outcomes

- **Nine duplicate pairs** match decoded rig/rest/coordinate data, animation
  curves, timing, interpolation and connection routing. Imported Godot bindings
  and **1,830 poses sampled at 120 Hz plus key times/endpoints** also match, with
  zero measured positional or rotational difference.
- **56 binary sources** are byte-for-byte unchanged. All **30 renamed Godot
  resources** retain serialized animation keys/bindings; all **55 import UIDs**
  survived. The migration verifier allows only recorded resource-path changes.
- All **446 previously cataloged clip IDs and exact preview bindings** survive.
  Tracking and pack-edit files were unchanged by the migration. Manual display
  names, approvals, notes and history retain their original identities.
- Left/right Braced Hang Shimmy are distinct. Corrected crawling and runtime
  derivatives remain separate from source animations. No file was moved to Trash.

## Naming review

19 clip entries have fingerprint-pinned naming review; 433 retain readable source-backed names and 34 explicitly need naming review. These are catalog evidence labels, not user approval.

Representative corrected labels are **Jump to Free Hang**, **Jump to Braced Hang**,
**Braced Hang to Mantle to Crouch**, and **Sprint to Mantle to Crouch**. “Braced Hang
Drop” catches a lower hold; “Braced Hang Fall” lands and recovers upright. Generic
“Hanging” remains uncertain. Reviewed transitions record their steps, starting
and ending poses, evidence and original source hashes in the classification manifest.

## Proposed duplicate keepers

Every redundant copy remains at its original path. Use Art Book → **Duplicate
review** to inspect evidence and select an eligible file for Scrap. Moving it to
recoverable Trash requires the existing separate confirmation.

| Proposed keeper | Redundant source retained for review |
|---|---|
| `anim_mixamo_braced_hang_hop_up_v01.fbx` | `Braced Hang Hop Up (1).fbx` |
| `anim_mixamo_falling_to_landing_v01.fbx` | `Falling To Landing(1).fbx` |
| `anim_mixamo_jump_to_braced_hang_v01.fbx` | `Jumping To Hanging (1).fbx` |
| `anim_mixamo_braced_hang_shimmy_left_inplace_v01.fbx` | `Braced Hang Shimmy.fbx` |
| `anim_mixamo_braced_hang_hop_left_v01.fbx` | `Braced Hang Hop Left (1).fbx` |
| `anim_mixamo_airborne_to_braced_hang_v01.fbx` | `Jump Braced Hang Wall.fbx` |
| `anim_mixamo_braced_hang_shimmy_right_inplace_v01.fbx` | `Braced Hang Shimmy(1).fbx` |
| `anim_mixamo_braced_hang_hop_right_v01.fbx` | `Braced Hang Hop Right (1).fbx` |
| `anim_mixamo_braced_hang_drop_to_lower_hold_v01.fbx` | `Braced Hang Drop (1).fbx` |

## Unresolved and protected work

The audit also records **59 unproven clip-name collisions**. A repeated name inside another library or rig is not proof of equivalent playback. No such source is offered for deletion.

The catalog preserves 173 historical clip records whose KayKit sources were already
missing before this work. They remain unavailable with their annotations intact.
Other unsupported/missing assets keep their existing availability explanations.

## Validation and recovery

Relevant gameplay tests passed **1,642 checks across six suites**. A separate
source copy with no import cache passed clean Godot import and **105 UAL model
checks**. Preview verification covered all 64 Mixamo sources; raw source hashes,
imported clip keys, hierarchy and sampled source poses remain unchanged after
renaming. Browser fixtures cover duplicate grouping, original-name search,
same-source filters, remembered views, approval and keeper protection, independent
annotations and no animation downloads during search.

- [Machine-readable source/duplicate audit](animation_audit.json)
- [Reviewed names and evidence](../../tools/art_animation_classification.json)
- [Persistent old/new path registry](../../tools/art_asset_identities.json)
- [Usage and recovery instructions](README.md#animation-names-and-duplicate-review)

Migration backup/journal: `.artifacts/animation-naming/migration-6e815766f30e49a7ad0d4967c050cbeb/journal.json`.
Detailed local check artifacts are under `.artifacts/animation-naming/`.
