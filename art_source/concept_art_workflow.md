# Retro Lowpoly Dark Fantasy — concept-art workflow

Approved workflow and guiding direction: 29 September 2026.

## Direction

**Retro Lowpoly Dark Fantasy** replaces “PS1-style” as the guiding description
for Ashen Courtyard. Emphasize deliberate low-poly shapes, a retro sensibility,
and dark-fantasy atmosphere. Texture treatment, resolution, dithering and
lighting are creative choices to explore, not fixed console-era requirements.
Existing artwork is reference material with room for reconsideration; preserve
its recorded approvals and history when proposing a new direction.

## Roles and deliverable

Neth directs; Codex generates. Each cycle delivers one approved static concept
and reusable style notes. Use the [concept brief template](concept_brief_template.md)
to record the subject, decisions and review history. The first brief establishes
concrete visual examples for the revised direction.

## Workflow and review checkpoints

1. **Agree on the brief.** Choose one subject, its gameplay role, mood,
   references, essential features, things to avoid and intended gameplay viewing
   size or distance. Ask for examples and reuse relevant approved references.
   Agree on a short acceptance checklist before generating concepts.
2. **Explore three directions.** Generate three distinct rough concepts with
   comparable framing and detail. Explain each idea and its practical tradeoffs.
   Neth selects one, combines specific elements, or redirects exploration.
3. **Refine the selection.** Use the chosen image as the edit reference. Record
   **keep / change / avoid** feedback, preserve approved features, and address
   one focused group of changes per round. Return to exploration if the
   underlying direction changes.
4. **Approve the concept and style notes.** Review the final image, palette,
   silhouette, materials, texture treatment and lighting. Separate decisions
   applying across the game from choices applying only to this subject.
   Record approval only when Neth explicitly gives it.
5. **Archive in the project and Art Book.** Save versioned images, prompts,
   brief, review history and style notes in the existing art-source structure.
   Refresh the catalog and record the creative decision separately from
   implementation status.

Pause for Neth's review after the brief, the three-direction exploration and
each refinement round. Reuse settled decisions; do not ask for duplicate
approval. Feedback can be as short as “Choose B; keep the silhouette; simplify
the armor.” Further exploration follows that feedback.

## Acceptance checks

Adapt these to the subject during brief review; do not mark them passed in advance.

- Communicates the agreed mood and gameplay role.
- Uses intentional low-poly forms and readable silhouettes.
- Establishes a coherent retro treatment without relying on fine detail.
- Remains recognizable at the intended gameplay viewing size.
- Provides clear guidance for translating the concept into a game asset.

Review the image at both full size and the agreed approximate gameplay viewing
size. This establishes visual intent; actual readability and lighting in-game
are validated during implementation.

## Archive convention

Keep an existing subject's established folder. For a new subject, create
`art_source/concepts/<subject>/` and copy the brief template to `brief.md`.
Use `direction-a-v01.png`, `direction-b-v01.png`, `direction-c-v01.png` for the
initial images, then `concept-v02.png`, `concept-v03.png`, and so on. Keep the
tool's actual image extension. Do not overwrite previous versions. Name the
approved file explicitly in the brief instead of inferring approval from a name.

Save exact generation/edit prompts and referenced image paths in `prompts.md`,
including whether the built-in image tool or an explicitly requested fallback
was used. Save final reusable direction in `style_notes.md`, separating
game-wide decisions from subject-specific ones. Preserve earlier versions and
settled decisions. Copy project deliverables into the project rather than leaving
them only in the image tool's output folder.

Run `python3 tools/build_progress_tracker.py` from the project root, then refresh
the [Art Book](../docs/tracker/index.html) to find the subject's images and
documents. Its existing notes can record the approved version and link related
features; the brief remains the detailed review record. Concept approval does
not mark a game feature implemented or its acceptance checklist complete.
See [tracker instructions](../docs/tracker/README.md) for editable review notes.

## Boundaries

This workflow covers static concepts and notes. Shader changes, replacement
assets, modeling, animation and game integration receive a separate implementation
brief after visual approval. Existing rendering effects remain current
implementation evidence, not requirements of the new direction.

For HUD work, continue the existing sequence: image references → reviewed
references → behavior definition → interactive preview. Do not treat concept
approval alone as approval of unresolved behavior.
