# Opening six-week publicity slate

This slate supplies three biweekly, design-first YouTube devlogs. Each episode
also produces three standalone 9:16 cutdowns for Instagram Reels and YouTube
Shorts. “Week 1” begins when the first devlog is ready; no fixed calendar hour is
assumed before audience analytics exist.

Public identity rule: introduce and credit the creator as **Neth** only. Do not
show a real name, local username/path, personal account, email, location,
notification or identifying file metadata in any capture or export.

## Publishing rhythm

| Week | Anchor | Supporting posts |
| --- | --- | --- |
| 1 | Episode 1 devlog and result-led short | — |
| 2 | — | Failure-to-fix short; Test Grounds/design takeaway short |
| 3 | Episode 2 devlog and result-led short | — |
| 4 | — | Before/after dodge short; adaptive-clearance/design short |
| 5 | Episode 3 devlog and result-led short | — |
| 6 | — | Ragdoll recovery short; timed-landing decision short; slate review |

## Episode 1 — Why I Built a Movement Lab Before Building the World

**Status:** ready for script and clean recapture  
**Format:** English voice-over, design-first  
**Viewer promise:** see how a deliberately plain Test Grounds makes an ambitious
movement system easier to design, test and explain.  
**Public truth:** the 140 × 120 m Test Grounds and its nine zones exist. Running,
jumping, crouching, ledges and swimming have active review fixtures; other
stations visibly remain placeholders.

### Packaging

Primary title: **Why I Built a Movement Lab Before Building the World**

Alternatives:

- **I Stopped Building Levels and Built a Movement Lab Instead**
- **The Test Level Behind My Soulslike Movement**

Thumbnail: split the atmospheric courtyard against the clean overhead Test
Grounds. Put the player at the boundary between them. Use at most the short text
**BUILD THIS FIRST?**; the contrast should carry the idea without the words.

Opening hook:

> This is the world I want players to explore—but this gray room is where I
> decide whether moving through it is actually fun.

Show the courtyard, cut immediately to a successful movement sequence in the lab,
then reveal the full facility. Avoid a logo animation before the payoff.

### Story outline

1. **Promise:** introduce Neth and Ashen Courtyard through ten seconds of current
   gameplay, not biography.
2. **Problem:** tuning movement inside a combat level makes distance, slopes,
   camera, obstacles and enemies change at the same time.
3. **Decision:** isolate one movement question per station while keeping the real
   production character, camera and action systems.
4. **Tour:** show the hub and all eight numbered stations quickly. Clearly mark
   inactive mechanics as future test space.
5. **Example:** use the measured running lane, raised-gap dive and fall-test rig
   to show how a question becomes a repeatable fixture.
6. **Reliability:** explain 30/60/120 Hz checks in plain language: the same input
   should not produce a different game because the frame rate changed.
7. **Payoff:** return to the courtyard and show why consistent movement frees the
   level to become atmospheric again.

Optional technical layer: briefly show that the courtyard, Test Grounds and
preview scenes use the same player scene. Do not turn the episode into a scene
tree tour.

### Footage and evidence

| Beat | Existing source | Use or recapture |
| --- | --- | --- |
| Atmospheric promise | [Courtyard still](../psx-courtyard.png) | Recapture 5–8 seconds of clean production gameplay; still is a fallback |
| Facility reveal | [Overview](../movement-lab-overview.png) | Use as an annotated still; recapture a slow overhead orbit for motion |
| Navigation | [Lab menu](../movement-lab-menu.png) | Use briefly if current text remains legible |
| Station tour | [Station 01](../movement-lab-station-01.png), [02](../movement-lab-station-02.png), [03](../movement-lab-station-03.png), [04](../movement-lab-station-04.png), [05](../movement-lab-station-05.png), [06](../movement-lab-station-06.png), [07](../movement-lab-station-07.png), [08](../movement-lab-station-08.png) | Build a fast labeled montage; label placeholder stations explicitly |
| Real test example | [Raised-gap normal speed](../dive-clearance/raised-gap-normal.gif) | Use or recapture for a cleaner 16:9/9:16 master |
| Diagnostic example | [Dive diagnostics](../movement-01/dive-diagnostics.png) | Crop only if labels stay readable; otherwise recapture F3 |
| Design source | [Character Test Grounds](../../MOVEMENT_LAB.md) | Fact checking and description link |

### Curated failure and payoff

Failure: demonstrate why testing in an art-heavy encounter makes it difficult to
separate a movement problem from a camera, collision or enemy problem. Use a
short staged comparison or voice-over over the courtyard; do not invent an old
bug if no truthful capture exists.

Payoff: show the same production character moving from a measured lab fixture to
the courtyard. The lesson is isolation of variables, not that grayboxes are more
important than final levels.

### Community question

**When you judge a movement mechanic, what reveals bad game feel fastest: a flat
measured course, an obstacle course, or a real combat encounter?**

### Short-form cutdowns

1. **I Built Eight Test Stations Before Building the World**
   - First frame: overhead lab reveal with large “8 MOVEMENT TESTS”.
   - Show the hub and one second per station; mark inactive stations as planned.
   - Payoff: “One question per room. The real character in every test.”
2. **Why Grayboxes Make Movement Better**
   - Start on a failed or ambiguous courtyard attempt.
   - Cut to a measured lane and diagnostic view.
   - Lesson: change one variable at a time, then return to the real level.
3. **Would Your Dodge Change at 30 FPS?**
   - Show the same raised-gap test labeled 30/60/120 Hz.
   - Explain that physics consistency protects game feel across machines.
   - Do not claim visual performance parity; this is behavior validation.

### Rights and safety

- Credits source: [CREDITS.md](../../CREDITS.md).
- Likely visible third-party work: Fullplate Armor Knight, Universal Animation
  Library/UAL2, PSX Dungeon environment and PSX Visuals adaptation.
- The PSX Dungeon attribution must appear in the description when courtyard
  footage is used.
- Do not show the unresolved PSX Sword / Espada PS1 asset.
- Use original narration, original/licensed music and current production footage.
- Keep private desktop notifications, real names, user paths and editor tabs out
  of frame. Credit the creator as Neth only.

### Dry-run completion

| Gate | Result |
| --- | --- |
| Brief | Viewer promise, truth boundary, hook, outline and community question are complete above |
| Footage | Existing sources are linked; clean courtyard and overhead lab motion are marked for recapture |
| Cutdowns | Three standalone hooks, lessons and payoffs are defined |
| Rights | Visible asset families and required PSX Dungeon attribution are identified; unresolved sword is banned |
| Publishing | Checklist dry run is intentionally blocked until the clean courtyard/lab footage, voice-over, captions and final licenses exist |

Success hypothesis: viewers who respond to the one-mechanic-at-a-time method
should continue into the dodge and falling episodes. Measure first-30-second
retention, meaningful answers to the question and clicks into Episode 2.

## Episode 2 — The Dodge Felt Wrong—So I Rebuilt It

**Status:** ready for script; validate whether historical hop footage is clear
enough before using it  
**Viewer promise:** see why removing an upward hop, keeping a forward dive and
separating motion from animation made each dodge direction easier to read.  
**Public truth:** standing/forward input selects the adaptive forward dive;
side/back input selects a 0.70-second grounded roll. The old hop and comparison
switch are removed.

### Packaging

Primary title: **The Dodge Felt Wrong—So I Rebuilt It**

Alternatives:

- **One Dodge Was Trying to Do Too Much**
- **How I Made Every Dodge Direction Read Differently**

Thumbnail: side-by-side silhouettes at takeoff—old upward hop on the left,
grounded roll or forward dive on the right. Use **HOP vs ROLL** only if the poses
remain legible at thumbnail size.

Opening hook:

> My dodge could avoid an attack, but it did not tell the player what kind of
> movement they had asked for.

Open with a rapid old/new comparison, then show the final four directions.

### Story outline

1. Show the readable final rule: forward dives; side and back stay grounded.
2. Explain the problem with adding the same physical hop to animation clips that
   already contained their own motion.
3. Show the selected 0.70-second left/right/back rolls and why their heading locks
   at acceptance.
4. Explain the forward dive as a separate traversal choice with a shallow arc.
5. Demonstrate adaptive clearance on the 0.60 m-to-1.00 m raised-gap fixture.
6. Explain the ownership rule in player language: actions ask for motion, the
   character motor owns collision, and animation never drags the body.
7. Finish with courtyard dodge practice and the four-direction payoff.

### Footage and evidence

| Beat | Existing source | Use or recapture |
| --- | --- | --- |
| Historical comparison | [Removed hop documentation](../../DODGE_HOP.md), [dodge pose sheet](../dodge-preview-poses.png) | Use only if the exact old behavior is labeled historical; otherwise explain with stills |
| Final ground rolls | [Ground-roll footage](../ground-rolls/ground-rolls.gif) | This behavior capture uses the earlier knight appearance; label it as development history or recapture the payoff with the current UAL mannequin |
| Edge behavior | [Falling rolls](../ground-rolls/falling-rolls.gif) | Use for momentum explanation, not the main hook |
| Adaptive dive | [Raised-gap normal](../dive-clearance/raised-gap-normal.gif), [slow](../dive-clearance/raised-gap-slow.gif) | Use both normal speed and a short slow-motion annotation |
| Current rules | [Ground rolls](../GROUND_ROLLS.md), [clearance plan](../DIVE_CLEARANCE_PLAN.md) | Fact checking and description links |

### Curated failure and payoff

Failure: the removed collision-body hop duplicated motion that already existed in
the side/back clips, weakening contact with the floor. Keep the old footage short
and label it clearly as an earlier version.

Payoff: four directions have distinct jobs while sharing stamina, interruption
and collision rules. The result should be shown at normal speed before slow
motion or debug overlays.

### Community question

**Should a dodge preserve its horizontal momentum after it leaves a ledge, or
stop when its original grounded travel distance runs out?**

### Short-form cutdowns

1. **This Tiny Hop Made My Dodge Feel Wrong** — old/new side-roll comparison,
   explain duplicated lift, finish on the grounded result.
2. **My Forward Dodge Reads the Obstacle** — show the flat shallow dive, then the
   raised-gap launch; explain that the action chooses the arc but collision stays
   with the motor.
3. **Animation Does Not Move This Character** — compare pose motion with capsule
   travel in a diagnostic view; end on why one body mover prevents disagreement.

### Rights and safety

- Credits source: [CREDITS.md](../../CREDITS.md).
- Likely visible work: Fullplate Armor Knight, Universal Animation Library roll
  source, PSX Dungeon and PSX Visuals adaptation.
- Describe directional roll variants as local derivatives, not separate source
  clips supplied by Quaternius.
- Existing knight footage must be labeled as an earlier player appearance when it
  is not replaced by a current UAL mannequin capture.
- Do not show the unresolved PSX Sword / Espada PS1 asset.

Success hypothesis: a strong before/after should increase short-form completion
and prompt design discussion. Compare retention around the brief architecture
explanation against the surrounding gameplay.

## Episode 3 — Making Falls Feel Dangerous Without Taking Control Away

**Status:** ready for script and current footage assembly  
**Viewer promise:** see how landing severity, physical ragdoll, supported recovery
and a last-second skill check turn falling into a readable consequence.  
**Public truth:** landing classification uses impact speed with 3/6/15 m
equivalent-height thresholds. Descending hits and lethal landings can ragdoll.
Survivors settle and use the approved 1.20-second supported get-up. A fresh Dodge
press in the last 0.15 seconds before eligible contact can spend 25 stamina for a
0.40-second roll and 50% fall-damage reduction.

### Packaging

Primary title: **Making Falls Feel Dangerous Without Taking Control Away**

Alternatives:

- **I Turned Falling Into a Combat Decision**
- **From Hard Landing to Physical Recovery**

Thumbnail: one diagonal composition with the falling character above and the
hand-supported recovery below. Use **LAND IT OR RAGDOLL** only if it does not hide
the body language.

Opening hook:

> A fall should feel dangerous before the health bar tells you it was dangerous.

Open with successful timed landing and missed-timing ragdoll back-to-back. Then
explain that both outcomes come from the same impact.

### Story outline

1. Show soft, heavy, damaging and lethal outcomes as a fast visual scale.
2. Explain why impact speed—not platform labels—classifies the landing.
3. Show a descending hit handing control to the physical ragdoll.
4. Explain settlement and clearance before the capsule is safely restored.
5. Show the face-down and face-up supported get-up paths.
6. Introduce the 0.15-second fresh-input choice and its stamina/damage tradeoff.
7. Compare successful timing, missed timing and lethal height without overstating
   literal drop-height boundaries.
8. Finish on the character returning to control in the real Test Grounds.

### Footage and evidence

| Beat | Existing source | Use or recapture |
| --- | --- | --- |
| Basic jump | [Jump](../jump-02/jump.gif) | Brief setup only |
| Severity | [Heavy landing](../jump-02/heavy_landing.gif), [lethal landing](../jump-02/lethal_landing.gif) | Label outcomes; avoid presenting GIF timing as performance data |
| Descending hit | [Hit recovery](../jump-02/hit_recovery.gif) | Use to connect combat and reaction systems |
| Supported recovery | [Face-down](../get-up/face_down.gif), [face-up](../get-up/face_up.gif), [physical fall](../get-up/fall-recovery.gif) | Distinguish staged pose previews from the real cliff fall |
| Timing success | [Full trajectory](../cliff-landing/timed-landing.gif), [close view](../cliff-landing/timed-landing-close.gif) | Main behavior payoff; label the earlier knight appearance or recapture with the current UAL mannequin |
| Timing failure | [Missed landing](../cliff-landing/failed-landing.gif) | Pair directly with success; apply the same appearance note |
| Current rules | [Movement 02](../MOVEMENT_02_JUMP_FALL_LAND.md), [get-up](../GET_UP_RECOVERY.md), [cliff landing](../CLIFF_DIVE_LANDING.md) | Fact checking and description links |

### Curated failure and payoff

Failure: use the missed timed landing, which applies full damage and enters a
physical recovery. This is an intentional gameplay failure, not a broken build.
If discussing the corrected upright frame during action replacement, show it only
when the historical capture is available and clearly labeled.

Payoff: the same impact can produce a skilled roll or a vulnerable physical
recovery, while lethal heights remain lethal and ordinary falls keep their
existing heavy landing.

### Community question

**Does a last-second landing input make a dangerous fall feel more skillful, or
does it make the consequence harder to read?**

### Short-form cutdowns

1. **Four Ways My Game Handles a Landing** — soft, heavy, damaging and lethal
   comparison with minimal numbers.
2. **The Character Gets Up From the Pose Physics Gave It** — ragdoll, settle,
   face selection, planted-hand recovery and return to control.
3. **A 0.15-Second Choice Before Impact** — success/failure split, 25 stamina and
   half damage versus ragdoll; state that lethal heights never receive the discount.

### Rights and safety

- Credits source: [CREDITS.md](../../CREDITS.md).
- Likely visible work: Fullplate Armor Knight, Quaternius-derived jump/landing or
  UAL motion where applicable, PSX Dungeon and PSX Visuals adaptation.
- The authored get-up poses are local Godot Resources; do not imply that a
  downloaded get-up animation produced them.
- Existing knight footage must be labeled as an earlier player appearance when it
  is not replaced by a current UAL mannequin capture.
- Do not show the unresolved PSX Sword / Espada PS1 asset.

Success hypothesis: the branching outcome should improve rewatches and meaningful
comments. Watch for retention loss during the impact-speed explanation; shorten
the formula segment if viewers understand the visual scale without it.
