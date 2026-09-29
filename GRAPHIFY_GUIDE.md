# Development context graph

The Souls-only graph lives in `../graphify-out/graph.json`; open
`../graphify-out/graph.html` for the subsystem overview. Select a system, then a
file, then expand its symbols/sections. Search matches both paths and contained
symbols; filter Code, Documentation, Tests or Assets. The inspector shows edge
direction, confidence and evidence locations. `graph-detail.html` retains the
full Graphify network. Both views use the same complete JSON graph.

Each file has one canonical node identified by its full path. Alternate extractor
IDs are merged and all edge endpoints are redirected to that node. Functions and
document sections stay distinct. Labels include project-relative paths, and
compatibility wrappers are marked and linked to their implementations. Stable
folder-based subsystem navigation is separate from statistical communities.

Node and edge source paths
are relative to the workspace (`pysnake`), so `souls_prototype/features/...` is
the path to read. The graph is an index of evidence, not a substitute for current
source code or the project workflow in AGENTS.md.

## Query from this project folder

```bash
graphify query "CharacterSimulation MotionResolver CharacterMotor" --graph ../graphify-out/graph.json --budget 1800
graphify query "ledge shimmy corner attachment" --graph ../graphify-out/graph.json --budget 1800
graphify query "stamina ResourceRegenerationPolicy grounded" --graph ../graphify-out/graph.json --budget 1800
graphify query "pause menu settings diagnostics" --graph ../graphify-out/graph.json --budget 1800
graphify query "SoulController Soulbound HUD refill crystal" --graph ../graphify-out/graph.json --budget 1800
graphify query "ManaEvolution full aura reserve acquisition" --graph ../graphify-out/graph.json --budget 1800
graphify explain "character_simulation.step" --graph ../graphify-out/graph.json
graphify affected "character_motor.gd" --graph ../graphify-out/graph.json --depth 2
```

Use exact symbol names alongside natural language for better matching. Query
results retrieve nodes, relationships and source locations; the agent should read
those focused source sections before proposing or implementing a change. Follow
AGENTS.md and distinguish implemented behavior from planned/historical documents.
The `affected` result only follows indexed relationships and is not exhaustive.

## Rebuild after edits or deletions

Run from `souls_prototype`:

```bash
"$(cat ../graphify-out/.graphify_python)" tools/build_context_graph.py
python3 -m unittest discover -s tools -p 'test_context_graph.py'
```

If the recorded Python path is unavailable after reinstalling Graphify, use:

```bash
uv tool run --from graphifyy python tools/build_context_graph.py
```

Use this project builder instead of a plain `graphify update` or `extract`:
Graphify 0.9.67 does not natively extract GDScript. The builder refreshes all
source relationships, removes deleted-source nodes, and preserves a previous
build in `../graphify-out/previous-build/`. It makes no API calls.

## Coverage and trust

- GDScript: functions/signals, local calls, resolvable typed/preloaded receivers,
  explicit resource references and named-class inheritance. This is conservative
  lexical extraction, not a full parser/type checker. Dynamic calls, untyped
  receivers, scene-node bindings and signal connections may be absent.
- Godot scenes, resources and project settings: explicit `res://` dependencies.
- Python tools: Graphify's native AST extraction.
- Markdown: headings, section excerpts and local source/document references.
  Assistant-authored semantic fragments add architecture, rationale and status.
- The standalone [Soulbound HUD preview](art_source/ui/soulbound_hud/README.md)
  is indexed through its guides, explicit file links and a dedicated semantic
  fragment. JavaScript/CJS symbols use native AST extraction; literal local imports,
  HTML scripts/styles and CSS imports add source-backed relationships. JavaScript
  call-target inference is omitted because receiver dispatch is not reliable.
  Tracker sources are indexed; vendor dependencies and generated catalog/preview
  outputs are excluded. Preview documentation distinguishes implemented effects
  from deferred Godot integration.
- Images/models are only represented when referenced by a source file. Generated
  `.artifacts` content (including clean-build source copies), logs, validation
  JSON, import caches and media contents are not analyzed.

`EXTRACTED` marks explicit lexical/AST/document evidence. Typed-receiver call
resolution is `INFERRED` with confidence 0.95. Every stored edge includes an
`evidence` list; multiple relationships between a pair are preserved there and
in `relations`, while Graphify's CLI shows the primary relation.

Semantic fragments match `../graphify-out/souls-docs-*.json`, including the
focused `souls-docs-hud.json` for the visual prototype.
Their `source_hashes` detect changed documents: outdated semantic facts are
omitted on rebuild, and listed in `coverage.json`; fresh heading/excerpt nodes
remain searchable. An agent can refresh affected fragments with the Graphify
semantic-extraction skill, preserving source paths/line evidence and updating
hashes only after rereading those documents. Never restamp stale summaries.

`source_manifest.json` records hashes of the current indexed sources, and
`coverage.json` records coverage, integrity and semantic freshness. Assistant
semantic token usage is unavailable; local rebuilding uses no model tokens.
