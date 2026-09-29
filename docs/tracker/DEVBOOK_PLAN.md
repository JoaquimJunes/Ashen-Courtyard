# Dev book: chapter browsing and reliable discovery

This pass organizes existing development records. It adds no game features,
acceptance criteria, artwork or completion claims, and does not change the
project tracking schema.

## Result

Dev book always shows three chapter cards: **Systems**, **Gameplay** and **UI**.
Choose a chapter, then one of its existing topics, to narrow the compact feature
list. The list remains accessible throughout browsing; chapter navigation is
not an additional page that hides all features. Use All features or a removable
selection chip to return to the broader view.

On narrow screens, choose a chapter to reveal its topic shortcuts; the Refine
features controls still offer all topics. The compact header and progress
summary keep chapter navigation near the top of the page.

Chapters and topics come from each feature's existing `area` and `topic`.
Generated `dev_tags` combine the existing topic and subcategory, removing
duplicates and broad chapter aliases such as Game systems and Gameplay
mechanics; they are not new workflow states or invented mechanics. No new editable
tracking fields are required. Existing IDs, notes, criteria, status, attention,
priority, related art and history remain attached to the same records.

## Implementation order

1. **Catalog and search:** derive tags from existing category information. Add a
   pure Dev book search/filter helper with tests before wiring it to the page.
   Normalize case, accents, spaces, underscores and hyphens. Match all search
   words in any order across title, description, existing limitation notes,
   user notes, topics, tags and source paths. Rank title matches above
   description/note matches, and path-only matches last.
2. **Navigation and filtering:** keep chapter cards visible even for empty
   results. Display their topics as keyboard-accessible controls. Preserve a
   compact feature list, remembered search/filter/position state and a clear
   route back to all features. Show active selections as individually removable
   chips and provide Clear filters.
3. **Feature inspection:** structure the existing detail panel into Overview,
   documented implementation evidence with source links, known limitations,
   acceptance checklist and user notes. Display only recorded information;
   absence of a documented limitation does not establish that a feature has no
   bugs. Keep related art and existing tracking controls accessible.
4. **Verify and document:** run focused helper and browser checks, then the
   existing tracker regression suite. Confirm that Art Book settings remain
   independent. Update launcher/usage documentation and refresh Graphify after
   final integration.

## Filter and sorting behavior

- Workflow status is separate from quality and priority: Planned, In progress,
  Ready for review, Completed and Deferred remain available.
- Attention, priority, assessment coverage and original category tags each have
  their own filter. A Completed feature with Bug found must satisfy both
  selections; reporting the bug must not rewrite completion status.
- Different filter groups combine with AND. Where a group permits multiple
  values, its selected values combine with OR. Search combines with the active
  filters rather than replacing them.
- Assessment distinguishes records with acceptance checks from Not assessed
  records. Progress alone does not imply review, approval or quality.
- Sorting supports relevance while searching, name, recent changes, needs
  attention, priority and checklist progress. High priority sorts first;
  progress sorts the most complete assessments first and unassessed records last.
  Existing saved settings remain useful rather than silently being
  discarded. Empty results explain that filters can be removed.

## Progress and evidence

Show checklist progress as **percentage · checked/total checks**, and show
assessment coverage alongside it. Aggregate the underlying checks directly;
do not average per-feature percentages or count the same feature more than once.
Deferred records stay in chapter/topic totals and coverage. Features without
checks remain Not assessed and never receive invented criteria.

Keep generated implementation evidence visibly separate from editable tracking
decisions. Preserve all existing Completed safeguards: a nonempty, fully checked
checklist and explicit user selection are required. Quality flags stay visible
even when checklist progress reaches 100%.

## Acceptance checks

- The three chapters remain visible before and after searching, filtering or
  opening a topic, including when the result list is empty.
- Chapter and topic controls narrow the list correctly; chips and Clear filters
  restore broader browsing without changing project metadata.
- Mixed-order, separator-normalized search finds names, recorded descriptions,
  notes, tags and paths, with useful ranking.
- Every workflow status, attention, priority, assessment and tag filter works
  separately and in combination. Deferred and unassessed totals stay honest.
- Feature details expose the recorded evidence, source links and limitations,
  while checklist and note edits use the existing saved project state.
- Switching books and restarting the page preserves Dev book settings without
  altering Art Book filters or files. Static browsing stays explicitly read-only.
- Keyboard navigation, narrow screens, source links and empty results remain
  usable; list browsing causes no animation/model requests.

Use isolated temporary tracking files for browser tests. Catalog rebuilds and
read-only browsing must leave the real `tracking.json` and original game assets
unchanged.
