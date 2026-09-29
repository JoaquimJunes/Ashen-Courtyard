# Project workflow

These are the user's working preferences for this Godot game. Treat them as a
practical reference that can adapt as development continues. Propose useful
workflow additions to the user and wait for approval before adopting them.

## Discuss behavior before new content

When the user requests new mechanics, inventory, items, bosses, enemies, or other
content, ask design questions about expected behavior and logical interactions
with existing systems before implementing unresolved behavior. Use decisions
already confirmed in the conversation; do not repeatedly ask settled questions.

## Agree on acceptance criteria

After the design questions and before implementing new content, agree with the
user on a short acceptance checklist covering expected behavior, important
interactions with existing systems, and what the user should test in-game.
Use this checklist as the feature's completion target. Keep it concise and
reuse already agreed criteria rather than requesting duplicate approval.

## Follow Godot's design philosophy and the project architecture

Follow [Godot's object-oriented design and composition guidance](https://docs.godotengine.org/en/stable/getting_started/introduction/godot_design_philosophy.html#object-oriented-design-and-composition).
Use focused, reusable scenes and objects, scene composition and appropriate
inheritance. Let the game design guide structure rather than imposing rigid
patterns. Keep code well organized and reusable as content grows.

Follow the ownership and interaction contracts in [ARCHITECTURE.md](ARCHITECTURE.md)
and the development boundaries in [DEVELOPMENT_ROADMAP.md](DEVELOPMENT_ROADMAP.md).
Consult the user before substantial architectural changes as previously requested.

## Visual work and feedback

Use **Retro Lowpoly Dark Fantasy** as the guiding art description. Follow the
approved [concept-art workflow](art_source/concept_art_workflow.md): agree on a
brief, explore three directions, refine with keep/change/avoid feedback, obtain
explicit concept approval, and archive versioned images and style notes in the
project and Art Book. Texture treatment, resolution, dithering and lighting are
creative choices, not fixed PS1 constraints. Concept approval is separate from
game implementation; preserve settled decisions and previous versions.

When starting visual work, ask the user for examples and feedback. Reuse approved
references when they already cover the requested change.

For HUD changes, follow the user's sequence: **develop image references → adjust
those references with the user → define behavior → add to the interactive
preview**. Do not implement a newly requested visual direction in the preview
before completing its reference and behavior review.

Only show animation-development GIFs, videos, or examples when the user explicitly
requests them. By default, explain how to test the change in-game; the user will
playtest and provide feedback. Do not automatically prepare animation showcases.

## Effort and communication

Ask permission before work that would consume a substantial amount of tokens
without affecting code or game behavior. Keep routine explanations and context
updates concise; extensive ancillary reports or presentations need approval.

## Public identity and privacy

For publicity, social posts, videos, descriptions, credits and other public-facing
material, identify the user only as **Neth**. Never expose or repeat the user's
real name or personal information. Remove local usernames and filesystem paths,
personal email or account details, location, notifications, tokens, private files
and identifying media/document metadata before anything is published. Internal
development notes are reference material and must not be copied into public
content without this privacy review.

Lead with the outcome. Explain relevant changed files and how to run the result.
Teach the reasoning at a computer-science-student level without unnecessary detail.
For coding tasks, implement the authorized change and run relevant checks.
Ask before destructive changes and preserve existing uncommitted work.

## Graphify development context

For architecture and relationship questions, first query the Souls graph at
`../graphify-out/graph.json` from this folder. For example:
`graphify query "CharacterSimulation motion contact" --graph ../graphify-out/graph.json --budget 1800`.
Use relevant symbols from the query to locate and read current source before
editing. The graph is partial evidence; a missing edge does not prove isolation.
Preserve the design/review gates above and distinguish current implementation
from historical or planned documentation.

Read [GRAPHIFY_GUIDE.md](GRAPHIFY_GUIDE.md) for coverage and refresh instructions.
After relevant changes, rebuild with the recorded Graphify interpreter:
`"$(cat ../graphify-out/.graphify_python)" tools/build_context_graph.py`.
Use this builder rather than plain `graphify update`: it includes Godot formats
that the installed native extractor does not support. Check `coverage.json` for
stale semantic summaries; refresh those from current documents before relying
on them. Rebuilding changes graph artifacts only, not gameplay.
