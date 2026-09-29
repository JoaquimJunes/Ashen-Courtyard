# Souls-like adventure — delivery roadmap

## Confirmed direction

A single-player fantasy action RPG, inspired by Elden Ring's combat, Zelda's
movement freedom and PS1 presentation. The eventual world is finite,
procedural and fully seamless, including dungeons. Each save has a reproducible
seed. Required landmarks are guaranteed; optional handcrafted structures obey
biome, slope, footprint, spacing and weighted-placement rules.

Builds are freeform. Equipment weight changes handling and costs without removing
core movement abilities. Physical exertion consumes stamina. Spells and permanently
unlocked powered flight share mana; empty mana ends flight with ordinary falling.
Attacks/spells declare compatible movement modes. Surface swimming and underwater
swimming are distinct from the evasive dive-roll.

Buildings eventually collapse physically as connected prebuilt pieces. Terrain
remains intact. Checkpoints respawn ordinary enemies and preserve major changes
and defeated bosses; dropped progression currency is recoverable. Loading uses a
validated safe resume location.

## Milestone 1 — existing prototype foundation

**Implemented; the user has requested starting Milestone 2.** Shared character in the
courtyard, Test Grounds and preview; motor/resources/actions/targeting/presentation
extraction; focused definitions; explicit spell dependencies; lifecycle cleanup;
single regression runner; documentation and native-rendered demonstrations.

The [Section 2 follow-up](docs/SECTION2_REVIEW.md) closes the audited ownership
gaps and brings Warden actions onto the same lifecycle. Current regression:
869 checks across 19 suites. This does not advance the new-mechanic review gate.

Review [the demonstrated scenes and validation](docs/FOUNDATION_REVIEW.md) before
changing another mechanic. Running/dodge tuning, camera and keybinding preferences
are retained. The user subsequently requested removal of the old dodge:
forward dive and grounded side/back rolls are now shared across all hosts.

## Milestone 2 — one movement mechanic at a time

**Step 3, crouching only, is implemented for review.** The user approved controls,
action restrictions, falling and KayKit adaptation. See [Movement 03](docs/MOVEMENT_03_CROUCH.md).
Crawling is deferred until this crouch pass is reviewed.

**User-approved bounded addition: jump-to-ledge is implemented for review.**
Grab/hang/pull-up and the recommended attachment/motor/regeneration extensions
are in [the ledge review](docs/LEDGE_GRAB_PLAN.md). This implements the ledge exit
foundation needed by step 5, not full free climbing. Complete hands-on review
before advancing another mechanic.

The subsequent airborne-motion architecture follow-up is implemented: player and
Warden use the same request/resolver/contact step, and tests cover a minimal NPC,
action release during falls and AI target loss. See the
[actual structure](docs/MOTION_PIPELINE.md) and
[latest validation](docs/validation/motion-contract-final.json). This strengthens
existing movement; it does not advance the new-mechanic review boundary.

**Step 2 is now implemented for review.** The user authorized jumping/falling/
landing and confirmed the design questions, then requested descending-hit and
lethal-landing ragdoll with automatic get-up. See
[Movement 02](docs/MOVEMENT_02_JUMP_FALL_LAND.md). This was the original review boundary; the subsequent crouching approval is recorded above.

**Step 1 is implemented and ready for hands-on review.** The user selected the
adaptive forward dive with current side/back rolls as the main candidate. The
first consolidation pass fixes controller-dependent movement/dodge reach and
adds optional combat practice plus read-only movement diagnostics. Controls,
references, transition rules and acceptance evidence are in
[Movement 01 — running and dodging](docs/MOVEMENT_01_RUNNING_DODGING.md).
Side/back rolls now use the selected reference clips directly on the floor,
with the user's selected 0.70 s timing; forward dive is unchanged.
See [ground-roll review](docs/GROUND_ROLLS.md).
Current regression: **1,347 checks across 22 suites**. This is the preserved pre-jump baseline. The latest jump/ragdoll
regression report is [here](docs/validation/jump-ragdoll-final.json).

| Order | Mechanic | Review focus |
| --- | --- | --- |
| 1 | Consolidate running and shared directional dodge | Momentum, stop/reversal handling, directions, slope/step/gap clearance, recovery |
| 2 | Jump, fall and land | Input choice, takeoff, air steering, ceiling collision, landing |
| 3 | Crouch and crawl | Posture collider, transitions, movement and blocked stand-up |
| 4 | Slide | Entry speed, slope behavior, braking and exits |
| 5 | Free wall climbing | Attachment, lateral/vertical movement, corners, ledge exits and release |
| 6 | Surface swim | Entry, float, movement and exits |
| 7 | Underwater dive/swim | Surface transitions, depth, steering and resource rules |
| 8 | Push, carry and throw | Weight, contact, pickup, persistent held state, aiming/release, impact and reset |
| 9 | Powered flight | Unlocks, takeoff, hover, steering, landing and same-tick mana-exhaustion falling |

Before **each** implementation, define controls, animation references, transition
rules and measurable acceptance criteria. Include optional combat targets and
interruption tests. Validate at 30/60/120 Hz, pause/resume, repeated reset,
collision and animation clipping. Finish and review one mechanic before the next.

## Milestone 3 — structural collapse pilot

Create one small structure made of walls, beams, floors and supports. Store a
connection graph with strengths and ground anchors. After support damage,
recalculate supported groups, turn unsupported connected groups into physical
bodies, and allow impacts to break more connections. Update collision immediately
and request local navigation updates. Measure collapse cost and active bodies
before choosing larger content limits.

Test the shared damage/interaction entry points, falling-piece collisions and
persistence of broken connections and piece transforms/velocities. Significant
structural changes persist; ordinary props and cosmetic debris may reset. Never
recreate saved destruction by replaying physics.

## Milestone 4 — generation, streaming and saves pilot

Start with **256 × 256 m**, **64 m regions**, one seamless modular dungeon,
one required landmark and optional structures. These are test dimensions.

- Place essential landmarks first; then fill eligible locations by weighted rules.
- Validate connectivity, safe spawns, entrances and footprint overlap. Bound retries
  and report invalid layouts rather than silently accepting them.
- Derive independent random streams from seed, generator version, region and pass.
  Test identical output with different region-loading orders.
- Save a manifest containing generator version, landmark placements and dungeon
  layouts. Preserve old manifests deliberately; [Godot RNG internals are not a
  permanent cross-version contract](https://docs.godotengine.org/en/4.6/classes/class_randomnumbergenerator.html).
- Generate plain data off-thread and load resources asynchronously. Use a budgeted
  main-thread queue to activate scenes and collision. The active scene tree is
  [not thread-safe](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html).
- Keep nearby simulation/collision and simpler distant representations. Derive
  prefetch distance from maximum traversal speed and measured loading latency.
- Persist stable entity IDs and world changes separately from generated defaults.
  Use versioned saves, temporary writes and a previous valid backup.
- Save progress, equipment, unlocks, checkpoint, safe location and currency recovery.
  Validate loaded collision before placing the character.

Test boundaries at maximum supported speed; loading spikes; progression/death;
structural saves; interrupted writes; repeated loads; and generator compatibility
before expanding the world. Safe-load validation is not implemented in Milestone 1.

## Milestone 5 — adventure content

**Item foundation delivered separately:** the existing sword, two spells and
flask now use a shared catalog, per-copy inventory, hand/quick-slot loadout,
authored upgrades and versioned record conversion. Test Grounds includes an item
testing panel. This does not deliver loot acquisition, upgrade economy, additional
combat mechanics or gameplay disk saves. See [Item system](docs/ITEM_SYSTEM.md).

Design quest lines, encounters, broader progression and content production using
stable entity IDs, placement anchors and world events. Gameplay rules for these
systems remain deferred. Extend the implemented item foundation when those
mechanics are designed; a general quest framework remains out of scope.

## Performance gates

Reference machine: i5-1135G7, Intel Iris Xe, 8 GB RAM, Linux. Stay on Godot 4.6.2
and Compatibility until measured evidence justifies a change. Target **60 FPS /
16.7 ms**, initially around **1280 × 720 internal 3D** with separately readable UI
and adjustable resolution. The PS1 pixelation shader is an art effect, not proof
of a lower actual rendering cost.

A release build on the real GPU must record frame-time p50/p95/p99/max, peak memory,
loading spikes and active physics bodies. Record build, driver, resolution, route,
warm-up and sample duration. Exercise traversal, combat, region boundaries and
collapse separately. Increase density/destruction only after measurements support
it. An initial native debug-build baseline is recorded in
[PERFORMANCE_BASELINE.md](docs/PERFORMANCE_BASELINE.md). It does not replace release
performance validation. The pinned Linux toolchain now installs matching export
templates, and the clean-check pipeline exports and smoke-tests the packaged game;
see [Development](docs/DEVELOPMENT.md).

## Character art foundation review

The UAL mannequin is now the normal player's approved temporary model, with native
UAL2 A/B light attacks and a sword-only loadout. The separate review scene retains
editable rig/animation profiles, native source locomotion, modular armor and full
carried-equipment controls. The
[foundation contract](docs/UAL_FOUNDATION.md) lists current temporary action
fallbacks and validation. Final body/armor modeling and further replacement action
animations require Neth's design/playtest review.
Visual equipment support does not implement the future inventory/progression
milestone or new weapon mechanics.

## Swimming implementation review

The user approved surface swimming, underwater diving and ledge exits together.
These are now implemented for review using native UAL swim loops and the existing
UAL2 pull-up. Test Grounds station 05 is playable, including breath/stamina rules
and safe water entry. See [acceptance route and boundaries](docs/SWIMMING.md).
Free climbing, currents and underwater combat remain deferred.

The subsequent approved full-body hitbox pass fits 17 animated regions to both
player appearances, confirms damage against those shapes and measures breath at
the visible mouth/nose. See [debug display and acceptance checks](docs/HITBOXES.md).
Motor collision, equal damage, attack timing and native animation keys are retained.
