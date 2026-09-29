# Ashen Courtyard publicity system

This folder turns approved development work into a sustainable public record.
The public identity is **Neth building Ashen Courtyard**: a developer-led,
English-language channel about making a Retro Lowpoly Dark Fantasy action RPG.
Neth is the only creator name used in public-facing material. The creator's real
name and personal information remain private.

The primary audience is players who enjoy seeing game feel evolve and developers
who want to understand the design reasoning. The goal is community, not maximum
upload volume. Publish one design-first YouTube devlog every two weeks, then adapt
its strongest ideas into two or three Instagram Reels and YouTube Shorts.

## Start here

1. Pick a ready topic from [the backlog](TOPIC_BACKLOG.md).
2. Copy [the devlog brief](templates/DEVLOG_BRIEF.md) and complete its truth,
   footage and rights sections before scripting.
3. Copy [the short-form brief](templates/SHORT_FORM_BRIEF.md) for each cutdown.
4. Run [the publishing checklist](templates/PUBLISHING_CHECKLIST.md) before upload.
5. Record 7-day and 28-day results in
   [the review template](templates/POST_PUBLICATION_REVIEW.md).

The [opening slate](OPENING_SLATE.md) contains the first three cycles and a full
dry run for the movement-lab episode.

## Editorial promise

Every post should answer one player-facing question:

> What felt wrong, what design choice changed it, and how does the game feel now?

Use this story order:

1. **Result:** show the most legible final gameplay moment immediately.
2. **Problem:** explain the visible player experience, not an internal class name.
3. **Attempt:** show one curated failure or earlier version when it teaches
   something useful.
4. **Decision:** explain the rule or tradeoff that guided the fix.
5. **Payoff:** compare the result under real gameplay conditions.
6. **Question:** invite discussion about one specific design tradeoff.

Implementation details support the story. Introduce a Godot or architecture term
only after the viewer understands why it matters.

## Content pillars

| Pillar | Audience value | Typical evidence |
| --- | --- | --- |
| Game feel | See a mechanic become clearer, fairer or more expressive | Before/after gameplay, slow motion, controller input |
| Design decisions | Understand the rule behind a visible result | Alternatives, constraints, playtest criteria |
| Honest iteration | Learn from a bounded failure without watching raw debugging | Failed attempt followed by the approved fix |
| Art and animation | See the visual identity and character language evolve | Concept comparisons, pose sheets, final in-game motion |
| Reliable systems | Learn why a result remains consistent | Test Grounds, diagnostics, 30/60/120 Hz evidence |

The first three pillars should appear in most devlogs. Art, animation and
technical validation rotate in when they strengthen the player-facing story.

## Two-week operating cycle

The cycle is relative to the chosen long-form publication day. Do not guess a
universal best hour; use channel analytics once enough audience data exists.

| Day | Work |
| --- | --- |
| -7 to -5 | Lock the brief, public truth boundary, community question and rights inventory |
| -5 to -3 | Gather or recapture footage; record the voice-over; prepare title and thumbnail candidates |
| -2 to -1 | Edit, caption, review on a phone and desktop, and run the publishing checklist |
| 0 | Publish the YouTube devlog and the strongest result-led short |
| +3 or +4 | Publish the failure-to-fix short |
| +7 to +9 | Publish the design takeaway or annotated comparison |
| +7 | Record early performance and answer substantive comments |
| +12 | Lock the next episode from the backlog |
| +28 | Complete the final review and update topic or packaging lessons |

Skipping a cycle is better than publishing a mechanic whose behavior or rights
cannot be described accurately.

## Capture contract

Preserve four types of footage while developing an approved mechanic:

| Capture | Purpose | Minimum useful version |
| --- | --- | --- |
| Problem | Makes the player-facing issue visible | Clean attempt with no explanation required to notice the issue |
| Diagnostic | Explains why the behavior occurs | F3/debug view, measured fixture or annotated still |
| Failure | Shows one informative rejected approach | Short clip with a clear lesson, not a bug compilation |
| Approved result | Delivers the payoff | Production character in the shared game implementation |

Prefer existing approved captures. Recapture when the source is too small, has
obsolete behavior, exposes private information, cannot be framed safely for
vertical video, or contains an asset that fails the rights check.

Several movement GIFs predate the UAL mannequin becoming the normal player model.
They remain valid development-history or behavior evidence, but label the older
appearance or recapture the final payoff with the current model. Do not let an
older character capture imply that it is the current visual direction.

Record a clean 16:9 master and, when framing permits, a separate 9:16 take. A
center crop is not automatically a short-form edit: important action, captions
and interface elements must remain inside platform-safe areas.

## Platform deliverables

### YouTube devlog

- English voice-over with optional on-screen terminology.
- 16:9 gameplay-led edit; use the shortest length that completes the story.
- The first moments must deliver the result promised by the title and thumbnail.
- Add accurate English captions, chapters when they improve navigation, source
  links, visible third-party credits, and one focused community question.

### Reels and Shorts

- Default to 9:16, 30–60 seconds, spoken narration and burned-in English captions.
- Show the result or surprising failure in the first two seconds.
- Make each cutdown understandable without watching the devlog.
- End with the episode's focused question or a narrower version of it.
- Export a clean master before adding platform-specific audio or stickers.

YouTube currently classifies square or vertical uploads up to three minutes as
Shorts, but that maximum is not the target for this workflow. Meta recommends
9:16 Reels with audio and key elements inside safe zones. Review the official
[YouTube Shorts guidance](https://support.google.com/youtube/answer/15424877?hl=en)
and [Meta Reels guidance](https://www.facebook.com/business/ads/facebook-instagram-reels-ads)
when platform behavior changes.

## Truth and review gates

- Use **implemented**, **implemented for review**, **visual prototype**,
  **concept approved**, and **planned** precisely.
- Do not call a visual prototype integrated gameplay. The Soulbound HUD is still
  separate from the Godot HUD.
- Do not describe concept-art progression thresholds as final gameplay rules.
- Do not present placeholder stations or roadmap mechanics as playable.
- A public response may suggest a backlog item or test. It does not approve a
  mechanic, alter an established design decision, or bypass the project's review
  gates.
- Correct material factual errors in a pinned comment or description and record
  the correction in the post-publication review.

## Community interaction

Ask one concrete question per post. Good questions expose a real tradeoff:

- “Should a dodge preserve momentum after leaving a ledge, or stop at its
  original travel distance?”
- “Does a failed cliff dive read as a fair consequence when the recovery is
  physical rather than a fixed animation?”

Avoid “What should I add next?” unless every offered option is already inside the
approved roadmap. Summarize recurring feedback as evidence; do not treat comment
counts as votes that silently decide the design.

Reply first to questions, useful playtest observations and thoughtful criticism.
Do not argue about taste, promise delivery dates, or reveal private contributor
information.

## Rights and safety

Every brief must link to [the project credits](../../CREDITS.md) and list the
third-party assets visible in its footage.

- Credit and introduce the creator as **Neth** only. Never publish a legal name,
  personal email, location, local account name, filesystem path, notification,
  private account, or identifying media/document metadata.
- Internal development notes are research sources, not automatically publishable
  material. Rewrite their information in the public voice and apply the privacy
  checklist before quoting or displaying them.
- **Never show the unresolved PSX Sword / Espada PS1 asset.** Its license is not
  supplied, and credit does not create permission.
- Use only original or appropriately licensed music, images, fonts, sound and
  footage. Platform music libraries must be checked separately for each platform
  and export.
- Retain required attribution for the PSX Dungeon pack and any other attributed
  material in the description. CC0 assets should still be credited when doing so
  helps viewers understand the development process.
- Confirm that editor paths, usernames, notifications, tokens, private files and
  identifying metadata are not visible in captures or exports.
- Recheck the relevant source license before accepting sponsorship, paid
  promotion or a commercial music license.

Instagram's own guidance recommends posting only material the creator made or
has permission to use; giving credit alone does not prevent infringement. See
[Instagram copyright guidance](https://www.facebook.com/help/354736791367645/).

## Measurement

Follower count is secondary during the opening slate. Review formats against
their own purpose rather than comparing a Short directly with a devlog.

| Goal | Primary signal | Diagnostic signals |
| --- | --- | --- |
| Keep the promise | First 30-second retention on devlogs | Early dips, title/thumbnail mismatch |
| Deliver useful stories | Average view duration and completion | Rewatches, chapter exits, top moments |
| Build a returning audience | Returning/casual/regular viewers when available | Repeat commenters, playlist continuation |
| Start useful discussion | Meaningful comments and replies | Questions that inform tests or future explanations |
| Make reusable short-form | Completion, replay, shares and saves | Profile visits and long-form referrals |
| Sustain the practice | Planned releases completed without disrupting development | Editing hours and skipped development work |

Use 7-day results for quick packaging observations and 28-day results for topic
and format decisions. Change one meaningful variable at a time when testing a
new hook, title style or video structure.

YouTube recommends matching the opening to the title and thumbnail promise and
using retention instead of assuming one ideal duration. See the official
[performance guidance](https://support.google.com/youtube/answer/16559650?hl=en)
and [retention guidance](https://support.google.com/youtube/answer/9314415?hl=en).
