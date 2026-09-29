# Publicity topic backlog

This backlog converts approved project work into player-facing stories. It is not
a gameplay roadmap. Re-rank it after each 28-day review or when a mechanic crosses
an implementation/review boundary.

## Scoring

Score each idea from 1–5:

- **Visual payoff:** can a new viewer understand the change from footage?
- **Teaching value:** does the decision reveal a reusable design lesson?
- **Readiness:** is the current truth stable and supported by approved captures?
- **Rights risk:** 1 is low and 5 is high; subtract this from the other scores.

`priority = visual payoff + teaching value + readiness - rights risk`

Rights risk is a gate, not merely a number. A topic with unresolved usage rights
does not publish regardless of its score.

## Opening slate

| Rank | Topic | Visual | Teaching | Ready | Risk | Score | Public truth |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | Why build the Movement Lab first? | 5 | 5 | 5 | 1 | 14 | Implemented Test Grounds with active and placeholder stations clearly labeled |
| 2 | Rebuilding the dodge | 5 | 5 | 5 | 1 | 14 | Shared forward dive and grounded side/back rolls are implemented |
| 3 | Falling, ragdoll and recovery | 5 | 5 | 5 | 1 | 14 | Jump, landing severity, ragdoll, supported get-up and timed cliff roll are implemented for review |

These are fully developed in [the opening slate](OPENING_SLATE.md).

## Ranked follow-up topics

| Rank | Topic | Visual | Teaching | Ready | Risk | Score | Hook and truth boundary | Evidence |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 4 | Ledge grabbing and automatic corners | 5 | 5 | 5 | 1 | 14 | “A ledge system is really several safety checks.” Grab, hang, pull-up and sideways corners are implemented for review; free climbing is not. | [Ledge grab](../LEDGE_GRAB_PLAN.md), [corner shimmy](../LEDGE_SHIMMY.md) |
| 5 | Surface and underwater swimming | 5 | 4 | 5 | 1 | 13 | “Water changes movement, resources and exits at once.” Swimming, breath and ledge exits are implemented for review. | [Swimming](../SWIMMING.md) |
| 6 | The Soulbound HUD and evolving mana vessel | 5 | 4 | 5 | 1 | 13 | “How can a resource meter become part of the character?” Clearly label it as a browser visual prototype, not the in-game HUD. | [Progress](../../art_source/ui/soulbound_hud/docs/DEVELOPMENT_PROGRESS.md), [mana evolution](../../art_source/ui/soulbound_hud/docs/MANA_EVOLUTION.md) |
| 7 | Six stages of fractured-stone recovery | 5 | 4 | 4 | 1 | 12 | “Permanent growth should change the body without changing its silhouette.” The six images are approved concepts; thresholds and integration remain deferred. | [Life progression](../../art_source/characters/ual/awakening_concepts/life_progression/README.md) |
| 8 | Replacing temporary attacks with native UAL2 sword motion | 4 | 4 | 5 | 1 | 12 | “Keep combat timing while replacing the animation underneath it.” A/B light attacks are integrated; final character artwork is not. | [Sword attacks](../UAL_SWORD_ATTACKS.md), [animation system](../ANIMATION_SYSTEM.md) |
| 9 | Crouching without breaking the character capsule | 4 | 4 | 4 | 1 | 11 | “Standing up is a clearance problem, not just an animation.” Crouching is implemented for review; crawling remains deferred. | [Crouching](../MOVEMENT_03_CROUCH.md) |
| 10 | One action lifecycle for player and boss | 3 | 5 | 4 | 1 | 11 | “Queued does not mean accepted.” Lead with visible combat/resource outcomes, then explain atomic costs and cancellation. | [Architecture](../../ARCHITECTURE.md), [Section 2 review](../SECTION2_REVIEW.md) |
| 11 | Building an item foundation before adding loot | 3 | 4 | 5 | 1 | 11 | “Inventory is identity, state and cost—not a list of icons.” The shared catalog/loadout/upgrades are implemented; loot economy and save progression are not. | [Item system](../ITEM_SYSTEM.md) |
| 12 | Testing movement at 30, 60 and 120 Hz | 3 | 5 | 5 | 1 | 12 | “The same dodge should not travel differently with frame rate.” Best as a technical companion to a visual mechanic, not the first introduction. | [Development](../DEVELOPMENT.md), [Movement 02](../MOVEMENT_02_JUMP_FALL_LAND.md) |

## Future-only topics

The following may become good episodes, but they are not current gameplay:

- Slide.
- Full free wall climbing.
- Pushing, carrying and throwing.
- Powered flight and mana exhaustion.
- Structural collapse.
- Procedural seamless world generation, streaming and saves.
- Quest lines, broader progression and the loot economy.

Keep these as design discussions only when explicitly useful. Do not use footage
from placeholder fixtures to imply that the mechanics are implemented.

## Parking lot

Record ideas here without promoting them into the ranked backlog until their
truth and rights boundaries are known.

| Idea | Audience question | Missing evidence or decision |
| --- | --- | --- |
|  |  |  |

