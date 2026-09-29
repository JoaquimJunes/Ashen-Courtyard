# Ashen Courtyard — current development context

**Art direction and workflow (29 September 2026):** **Retro Lowpoly Dark Fantasy**
replaces “PS1-style” as the guiding description. Low-poly forms, retro sensibility
and dark-fantasy atmosphere guide exploration; texture treatment, resolution,
dithering and lighting are open creative choices. The approved
[concept-art workflow](art_source/concept_art_workflow.md) establishes brief
review → three rough directions → focused refinement → explicit concept approval
→ versioned project and Art Book archive. Each cycle delivers one concept plus
style notes; game-wide and subject-specific decisions are recorded separately.
Use the [brief template](art_source/concept_brief_template.md). The first approved
[player brief](art_source/characters/ual/player_concept_brief.md) explores a
broad-built fallen sacred warrior's awakening: left chest/arm stone, spiral
runes, a half-full purple crystal on the back of the left hand, faint submerged
eyes and five empty sockets. The main mana gauge is its ritual-object reference.
The [three-direction review](art_source/characters/ual/awakening_concepts/README.md)
contains close-fitting, fractured and carved stone studies with hand close-ups.
Current v02 sheets correct mirrored v01 hand insets. Neth selected **B — Fractured
Stone** and approved [six life-progression forms](art_source/characters/ual/awakening_concepts/life_progression/README.md).
Permanent maximum-life upgrades join fractured stone into denser intact surfaces
at the same size, while exposed left arm/hand skin progressively petrifies up to
the fingertips. The chest boundary stays fixed. Revision 02 adds darker charcoal,
varied rune symbols and six aligned columns (characters above matching hands).
Damage/healing do not reverse the stage, and mana evolves independently. Revised
sheets have been superseded by Neth’s approved six-image selection in revision 03.
The comparison and source manifest follow his exact attachment order; only Stage 0
needed its printed heading relabeled. Exact life thresholds
and game integration remain deferred; earlier versions remain archived.

**HUD visual archive (28 September 2026):** The reviewed Soulbound HUD now has a
durable [editable project package](art_source/ui/soulbound_hud/README.md) and
offline `index.html`. It preserves the crown/stone artwork, faceted crystal,
dark Soul slosh, automatic reserve refill, moving souls, bottom inlet light,
full-refill-only eye glow and sharper high-density stone rendering. Approved
[six-stage mana evolution](art_source/ui/soulbound_hud/docs/MANA_EVOLUTION.md) now
links 0–5 reserves to 100–300 capacity without granting free Soul. New rune,
circle and full-mana aura layers retain the existing health frame; the preview
includes an equal-fill comparison, bright/dark backdrops and reduced motion. The
[development snapshot](art_source/ui/soulbound_hud/docs/DEVELOPMENT_PROGRESS.md)
records decisions, tests and future modification points. This is still a
browser preview: the 12-HP balance rescale, kill-based mana rewards, reserves,
and replacement game HUD have not been integrated into Godot by this work.

**Latest presentation change (26 September 2026):** Neth approved switching the
normal player to the UAL mannequin for native UAL2 `Sword_Regular_A` / `B` light
attacks, including their matching recovery clips. The player carries only its
sword; the separate appearance-review scene retains shield/bow-marker layouts
and armor controls. The Warden remains on the old Knight model. Existing light
attack timing, costs and damage remain authoritative. Heavy attacks and other
unconverted actions still use temporary adapters. See
[sword integration and playtest](docs/UAL_SWORD_ATTACKS.md). This approval does
not approve final character artwork or resume Blender modeling.

**Latest movement addition (24 September 2026):** Crouching is implemented for review;
crawling remains deferred. See [Movement 03](docs/MOVEMENT_03_CROUCH.md) for approved
controls, behavior, ownership, limitations and validation. Older pending-crouch
notes below describe prior milestone boundaries.

**Snapshot: 23 September 2026.** This describes the local working tree, including
uncommitted work. Read it with [ARCHITECTURE.md](ARCHITECTURE.md),
[DEVELOPMENT_ROADMAP.md](DEVELOPMENT_ROADMAP.md) and
[Milestone 1 validation/review](docs/FOUNDATION_REVIEW.md) and the latest
[Section 2 ownership follow-up](docs/SECTION2_REVIEW.md). Current work is
[Milestone 2.2 — jumping/falling/landing and ragdoll](docs/MOVEMENT_02_JUMP_FALL_LAND.md).

## 23 September bug fixes

F4 effect changes now notify the Display editor, keeping its checkbox and Apply
state synchronized without false unsaved-change warnings. Returning to Debug via
Back refreshes its snapshot while retaining keyboard focus. Early action rejection
now emits the same completion signal as queued requests, so diagnostics include
reasons such as disabled combat. `tests/run_bug_fixes.gd` covers all three cases
in both worlds and verifies buffered actions and resource amounts are preserved.

## Small UI/performance improvements

Unchanged ledge debug paths reuse cached geometry; changes to endpoints or parent
transforms invalidate it. Settings remembers the last Camera/Controls/Display tab
across levels and restarts, independently of Apply. These changes passed 232 checks
across four relevant suites. A native Iris Xe debug-build lab benchmark is recorded
in [PERFORMANCE_BASELINE.md](docs/PERFORMANCE_BASELINE.md); release-build validation
remains outstanding.

## Latest interface update

The courtyard and Test Grounds share a muted olive/stone menu with grouped
navigation and Back/focus history. Esc → Settings contains Camera, categorized
Controls and Display. Apply saves and stays open; Reset to defaults stages
changes (all groups for controls). Apply is hidden when no values differ.
Leaving unapplied edits offers Apply changes (all changed tabs), Discard, or
Keep editing. A failed save keeps the warning open and retains remaining drafts. Existing camera/keybinding files remain compatible.

Esc → Test Grounds contains lab travel and testing commands. Esc → Debug pauses
for detailed inspection; F3 enables a small live overlay in either level.
The old always-visible lab title, instructions, resource text and practice status
overlays have been removed; use the shared menu and optional diagnostics.
Hand/path/capsule overlays are optional. Diagnostics read existing character
state and keep at most 40 recent events. No movement mechanics changed.
Implementation: `features/ui/`; integration checks: `tests/run_menu.gd`.
Validation: 43 regression suites / 2,502 checks passed; follow-up menu, camera
and controls checks passed after the final navigation/layout fixes. Native 720p
UI checks on Iris Xe verify mouse capture and visible controls. Local reports:
`.artifacts/tests/interface/`.

## Latest addition: sideways hanging and automatic corners

**22 September correction:** Pull-ups now accept a supported landing up to the
existing 0.6 m step limit higher or lower than the lip, using bounded inward
search and a clearance-tested path to the actual destination height. Gaps,
excess height and blocked ceilings reject without spending pull-up stamina.
See [targeted regression results](docs/validation/uneven-mantle-related.json):
315 checks across 6 suites pass. The new fixture checks ±0.6 m at 30/60/120 Hz.

Ledge entry now skips lips at or below the knight's default jump height
(currently 1.2 m above his takeoff feet level, with 1 mm comparison tolerance).
The movement coordinator records takeoff height; traversal owns the eligibility
rule and rechecks it when accepting a grab. Existing grips and sideways support
checks remain separate. See `tests/run_ledge_height.gd` for real-jump boundary
checks at 30/60/120 Hz and elevated-platform coverage.

Left/Right now move along the current ledge, independently of camera orbit, and
round validated inside/outside corners. Stop/reverse works mid-turn. Stamina stays
unchanged; Forward still requests a validated pull-up and Dodge releases. Gaps,
unsupported/excluded geometry and blocked routes retain the last safe hold.

Use **Test Grounds → Esc → Test Grounds → Corner tests**. The feature follows the existing
attachment/action/motor architecture; no separate body mover or vertical free
climbing was added. See [implementation and previews](docs/LEDGE_SHIMMY.md) and
[latest validation](docs/validation/shimmy-final.json): **2,254 checks / 40 suites pass**.
The earlier 2,140-check
ledge report below is a preserved baseline. Review this movement before advancing.

## Earlier implemented feature: jump, ledge hang and pull-up

The [ledge implementation and review](docs/LEDGE_GRAB_PLAN.md) now includes the
approved shared regeneration policy, persistent attachment and constrained motor
contract. Jump toward an eligible static lip; release Forward to hang, hold it to
pull up, and press Dodge to let go. Forward is independent of camera orbit.
Jump still costs 15 stamina; pull-up costs 10 once; hanging and ordinary airborne
travel neither regenerate stamina nor add an ongoing drain. Explicit action costs
still apply. Attached accepted hits enter ragdoll. Static geometry is detected
automatically, with `no_ledge_grab` exclusions and separate grip/standing validation.

Try **Esc → Test Grounds → Enter Character Test Grounds**, then
**Esc → Test Grounds → Ledge tests**. Station 04 has 1.5 m,
2.5 m, blocked-ceiling and excluded-surface fixtures. Esc → Debug offers hand/path overlays; F3 enables live diagnostics.
The same character implementation runs in the courtyard, lab and actual capture.
Current evidence: **2,140 checks / 37 suites pass**; [full regression](docs/validation/ledge-final.json),
[clip](docs/ledge-grab/ledge-pull-up.gif), [decision 010](docs/decisions/010-ledge-attachment-and-regeneration.md).

This implementation is awaiting hands-on review. Free climbing and the future
flight-magic stamina exception are not implemented. Do not begin another movement
feature until the user reviews the ledge mechanic.

## Current motion architecture

The latest authorized refactor replaces independent player/boss horizontal motion
loops with `CharacterSimulation`, typed `MotionRequest`, `MotionResolver` and
per-action `MotionBudget`. Side/back and landing rolls declare retained departure
velocity; forward diving declares directed air velocity. Empty ground travel or
an action finishing cannot implicitly stop airborne momentum. AI target loss now
produces idle input while physics continues. The actual file tree and extension
rules are in [MOTION_PIPELINE.md](docs/MOTION_PIPELINE.md) and
[ADR 009](docs/decisions/009-shared-motion-contract.md).

Outer controller/resource/presentation policies remain in the compositions.
Knight fall damage/skill checks/ragdoll have not been added to the Warden.
That motion refactor preceded the ledge feature described above.

## Current boundary

**User review boundary:** the user authorized jumping, falling and landing, then
added descending-hit/lethal-landing ragdoll and confirmed automatic get-up.
The subsequent cliff-dive/timed-landing refinement is also implemented: airborne
forward travel continues until contact; a fresh Dodge in the final 0.15 s spends
25 stamina for a 0.40 s grounded roll and 50% fall damage on eligible nonlethal
impacts. Failed heavy cliff-dive checks ragdoll and automatically get up if alive.
Side/back rolls also retain their edge-departure horizontal speed until contact;
their separate ground braking clock no longer stops them while falling.
Ordinary low dives retain their normal finish; lethal heights never receive the
discount. See [current behavior and footage](docs/CLIFF_DIVE_LANDING.md).
Do not start crouching or
another movement mechanic without a new user decision.

Confirmed controls and behavior: Space jumps / Alt dodges for fresh defaults;
existing bindings are preserved (older Space dodge normally gets Jump on Alt).
Immediate fixed 1.2 m jump, 15 stamina, 0.10 s edge grace, 0.12 s input buffer,
retained momentum and very little air steering. Jump owns only a short takeoff;
compatible attacks/spells remain usable in the air. Landing uses impact speed,
with 3/6/15 m equivalent-height thresholds and no dodge immunity against falls.

Accepted hits while descending trigger physical ragdoll; rising hits do not.
Lethal landing damage also ragdolls. A surviving character settles, checks standing
clearance, then plays a brief get-up. Bone dimensions, masses and joint limits are
Resource data; ten physical bodies are created per rig and activated on demand.
Approved option B now uses a **1.20 s supported get-up**: face-down hand plant,
knee-under and rise, or face-up side turn before the kneel. Pose selection follows
the settled torso. Original Resource-authored poses retain planted contacts;
reaction owns recovery and only the motor moves the collision body. See
[recovery structure, tuning and native clips](docs/GET_UP_RECOVERY.md).

Open the lab Esc menu, select a drop height and choose **Start fall test** or
**Drop + hit**, then walk forward off the platform. F3 shows impact diagnostics.
Lethal lab falls show the ragdoll for 2.5 s before reset. Manual resets cancel the
delayed recovery. See [Movement 02](docs/MOVEMENT_02_JUMP_FALL_LAND.md) and
[ragdoll ownership](docs/decisions/007-ragdoll-handover.md).

Milestone 1 and the existing running/dodge consolidation remain in place.
The forward dive retains its adaptive clearance and the old hop remains removed.
The requested **0.60 m platform → 0.5/0.6 m gap → 1.00 m platform** crossings pass
at 30/60/120 Hz, including near-edge starts. Detection looks across empty gaps and
uses relative elevation. The earlier dodge baseline passed **1,347 checks / 22 suites**; the latest full
report is [motion-contract-final.json](docs/validation/motion-contract-final.json).
See [implementation, tuning and native footage](docs/DIVE_CLEARANCE_PLAN.md).

Two measured lanes are in **02 Jumping**. Open `scenes/dive_clearance_preview.tscn`
and press F6 for actual-character replay/pause/slow motion. The implementation is
ready for the user's feel review; other new mechanics retain their review gates.

The ownership follow-up closes definition/timing, mode-transition, queued-cost,
presentation/input and health-signal gaps. The Warden now uses the shared action
lifecycle; explicit world-space spell aim supports a caster without a player camera.
All original encounter patterns remain in place. Forward-dive tuning is preserved.

The first movement consolidation fixes scripted input scaling dodge reach: the
motor now normalizes horizontal ground/dodge direction for every controller.
Test Grounds → Esc → Movement practice offers running/gap route shortcuts,
a stationary target and a timed overhead (10 damage). Authored practice settings
are separate from the courtyard boss. Leaving the hub removes practice combat;
an active traversal dodge continues. Death/station reset restores the attempt;
entire-lab reset returns to combat-free defaults. Expanded F3 diagnostics observe
real movement/action/phase/cost outcomes without running separate physics.

The user then selected the existing side/back animation references with **0.70 s**
playback and no physical hop. These rolls now start on the ground in both worlds,
retain 4.34 m reach, 25 stamina and the 0.06–0.32 s immunity window. Grounded
step-up uses the motor; edge departure falls normally. Forward dive and its
adaptive clearance are unchanged. See [ground-roll review](docs/GROUND_ROLLS.md).

## Game direction

A single-player fantasy Souls-like adventure RPG with PS1 presentation, inspired
by Elden Ring and Zelda: Tears of the Kingdom. The eventual world is fully
seamless, finite and procedural, including dungeons, with a reproducible seed per
save, guaranteed essential landmarks and rule-based optional handcrafted structures.

Freeform equipment/builds affect handling and costs without removing basic movement.
Stamina supports physical exertion; spells and permanently unlocked powered flight
share mana. Flight mana exhaustion causes ordinary falling. Combat compatibility is
declared per ability/movement mode. Plan both surface and underwater swimming,
physical structural collapse with prebuilt pieces, checkpoint respawning, recoverable
progression currency and validated safe save-load positions.

These are **accepted future requirements**, not currently playable features.
Quests, encounters, broader progression and content production come after the
movement, collapse, streaming and persistence pilots. The roadmap is authoritative
for sequence and test gates.

## Run the project

| Item | Value |
| --- | --- |
| Repository | `<PROJECT_ROOT>` |
| Desktop link | `<USER_HOME>/Desktop/Ashen Courtyard/Project` |
| Engine | `<USER_HOME>/Desktop/Ashen Courtyard/Godot_v4.6.2-stable_linux.x86_64` |
| Exact engine | **4.6.2.stable.official.71f334935** |
| Language/renderer | Typed GDScript / Compatibility (`gl_compatibility`) |
| F5 / Run Project | `scenes/arena.tscn` |
| F6 / Run Current Scene | Open `scenes/movement_lab.tscn` or `scenes/dodge_preview.tscn` |
| Canonical character | `features/character/player.tscn` |
| Reference hardware | i5-1135G7, Iris Xe, 8 GB RAM, Linux |

Desktop **Open Editor** and **Play Game** launchers remain available. Restart an
already running game after edits. Courtyard Esc menu links to Character Test
Grounds; laboratory Esc menu returns to a fresh courtyard. Most environment
geometry is built at runtime, so editor views are sparse. On a fresh checkout,
let Godot finish importing assets before running tests.

## What works

- Courtyard sword combat: light combo, heavy, two spells, healing, boss patterns,
  telegraphs, vulnerable commitment/recovery, death/victory and retries.
- Camera-relative walk/sprint, momentum, speed-based lean, slope adaptation and
  planted-foot corrections. S-turns receive 15% more lean; diagonal/S-turn steering
  preserves speed. Full 180° reversals brake; released movement slows to a stop.
- Capsule-checked walking/sprinting step-up to **0.60 m**, including ramp sides.
- Shoulder camera: side, FOV, distance, offset, height, sensitivity, smoothing and
  inversion settings; collision at walls/corners; target lock independent of body
  facing. Camera settings persist in `user://camera_settings.cfg`.
- Shared keybinding menus with validation, cancellation/default restoration and
  `user://keybindings.cfg`. Default movement WASD, sprint Shift, jump Space, dodge Alt, light/
  heavy mouse buttons, lock Q, spell select 1/2, cast E, heal R, pause Esc, PS1 F4.
- Separate 140 × 120 m graybox lab with eight stations, hub, navigation/reset menu,
  camera/keybinding menus and F3 diagnostics. Fixtures
  for unfinished abilities are marked inactive. Falling outside the test fixtures resets
  to safe station entrances; station 05 now has working water.
- PS1 effects toggle survives scene retries during the session. Asset credits and
  licenses remain under `CREDITS.md` and `assets/third_party/`.

## One shared directional dodge

The old physical hop and comparison toggle have been removed at the user's
request. All levels and animation previews use the same character and definition
selection. Forward input or no input selects the adaptive dive. Side/back input
selects the grounded reference roll, relative to the knight's facing at start.

Forward: 0.10 s preparation, 0.05 s extension, 0.25 m open-ground rise, 11 m/s
flight until contact, 5.5 m ordinary flat-ground travel and a 0.55 s grounded finish. Side/back: no physical
hop, 0.70 s grounded playback and 4.34 m requested travel. Both cost 25 stamina.
Forward immunity is 0.06–0.32 s from takeoff; side/back immunity is measured from
action start. An ordinary landing does not renew it. A successful paid timed
landing roll is a new action with its own ordinary roll immunity; that immunity
never substitutes for the separate impact-damage calculation.

The preparation keeps both knees forward and anchors the feet. At a ledge its
small forward movement is withheld if it would leave support before takeoff.
Adaptive launch selection occurs once at takeoff: 2.6 m lookahead, maximum 0.6 m
relative rise and 0.12 m clearance margin, subject to capsule/headroom checks.
The example's 0.4 m rise selects approximately 0.52 m launch height; a 0.6 m
obstacle selects approximately 0.72 m. Collision can shorten horizontal travel.
The native 0.6 m gap capture travels 5.2413 m, lands at 0.4167 s and finishes at
0.9667 s. Actual contact still starts the roll. No second boost or immunity reset.
The original directional reference clips remain the side/back animation sources.

The preview now instantiates the **actual player**. It has no separate movement
integrator. R replays, Space pauses, Right steps one physics tick, and the menu
selects normal/quarter-speed playback. See [DODGE_PREVIEW.md](DODGE_PREVIEW.md)
for current native footage and exact measurements; older timing claims are superseded.

## Architecture that now exists

- Motor exclusively moves the character's collision body. Animation follows state.
- Resources own instance health/stamina/mana/flasks and atomic combined spending.
- Shared `ActionLifecycle` owns one committed action, clock, input buffer, interruption,
  result ticket and strike token. Player/Warden executors use captured definitions
  for timing and payload; definitions specify mode-exit and damage interruption rules.
- Grounded/airborne movement modes are independent of action state. Other modes are
  not implemented yet.
- Keyboard, scripted and Warden controllers use the same intent/action interface.
  Requests queue until the physics tick pays ongoing costs, then validates and spends
  action costs atomically. Read `ActionResult.resolved`/`completed` before `accepted`;
  legacy `begin()` now means queued, not immediately started.
- Targeting, locomotion facing and camera feedback are separate responsibilities.
- Injected world combat services receive explicit world-space aim. The player adapter
  supplies selected-enemy/reticle aim; AI needs no camera. Bursts query receivers and walls.
- Animation consumes resolved sprint state. Presentation owns the dive pose sampler
  and blends; the ability owns physical phases and launch decisions.
- Damage, healing and reset notify through resource health signals and their character facade.
- Strike tokens deduplicate per action/projectile. Legacy string history is bounded
  to 128 entries and eight seconds of simulation time.
- Session owns player creation, active-world references, pause and scene lifecycle.
- Focused movement, resources, ability, combat and presentation Resources replace
  the old combined tuning fields. `CombatTuning` is a read-only compatibility facade.
- Reset, interruption, death and unload release active action/pose ownership.
- `PersistentEntityState` is a serialization contract, not an implemented save system.

Historical script paths remain thin adapters where implementations moved into
`features/`. Existing boss decision logic, environment construction and UI are
retained. The Warden's composition wires a separate decision controller, shared
action lifecycle and presentation owner, plus motor/resources/damage dependencies.
No general quest or ECS framework was added. The subsequent
[item foundation](docs/ITEM_SYSTEM.md) adds focused inventory and loadout owners.

## Validation and evidence

`python3 tools/run_tests.py` runs all suites with isolated temporary settings,
checks both exit status and engine errors, and writes JSON/raw logs under
`.artifacts/tests/`. Use `--suite run_camera` to select a suite and `--godot` or
`GODOT_BIN` for another engine path. `--self-test` checks the runner's error handling.

**1,973 checks across 31 suites pass.** The latest report is
`docs/validation/get-up-final.json`. Supported recovery adds 92 checks and
preserves the 1,881-check motion baseline in `motion-contract-final.json`. The motion refactor adds 48 independent
character contract checks and 21 production Warden checks. Its preserved baseline
was 1,812 / 28 suites in `motion-contract-baseline.json`. Prior jump/ragdoll coverage
includes 118 jump checks, 35 integration checks, 50 ragdoll checks and saved-binding
migration; cliff/landing and directional-roll suites are also included.
The existing combat/camera/running/step/dodge/gap/ownership suites remain passing.
The preserved pre-jump baseline was 1,347 checks / 22 suites in
`docs/validation/unified-dodge-final.json`. Legacy-hop-only suites remain retired.

Native courtyard/lab/preview screenshots and dodge footage were captured on the
actual Iris Xe through Compatibility and visually inspected. This verifies rendering,
not a sustained release-frame-budget claim. Release export templates are absent;
a real release benchmark remains required before world/destruction scale increases.
Target 60 FPS, ~720p internal 3D with readable UI; see roadmap measurement requirements.

## Source assets and limits

The player uses Quaternius's UAL mannequin; the Warden retains Luana Coppio's
Fullplate Armor Knight, repaired to include both mesh halves, with original
crown/cape/sword accents. Locomotion and light sword attacks use source-native UAL
clips; jump, dodge, heavy/cast/heal and other remaining actions use temporary
adapters. Sources are recorded in `CREDITS.md`. PSX dungeon art comes from the
credited asset pack. No Elden Ring game assets were extracted.

Still unimplemented: crawling/sliding, full free climbing,
pushing/carrying/throwing, flight, adventure item progression,
world generation/streaming, gameplay saves/checkpoints, structural collapse and quests.
No multiplayer or controller support. Graybox fixtures do not enable these abilities.

## Git and working preferences

Branch `main`; latest existing commit `7117fa2` (test-ground menu, saved keybindings
and dynamic running animation). There is substantial uncommitted work from previous
movement/dodge iterations and this milestone. It has been preserved; no commit,
push, reset or branch change was performed for the architecture task.

Pre-refactor source/config/docs, Git status/diff and a SHA256 manifest were copied
to `/tmp/ashen-architecture-baseline-20260920/`. Baseline/final test reports are also
saved in `docs/validation/`. Do not discard existing changes. The adjacent Python
Snake project is unchanged.

Explain decisions plainly: the user is a Computer Science student. Before each new
mechanic, agree on controls, animation references and acceptance criteria, implement
one at a time, show results and complete a review before continuing.

## UAL player and appearance review

The normal player uses `scenes/models/ual_player.tscn`, an inherited UAL mannequin
with the sword-only player loadout. The separate Test Grounds review scene
demonstrates removable chest armor, configurable sword/shield/bow-marker layouts
and automatic stowing. UAL and legacy models use sibling adapters; editable
profiles distinguish six native locomotion clips and UAL2 A/B light attacks from
temporary action poses. Final character art still requires Neth's consultation
and visual review. This does not advance crawling, sliding, stealth, inventory
or bow/shield combat. Current implementation and artist
requirements: [UAL foundation](docs/UAL_FOUNDATION.md) and
[Blender workflow](docs/BLENDER_CHARACTER_WORKFLOW.md).


### Locomotion review — 25 September 2026

Jog/sprint retain UAL `Jog_Fwd` / `Sprint`, with baked source contact curves and
measured stance-speed metadata. Presentation scales cadence by actual movement,
releases swing-foot anchors, preserves ankle orientation through leg IK, and
uses sole-relative clearance. Native UAL gait bakes retain vertical bounce;
redundant per-frame gait smoothing was removed (transition blending remains).
Dive preparation applies supported foot constraints after whole-body clearance.
Motor speeds, costs, action timing and default model selection are unchanged.
See `docs/validation/LOCOMOTION_REVIEW.md` for checks and remaining limitations.

## Item foundation — 26 September 2026

The existing sword, Azure Bolt, Violet Burst and flask now resolve through the
shared item catalog, per-character inventory and hand/spell/gadget loadout.
Items compose reusable movesets, presentation, hand requirements and authored
upgrade profiles. Accepted actions capture effective values and pay character
resources plus quantity/charges atomically. Player flask compatibility access
has one backing store in inventory. Retry/station reset rebuilds the starter
loadout. A Test Grounds item panel grants test content and edits idle loadouts.

Bow/shield equipment fixtures demonstrate two-handed stowing, but their combat
is deferred. Versioned records support validated round trips without disk saves.
The appearance-review scene retains its independent visual loadouts. See
[implementation, authoring and playtest steps](docs/ITEM_SYSTEM.md).

## Swimming update

Surface swimming, camera-directed underwater movement, breath/drowning and automatic
water ledge exits are implemented in the shared player. Use **Test Grounds →
Swimming (05)**. C dives, Space ascends and Shift swims faster; controls follow
existing rebindings. Native UAL1 swim loops and the existing UAL2 mantle drive the
visuals. The old water-entry reset was removed. See [Swimming](docs/SWIMMING.md)
for tuning, architecture, tests and the hands-on review route.

## Fitted hitboxes and head-based breath

The approved sensing pass adds 17 animated regions to the UAL and legacy player,
precise projectile/melee/area confirmation, and a mouth/nose water detector. Motor
collision remains separate. Use **Esc → Debug → Fitted hitboxes / breath** and
see [HITBOXES.md](docs/HITBOXES.md) for ownership, editable profiles and checks.
