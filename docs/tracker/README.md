# Dev book and Art Book

On this Linux machine, open **Ashen Courtyard Tracker** from the application menu,
or **Open Project Tracker** in the desktop's **Ashen Courtyard** folder. The
tracker starts automatically when you sign in and recovers if its server exits.
The shortcut also starts the service before opening the page, so no terminal or
Codex task needs to remain open.

Bookmark <http://127.0.0.1:8765/docs/tracker/>. The page and saved data stay on this
machine; no internet connection is needed. The computer must be awake and you
must be signed in. Keep the project at its installed location, or reinstall the
launcher after moving it.

For another Linux installation with a user service manager, run once from the
project directory:

```sh
python3 tools/manage_progress_tracker.py install
```

Optionally pass `--shortcut-dir "/path/to/desktop/folder"` to add a desktop
shortcut. Installation creates the per-user `ashen-courtyard-tracker.service`
and application-menu launcher. It requires no administrator access and never
changes tracker annotations or original assets. Existing managed launcher files
get a `.bak` copy when updated. The service binds only to `127.0.0.1`.

Open or check the installed service with:

```sh
python3 tools/manage_progress_tracker.py open
python3 tools/manage_progress_tracker.py status
```

After changing server code, reload it with
`systemctl --user restart ashen-courtyard-tracker.service`. Inspect errors with
`journalctl --user -u ashen-courtyard-tracker.service -n 30`. To deliberately stop
automatic startup, use `systemctl --user disable --now ashen-courtyard-tracker.service`.
Re-run the installer to restore it. The ordinary shortcut starts an installed
service even after a deliberate stop.

For manual development or systems without that service manager, run:

```sh
python3 tools/serve_progress_tracker.py --port 8765
```

The manual server uses Python's standard library. Keep that terminal running
while editing; do not start a second manual server while the managed service owns
port 8765. Opening `index.html` directly, or using an ordinary static server,
provides a read-only catalog: editable project tracking needs the local service.

The **Dev book** groups existing features into Systems, Gameplay and UI, with
shared topics such as Movement, Combat, Magic, Items and Animation. Original
categories, summaries, implementation evidence and source paths are preserved.
Search and filters narrow the list; select an entry to inspect its sources and
record workflow status, attention flags, priority, notes and acceptance criteria.
A recorded implementation label is evidence about code, not a completion score.

The **Art Book** catalogs existing images, models, maps/scenes, design documents,
interactive previews and recorded world concepts. Origin separates project files
from third-party libraries. `Reference` means the file is under
`art_source/references`; it does not establish approval. Scene entries are scene
files, and the world-concept entry does not imply a finished story. The book links
to files without copying or changing them. Art notes and related feature links
are project metadata, separate from asset contents.

## Dev book chapters, filters and feature details

The **Systems**, **Gameplay** and **UI** chapter cards stay visible above the
compact feature list. Choose a chapter, then a topic, to narrow the list. Topic
and tag buttons are shortcuts to existing information; **All features** and active
selection chips provide a route back to broader browsing. Empty results do not
hide the chapter navigation.

On narrow screens, select a chapter to reveal its topic shortcuts. **Refine
features** still offers the full topic selection. The mobile header and progress
summary use a compact layout to keep the chapters near the top.

Open the filter controls to refine workflow **Status**, **Attention**,
**Priority**, **Assessment** and **Tag** independently. All five workflow states
remain available: Planned, In progress, Ready for review, Completed and Deferred.
A Completed feature can also have Bug found. Assessment distinguishes records
with recorded acceptance checks from **Not assessed** records. Remove individual
chips or choose **Clear filters** without changing any saved feature metadata.

The **SPECIAL** label is available beside the other **Attention** tags in both
books. Select it in an entry's details, then use the Attention filter to find
tagged entries. It does not change workflow status, priority or completion.

Search matches words in any order across names, summaries, recorded limitations,
user notes, topics, generated tags and source paths. Case, accents, spaces,
underscores and hyphens are normalized. Relevance places title matches ahead of
description/note matches, then path-only matches. Sorting also supports name,
recent changes, attention, priority and checklist progress; unassessed records
appear last when sorting by progress.

Chapter and topic summaries show completed checks divided by recorded checks,
alongside assessment coverage. Deferred records remain in totals. Features
without checks stay Not assessed; no acceptance criteria or completion claims
are inferred from their implementation labels. Active search and filters narrow
the list, while chapter totals describe the chapter's underlying recorded work.

Open a feature for **Overview**, **Documented implementation**,
**Implementation notes & known limits**, **Completion checklist** and **Your
notes**. Source evidence links remain available. Recorded implementation notes
are distinct from your editable notes and workflow choices; missing notes do
not establish that a feature is bug-free. Existing related-art links, checklist
completion safeguards and project saves continue to work.

Dev book remembers its search, filters, sort and reading position independently
of Art Book. Generated `dev_tags` use the existing topic and subcategory, with
duplicates and broad chapter aliases removed. This pass adds no new tracking
fields or game content. The implementation and acceptance scope is recorded in
[DEVBOOK_PLAN.md](DEVBOOK_PLAN.md).

## Concept-art workflow

The guiding direction is **Retro Lowpoly Dark Fantasy**. Follow the approved
[concept-art workflow](../../art_source/concept_art_workflow.md) and use its
[brief template](../../art_source/concept_brief_template.md). Both appear in the
Art Book under Design documents. Versioned subject images, briefs and style notes
are cataloged from `art_source` when the catalog is refreshed.

Record the approved image version and creative decision in the subject's brief
and Art Book notes. Concept approval does not establish in-game implementation
or complete a feature's acceptance checklist.

## Art Book topic tags

Open an image, asset or pack's details and use **Tags**. The suggested topics are
**Combat**, **Magic**, **Clothing**, **Armor**, **Weapons** and **Items**. Select a
topic or type a name in **Add custom tag** and select **Add tag**. Existing custom
tags appear as suggestions for other entries. Use a tag's **×** button to remove
it from the current entry. Tags save automatically with the project's notes.

Search matches tag text, including tags on images inside packs. The **Tags**
filter lists the suggested topics and custom tags currently used in the project;
multiple selected tags match any of those tags, and other filter groups further
narrow the results. Tags and filters survive reloads. Select **Images** in the
Type filter to narrow the results to images.

Tags belong to their individual entry. A pack's tags describe the pack and do not
automatically tag its images; open **Image details** to tag an individual image.
Each entry supports up to 32 tags, with up to 60 characters per tag. Extra spaces
are removed and case-only duplicates are rejected. Tags are separate from
Attention flags such as SPECIAL, animation classifications, approval and status.
No topic is assigned automatically from an image's appearance or filename.

## Art Book filters and search

The desktop Art Book has a filter sidebar and a gallery/list switch. On small
screens, use **Filters** to open the drawer; Done or Escape closes it. Editing
status, notes and links stays in the asset detail panel. Quick **Textures**,
**Animations** and **UI** buttons toggle the matching filters. Remove individual
chips or use Clear filters to show all assets.

Choose multiple values within a group to match any of them; different groups
combine to narrow the results. Types overlap: an animated model can appear in
both Models and Animations. UI is a collection across types. Origin and Reference
role are separate filters. New All files visits start with Project files; previously saved
preferences take precedence, including a prior explicit all-origins view. Book
search, filters, layout and reading position remain independent of Dev book.

Search ignores case and treats spaces, underscores and hyphens alike. Words can
appear in any order across an asset's name, named clips, notes and path. Relevance
ranks names and clips ahead of path-only matches; without a search it uses name
order. Other sort choices are Name, Recently changed and Needs attention. Recently
changed uses the latest recorded file modification or user tracking activity.

Use **All files** for the original asset catalog, **Model animations** for
individual 3D clips, and **UI animations** for documented sequences and videos.
Model animations opens category packs: **Combat**, **Movement**, **Interactions**,
**Poses & utilities** and **Unclassified**. Open a category to browse its clips;
the back control returns to the category overview. A clip can belong to several
categories, but overall counts include it once. UI animation frames remain one
sequence entry, alongside the existing video; still review images remain in All
files. These views retain independent searches, filters and reading positions.

Clip details provide editable categories and controlled tags such as Sword
attack, Sword running, Bow aiming, Stealth, Climbing and Item pickup. Empty
category selections appear under Unclassified. **Reset to catalog
classification** restores the documented defaults. Initial labels use explicit
clip-name or source evidence, not a claim that the gameplay mechanic exists.
Category notes and names remain separate from all clips inside them. Source
library, rig and documented root-motion mode are additional discovery filters;
unknown motion is labeled Unknown rather than guessed.

Use **Preview animation**, or select a named clip, to open playback. Unsupported
or unavailable metadata is labeled **Clip names unavailable**. Original image
previews use the existing files; searching
never imports assets or loads models/animations. File classification and clip
indexing happen only during catalog building. Texture membership comes from
explicit texture folders, material image references, or the documented UI atlas;
neighboring screenshots do not become textures. GLB/glTF and Godot text resources
provide named clips directly. For FBX, the builder reads existing Godot import
resources when the local engine and imports are available; it does not run an
import pass. Missing engine/import metadata leaves the animation file searchable
with a clear unavailable label. UI frame/atlas membership is backed by the
existing documentation in `tools/art_catalog_sequences.json`.

The generated catalog adds overlapping `types`, `collections`, `clip_names`,
`clip_status` and `modified_at` fields. These are descriptive metadata, separate
from `tracking.json`. Existing IDs and missing entries retain their annotations;
no new completion or approval claims are inferred.

### Display names and source identities

Open an asset, image pack, clip or category's details, edit **Rename display
name**, and select **Save name**. **Reset to original name** removes the override.
Display names are searchable project metadata: renaming never edits filenames,
source clips, import paths, animation bindings or gameplay resources. Details
continue to show the catalog name, original clip and source-file link. Names and
classification edits participate in normal saves, activity history and backups.

Individual clip IDs combine the parent asset's stable ID with its exact unique
source clip name. Two files may contain the same clip name without sharing
annotations; reordering uniquely named clips preserves their IDs. Duplicate or
unnamed clips have no safe editable identity by default. They remain browsable,
with a reason and a link to edit their parent file; per-clip editing stays locked
until an explicit fingerprint-pinned identity is added to
`tools/art_animation_classification.json`. Missing clips retain their records and
notes. Category IDs remain stable when their display names change.

New authored filenames follow `<type>_<subject>_<purpose>[_<variant>]_vNN.ext`
using lowercase snake_case. Approved examples are:

- `anim_ual_sword_attack_regular_a_inplace_v01.glb`
- `anim_ual_combat_library_v01.glb`
- `anim_ui_soul_wisp_refill_v01.webm`
- `tex_knight_body_basecolor_v01.png`

Include motion qualifiers only when documented. This convention applies to
future files; existing paths and third-party filenames remain unchanged.

### Art review decisions, Scrap and project Trash

Art Book details have an **Art review decision**: **Not decided**, **Approved**
or **Scrap**. These labels belong only to Art Book. Approval does not mark a
checklist complete or change workflow status; Scrap alone moves no files.
Approving an image pack also marks every image currently in that pack Approved,
including images hidden by filters, beyond the current thumbnail page, or
retained as missing-file records. The pack and its images save together in one
atomic update. Images already moved to project Trash are outside the active pack.
The approval count and image badges show the result. **Approve whole pack** also
lets you apply this to a pack approved before this behavior was added, or reapply
approval after reviewing individual images. Existing approvals are not expanded
automatically on loading or catalog rebuilds.

Scrap and Not decided on a pack affect only the pack; they do not reverse its
images' approvals. Notes, names, attention tags and completion stay independent.
Clip/category decisions do not propagate to their source files or members.

Use the **Approved** section for explicitly approved entries, or the **Review
decision** filter when browsing other Art Book views. The dedicated **Scrap**
section lists work you have marked Scrap. Select individual entries or the
currently displayed entries, then use the red **Delete selected** button. The
confirmation lists the exact work, source paths, file sizes and any reference
warnings. **Cancel** changes nothing. A changed selection, stale project state
or changed source must be reviewed again rather than silently substituted.

Confirmed deletion is recoverable:

- Original files move into this project's private Trash folder,
  `.artifacts/tracker-trash/`. They disappear from normal Art Book browsing.
- Virtual entries—image packs, categories and individual clips—are archived
  without deleting their member images or shared animation library.
- Notes, display names and review decisions stay with their original IDs.
  **Restore work** returns files to their original paths and makes archived
  entries visible again. The Scrap label remains until you change it.

The service refuses to move Approved work, source files supporting Approved
clips or packs, known Godot resource dependencies, and files required as feature
or pack evidence. Only original files under `assets/` or `art_source/` are
eligible; private/generated paths and symbolic links are excluded. This checks
known project references rather than claiming a complete dependency analysis.
Read the confirmation's remaining document-reference warnings before proceeding.

Trash persists across service restarts. Restore refuses to overwrite an occupied
original path or use a changed/missing trashed file. A journal allows interrupted
moves to recover safely. If recovery reports an error, keep the Trash folder and
resolve the reported conflict before retrying; do not manually discard its
journals. Tracking JSON exports do not contain the moved asset bytes, so keep
the Trash folder with the project when making a complete recovery backup.

The current Linux implementation uses an atomic no-overwrite move
(`renameat2` with `RENAME_NOREPLACE`). If the operating system or filesystem does
not support it, the service fails clearly rather than falling back to a move
that could overwrite another file.

Deletion and restoration require the local service and saved, conflict-free
metadata. Static browsing remains read-only. Validation uses disposable project
copies: no live project assets are deleted or moved by the browser tests.

## Image packs

In **Art Book → All files**, **Refresh auto packs** rereads the documented pack
definitions and current image catalog, then shows suggestions based on folders
and numbered filenames. Choose **Review suggested pack** to inspect its images,
adjust the selection/name, and explicitly **Create pack**. Refresh itself creates
no suggested packs, approves no images and performs no animation conversion.

Choose **Select images** to show individual image cards with checkboxes. Select
two or more cards, then **Create pack**. Selections stay while you change filters;
the review dialog lists the complete selection. Canceling keeps your selection.
Finishing selection restores your previous grouped/individual-image preference.
An image can belong to a manual pack and a documented pack; file totals remain
deduplicated and manual packs are searchable through all their members.

Inside a pack, each thumbnail has a small **×** at its top-right corner. Confirm
the popup to remove that image from the pack. Its file, notes and approval remain
intact. The cover falls back to a remaining image; an empty pack keeps its name
and notes. Refreshing retains your removals. Removing frames from a documented
sequence pack disables that pack's playback shortcut; individual frames still
link to the original, unchanged sequence.

Manual definitions and removal exclusions live in **pack_edits.json** beside
tracking.json, with their own revision, dated history and recovery `.bak` file.
Back up this file with your project; the existing tracking export covers
annotations, not pack definitions. Explicit catalog builds apply these saved
definitions for static browsing too. Multiple-tab conflicts keep the local
selection and ask you to review/retry against the latest packs. Pack editing
requires the localhost service; static browsing remains read-only.
Whole-pack approval also checks the membership version seen when you made the
decision. If another tab changes the pack, reload its current images before
approving; a failed retry cannot approve images using an outdated membership.

Art Book groups documented animation frames and review sets behind one cover.
Choose **Open pack** for its ordered thumbnail gallery. Images load lazily in
batches; select one to open its original details, notes and flags. **Show
individual images** restores the flat file view and is remembered for Art Book.
**Play animation** appears only for packs with documented playback timing. The
Firefly keyframes and its separate alignment/occlusion review pack remain still
images; no timing is invented.

While reviewing a pack, use **Previous image** / **Next image** or the **Left /
Right arrow keys** to move through its ordered images. The counter shows your
position, including images beyond the current thumbnail page. Navigation follows
the search/filter results captured when you opened the image; it stops at the
first and last image. Arrow keys keep their normal behavior in text fields and
select menus. Missing images retain a placeholder and their saved notes.

Pack details initially show the cover (or the first matching image). Choose
**Image details** to edit that image, or an arrow to review another image.
Each image opens its own notes and review decision. Pack approval also approves
its images; other pack annotations stay on the pack. Unsubmitted name and
new-task text are retained while switching images
within the same review session. Closing returns to the existing pack gallery
and its search.

The gallery's **Whole pack** controls let you approve or mark the pack Scrap,
rename its display name, apply existing attention tags, and write pack notes.
Names use an explicit save; notes and tags save automatically. Approval applies
to all pack images; other edits remain pack-only. **Pack details & notes**
also provides its checklist, status, related features and source evidence.

Search also looks inside packs, including member filenames, paths and saved
notes. Cards report matching image counts; opening a filtered pack initially
shows those images, with a **Show all images in this pack** option. Each matching
image must satisfy every selected filter group itself. Pack notes and flags are
independent of the images; only whole-pack approval also marks its members. Counts show
packs and underlying files separately, without counting a file twice.

Pack definitions live in `tools/art_image_packs.json`: stable IDs, ordered paths,
existing covers and documentation evidence. Rebuilding retains original asset
IDs and missing member records. No files are moved, renamed or deleted. Add packs
from documented relationships, never visual similarity between unrelated files.

## Animation names and duplicate review

Model animation cards use descriptive display names and retain their exact playback
bindings. Use **Starts in**, **Ends in**, **Naming review**, and **Comparison**
filters to find transitions. Names supported only by the source label are marked
source-named; ambiguous transitions carry **Needs naming review**. Entry details
show the naming evidence and original identifiers. Searching finds both the new
name and original filename. Your saved display-name overrides take precedence.

**Duplicate review** shows confirmed copies, unresolved comparisons, distinct
variations and runtime derivatives. Verified equivalents share one card by
default. Expand **Source copies** to inspect each source, or enable **Show
duplicate sources** for separate cards. Counts distinguish motions from source
clips. Each source must independently satisfy every selected filter; notes,
approvals and tags never merge across copies.

The proposed keeper favors an actively referenced file, then approved work, then
a clearly named original. An eligible redundant source offers **Mark redundant
file as Scrap**. This only queues review: the file stays in place. Moving it to
recoverable project Trash still requires selecting it in **Scrap** and confirming
the existing deletion dialog. Approved or referenced work and libraries containing
additional clips are protected. A matching title alone never permits grouping
or removal; different rigs, left/right motions, root-motion variants and corrected
runtime clips remain separate.

The migration uses `tools/art_asset_identities.json` to keep original asset IDs
and clip IDs after renaming. `tools/art_asset_identity_plan.json` records the
old-to-new filename plan; backups and the recovery journal live under
`.artifacts/animation-naming/`. The filename migration is an explicit maintenance
operation, never a browsing action. Internal clip keys and bundled library
filenames remain unchanged. See [the audit](animation-naming-audit.md) for source hashes,
structural comparisons and imported-pose evidence.

Maintenance commands (from the project root):

```sh
python3 tools/migrate_animation_names.py                 # validate a pending plan
python3 tools/migrate_animation_names.py --apply         # apply a reviewed pending plan
python3 tools/migrate_animation_names.py --verify .artifacts/animation-naming/<migration>/journal.json
python3 tools/migrate_animation_names.py --rollback .artifacts/animation-naming/<migration>/journal.json
```

The applied plan is not rerunnable: existing destinations are rejected. Recovery
refuses to overwrite files changed after migration. Stop the tracker while applying
or rolling back, then import through Godot and explicitly rebuild previews,
thumbnail metadata and the catalog using the preparation commands below. Never
manually edit the identity registry to point at a file that has not moved.

## Animation previews

Select **Preview animation** on an asset, or click one of its clip names. The
viewer opens paused. Play/Pause, Restart, the timeline, Loop and speed controls
inspect one animation at a time. Scrubbing pauses playback. Opening another clip
resets it to the beginning; static pose clips have no playback duration.

For 3D assets, drag to orbit, right-drag to pan and scroll to zoom. Front, Side,
Back and Reset view also work without dragging. Focus the viewport and use arrow
keys to orbit. Bones, Wireframe and Ground grid start off. Follow movement moves
the camera with the character; it never removes authored root motion. Space on
the viewport toggles playback. Escape closes the window and returns focus.

The viewer uses the asset's own model or a verified matching rig for standalone
resources. Its model and source are displayed. It plays the selected file's
actual clip: a corrected game animation is not replaced by a similarly named
source-library animation. Gameplay transitions, IK, equipment logic, combat and
Godot-specific material rendering are outside this inspection viewer.

Videos play directly. Documented image sequences use their recorded frame rate
and order, with Previous/Next frame and checkerboard/dark/light backgrounds.
Opening an individual frame starts at that frame. The documented soul-wisp atlas
opens its associated sequence, not an invented sprite-sheet animation. Decoded
sequence images are limited to eight frames at a time.

**Entry details & notes** returns to existing tracking controls. Previewing does
not save notes, alter status, record activity or grant art approval. One viewer
runs at a time; hiding the tab pauses it, and closing releases its resources.
The browser needs WebGL 2 for 3D. Missing files, unknown matching rigs, unsupported
tracks/codecs and stale generated previews show explicit reasons. Animation-only
FBX files with no verified matching mesh remain searchable without a guessed body.

### Mixamo mannequin previews

The 64 cataloged meshless Mixamo clips use two explicit, versioned rig profiles in
`tools/art_preview_retarget_profiles/`. Selection validates bone names, parent
hierarchy, rest transforms and scene coordinates against the recorded
fingerprint. An unfamiliar rig is rejected; matching bone counts are insufficient.
The original FBX must also match its existing Godot import stamp.

The preview-only baker transfers rest-relative world rotations into the UAL
hierarchy and keeps UAL limb translations and scales. Both documented source rigs
and the reference are meter-scale, Y-up, with matching world-axis orientation;
the declared conversion is identity. Source hip displacement relative to its rest
position becomes UAL root displacement, preserving travel distance and direction.
Baking uses 120 Hz plus exact endpoints. It adds no floor clamping, centering,
contact correction or gameplay logic. Different body proportions can produce
contact differences; equal deformation between different bodies is not claimed.

These entries display **Retargeted mannequin preview · visual review pending**.
This is generated provenance, separate from editable status and attention flags.
The previously reviewed `art_source/mixamo/anim_ual_crawl_retarget_reviewed_v01.glb` and corrected
`assets/animations/ual/anim_ual_mixamo_crawling_library_v01.tres` remain distinctly identified. Their
special shoulder/contact adjustments are not applied to other clips.

Provenance records the original asset hash and clip, target rig, profile/version,
source/target rig fingerprints, bake rate and dependency fingerprint. Changing
these dependencies marks a preview stale until explicitly rebuilt. The remaining
unavailable sources need different work: seven Blender files need GLB exports,
one FBX lacks its import, and six files have no playable animation tracks.

Delivery validation on 29 September 2026 covered both source configurations and
all 24 clips: 63,065 retarget checks and 666 exported-pose samples passed. Maximum
sampled GLB position deviation was 0.000001697 m. Browser pose inspection covered
Crouch Walk Left, Run With Sword, Two Hand Spell Casting and raw Crawling at
multiple times and camera angles. The raw crawl retains travel and has contact
height differences; its floor contacts are deliberately not fitted. These checks
establish usable inspection previews, not gameplay or artistic approval.

### Prepare and rebuild

From the project directory:

```sh
python3 tools/prepare_art_previews.py
python3 tools/build_progress_tracker.py
python3 tools/prepare_art_thumbnails.py
python3 tools/build_progress_tracker.py
python3 tools/serve_progress_tracker.py --port 8765
```

The first command requires the existing Godot toolchain and imports for Godot/FBX
conversion. `GODOT_BIN` can point to another compatible executable. Use
`--only native_actions` to prepare a matching path subset, or `--force` to rebuild
cached conversions. Original artwork, rigs and animation resources are unchanged;
derived files live in `docs/tracker/previews/`. Those files are reproducible,
excluded from the Art Book scan and not used by the game. After preparing changed
assets, rebuild the catalog and refresh the page. Normal catalog rebuilds do not
convert assets: missing or outdated preview files are labeled instead.

Thumbnail preparation uses installed Playwright and Chromium to capture each
exact clip at **0.00 s**, at **384 × 256** pixels. It loads each model once and
fits the camera to the evaluated first pose, including skinned bounds. Fixed
lighting and camera direction are used, with no bones/grid overlays, pose
adjustments or root movement. Sequence cards use actual frame zero even when a
pack has a different cover; individual frame files keep their original images.
Videos use their decoded first frame without playback. Empty or transparent
first frames are labeled rather than replaced with a later frame.

The thumbnail command needs Node.js, Playwright available through `NODE_PATH`,
and Chromium on the executable path. This workspace's bundled Node dependencies
are detected automatically; `--node` and `--chromium` select other installations.
Use `--only <source-path-or-title>` for a subset or `--force` to recapture.
No package installation or network upload occurs during preparation.

PNG files and their separate manifest live under `previews/thumbnails/`.
Source/clip fingerprints and renderer dependencies invalidate outdated images.
Unchanged thumbnails are reused; new images and the manifest publish atomically.
Failed, missing or stale thumbnails show a clear placeholder without disabling
an otherwise usable preview. The second catalog rebuild publishes the results.
Gallery browsing and searches load PNGs only, never models or conversion tools.

The catalog's optional `preview` descriptor records availability, format, local
URL, exact clip index/name, duration, model and dependency fingerprint. Converted
clips also carry the exported binding name; this is distinct from the displayed
source name. Sequence descriptors refer to a shared frame manifest instead of
repeating hundreds of URLs on every frame entry. Existing file and pack IDs are
preserved; per-clip records add distinct IDs without replacing their parent files.

Conversion copies mesh, skin, skeleton and animation data into a separate scene;
it does not instantiate scripted player scenes. Round-trip checks compare clip
identity, duration and sampled bone poses before publishing a generated GLB.
Samples include endpoints, 17 phase positions and authored key times. The
acceptance tolerances are 1 mm for world positions and 0.001 for basis-vector
differences; each conversion records measured errors.
Dependency fingerprints include the converter version, rigs and source files.
Outputs are replaced atomically. Unsupported data is rejected rather than
silently removing animation tracks.

Three.js **0.180.0** is pinned under `vendor/three/`, with its MIT license and
package provenance. It loads only when opening a 3D preview. All dependencies
remain local; there is no CDN and no uploading. Search does not load models or
start conversion. Use the localhost service for playback; direct `file:` opening
retains catalog browsing and explains how to start the service. The service
supports byte-range video seeking while retaining its existing path restrictions.

## Tracking, acceptance and completion

Entry details show a brief description beneath the title. Existing catalog
descriptions take precedence; HTML previews use their authored description or
page title, read during catalog rebuilds. Other files show their type, format and
collection. The tracker does not guess undocumented contents.

In Art Book details, **Search related features** matches names, descriptions,
topics, tags, notes and source paths. Words can appear in any order; case,
underscores and hyphens are normalized. Filtering never removes a selection:
the count includes all selected features, including those hidden by the search.
**Clear search** shows the full list. Search remains available in read-only mode.

Review decisions use colored bars: **Approved** is green, **Scrap** is yellow,
and the separate **Delete** action remains red. Tracking states have their own
colors: Planned blue, In progress amber, Ready for review purple, Completed
green and Deferred slate. Text labels remain visible; color does not change any
saved decision or completion rule.

Workflow status, attention and priority are separate fields. Workflow describes
where work stands; multiple attention flags can record testing, bugs, visual
review, improvement or blockers at the same time. Priority describes urgency.

Acceptance checklists measure explicitly recorded criteria. A feature with no
checklist is **Not assessed**, not 0% complete. With a checklist, progress is the
number of checked criteria divided by the number of criteria. `Completed`
requires a nonempty checklist with every criterion checked. Checking criteria is
a human assessment; generated implementation evidence never checks them for you.
Selecting **Completed** with missing or unfinished checks opens the checklist
and focuses the next task, with an explanation instead of a disabled option.
Once every task is checked, use **Mark Completed** or choose **Completed** in
the status menu. Finishing the checklist alone does not change the status, and
completion preserves notes, approval decisions and attention flags.
If changing or deleting criteria would invalidate a Completed status, the book
asks for confirmation before returning the feature to In progress.

Initial criteria are a small representative set quoted from existing acceptance
and playtest documents. Each seed links to its source and starts unchecked.
Unseeded entries remain empty; review scope and add the agreed criteria before
using a checklist as a completion target. Source coverage is intentionally
partial and does not establish that a feature's entire scope is assessed.

Aggregate progress divides all checked criteria by all recorded criteria in the
selected group; it does not average feature percentages. Coverage separately
shows how many features have a checklist, keeping unassessed work visible.
Deferred features remain in overall totals and coverage; deferring work does not
remove it from the denominator or mark it complete. Attention remains
visible independently of a feature's checklist progress or workflow status.

## Project files and recovery

- `features.json` is the curated implementation snapshot. Preserve feature IDs
  and use existing project sources when updating its descriptions or evidence.
- `checklist_seeds.json` contains source-backed initial acceptance criteria.
  Preserve criterion IDs. The builder verifies that each quote still occurs in
  its linked document; it does not derive requirements from implementation code.
- `catalog.json` and `data.js` are generated catalogs for tools and the browser.
  They contain features, individual art entries, image packs, animation clips,
  categories and thumbnail descriptors, not your current project annotations.
- `tracking.json` is the editable project state, created on the first saved
  change. Version five stores notes, workflow fields, checklist assessments,
  related links, display names, optional animation categories/tags, Art Book
  review decisions, custom topic tags and change
  history. Keep this file with the project to carry tracking across
  browsers and machines.
- `tracking.json.bak` holds the previous saved state. Writes replace the state
  atomically. Export a separate copy before importing or restoring data. If state
  is corrupt, inspect both files and restore the suitable copy; the server
  refuses to silently overwrite invalid state.

The server checks revisions to prevent a stale browser tab from overwriting
newer edits. If a save fails or conflicts, retain your edits and follow the
on-screen recovery message before retrying. The generated catalog is independent
of tracking: rebuilding it does not rewrite `tracking.json` or its backup.

Pack IDs are `art:pack:<manifest-key>` and do not depend on the title or cover.
Their metadata stays separate from all member files.

Art IDs are `art:` followed by the first 24 hexadecimal digits of SHA-256 of the
project-relative path. Rebuilding or changing file contents preserves the ID.
Renaming a file creates a new ID; the previous entry remains marked missing so
its notes remain available. Deleted files also remain as missing entries. Restore
the same path to make its existing entry available again. This preserves past
tracking without treating a missing asset as an approved or rejected asset.

## Import and migration

Version-two, version-three and version-four project files open in the new service without
being rewritten by a read. The first actual edit saves version five and retains
the original bytes in `tracking.json.v2.bak`, `tracking.json.v3.bak` or `tracking.json.v4.bak`, according
to the previous version, independently of the rotating `.bak` backup. Existing
notes, criteria, flags, history and IDs remain intact. Older open browser tabs
must reload before saving; they cannot overwrite fields they do not understand.

Use export for a portable copy of tracking. Imports show a preview before any
project state is changed; inspect the affected entries before applying it.
Matching IDs replace the corresponding metadata; records absent from the import
remain unchanged. Backups made while edits are unsaved include a recovery patch;
import uses only that patch so unrelated newer project records are not overwritten.
Imports preserve current project history and record new activity for restored
metadata. The exported JSON retains the original timeline for reference or full
file recovery; importing does not replay old history events. Unknown IDs are retained for recovery instead of being silently
discarded.

Version-one, version-two, version-three and version-four backups remain importable through
that preview. Missing newer fields preserve current explicit naming,
classification, review decisions and custom tags instead of resetting them. Version-five
exports include review labels and topic tags. Old Reviewed notes never become Approved or
Completed automatically. Importing tracking metadata does not restore asset
files from Trash.

The original tracker stored reviews and notes in the browser under
`ashen-progress-v1`. The migration preview can read that browser state or an old
version-1 export and map it into project tracking. Migration requires an explicit
import; it does not delete the old browser copy or automatically claim completion.
An old Reviewed label becomes a "Previous review: Reviewed" note, never Completed.
Browser-local data belongs to its original browser/profile and URL origin, so
open the original location or import its exported file if it is not detected.

## Refreshing the catalog

After updating existing source evidence or adding/removing art files, run:

```sh
python3 tools/build_progress_tracker.py
```

Refresh the browser to load the regenerated catalog. The scan excludes tracker
output, dependencies, vendor folders, caches and generated test artifacts. It
retains previously cataloged entries even when their files disappear. Review the
generated changes before committing; the builder changes no gameplay or assets.

Run the focused catalog checks with:

```sh
python3 -m unittest discover -s tools -p 'test_progress_tracker_catalog.py'
```

Additional checks: `node tools/test_progress_tracker_model.cjs`,
`python3 tools/test_progress_tracker_service.py`, and
`node tools/test_progress_tracker.cjs` (requires Playwright in `NODE_PATH`;
`CHROMIUM_PATH` can select a local Chromium). Browser tests use temporary tracking
files and never modify your project tracking.

Art discovery checks: `node tools/test_art_search.cjs` and
`node tools/test_art_book.cjs` (the same Playwright/Chromium setup as the main
browser suite). Catalog metadata extraction has focused Python tests alongside
the existing catalog checks.

Dev book checks: `python3 tools/test_dev_book_catalog.py`,
`node tools/test_dev_search.cjs` and `node tools/test_dev_book.cjs` (the same
Playwright/Chromium setup). Browser fixtures use temporary tracking data for
status, assessment, navigation, search, responsive layout and persistence checks.

Animation organization checks: `python3 tools/test_art_animation_catalog.py`,
`node tools/test_animation_organization.cjs` (Playwright/Chromium). These cover
clip identities, category overlap, display names, independent notes, filtered
counts, remembered views and browsing without animation downloads.

Animation preview checks: `python3 tools/test_art_preview_metadata.py`,
`python3 tools/test_art_preview_exporter.py` and
`node tools/test_animation_preview.cjs` (same Playwright/Chromium setup).
The browser suite uses actual prepared assets and isolated temporary notes.

Thumbnail checks: `python3 tools/test_art_thumbnail_metadata.py` and
`node tools/test_art_thumbnails.cjs` (same Playwright setup). The latter starts a
temporary read-only server, checks actual models/video and a transparent-frame
fixture, and makes no tracker edits.

Scrap checks: `python3 tools/test_art_scrap_store.py` and
`node tools/test_art_scrap.cjs`. The browser suite copies the tracker into a
temporary project and exercises approval protection, confirmation cancellation,
stale selections, file moves, restart recovery and restore conflicts there.
Its original-image fixtures are disposable copies; the live game assets remain
untouched.

Image pack checks: `python3 tools/test_art_image_packs.py`,
`node tools/test_art_packs.cjs` and `node tools/test_image_packs.cjs`.
Mannequin checks: run the project Godot executable with
`--headless --path . --script res://tools/test_art_preview_retarget.gd`, then
`node tools/test_mannequin_previews.cjs` for the prepared catalog/browser checks.

### Preview code ownership

- [animation-preview.js](animation-preview.js) owns the dialog, playback clock,
  keyboard controls and disposal lifecycle, independently of saved tracking.
- [preview-model.js](preview-model.js) owns local glTF loading, skeleton playback,
  camera controls and GPU resource disposal.
- [preview-media.js](preview-media.js) owns native video and bounded frame-sequence
  loading. [animation-preview.css](animation-preview.css) supplies responsive layout.
- [art_preview_metadata.py](../../tools/art_preview_metadata.py) validates preview
  descriptors and dependencies; [prepare_art_previews.py](../../tools/prepare_art_previews.py)
  performs explicit preparation; [export_art_previews.gd](../../tools/export_art_previews.gd)
  creates and validates inspection copies using Godot.
- [art_animation_catalog.py](../../tools/art_animation_catalog.py) creates stable
  clip/category records; [art_animation_taxonomy.json](../../tools/art_animation_taxonomy.json)
  defines controlled labels. [animation-browser.js](animation-browser.js) projects
  the separate model/UI views without loading animation assets.
- [art_thumbnail_metadata.py](../../tools/art_thumbnail_metadata.py) validates
  derived images; [prepare_art_thumbnails.py](../../tools/prepare_art_thumbnails.py)
  runs the isolated local [thumbnail renderer](thumbnail-render.html). Normal
  catalog builds only read these outputs.
- [art-review.js](art-review.js) owns explicit Scrap selection and confirmation;
  [art_scrap_store.py](../../tools/art_scrap_store.py) validates protected work,
  journals recoverable moves and restores files without overwriting paths.
  [test_art_scrap_store.py](../../tools/test_art_scrap_store.py) and
  [test_art_scrap.cjs](../../tools/test_art_scrap.cjs) verify these operations only
  against disposable test projects.

- [art_image_packs.json](../../tools/art_image_packs.json) declares documented
  image groups; [art_image_packs.py](../../tools/art_image_packs.py) builds stable
  pack/member metadata. [art-packs.js](art-packs.js) performs grouped filtering
  without merging member annotations.
- [art_preview_retarget.gd](../../tools/art_preview_retarget.gd) performs the
  preview-only 120 Hz transfer. Its explicit
  [common profile](../../tools/art_preview_retarget_profiles/mixamo_common_v1.json)
  and [crawl profile](../../tools/art_preview_retarget_profiles/mixamo_crawl_v1.json)
  validate the two known source configurations.
