# Soul wisps — keyframe and behavior concept v1

Status: static visual storyboard approved by the user. The subsequent
[separate animated reference](soul-wisps-motion-v1/README.md) uses the user's
selected Heavier timing. No interactive-preview implementation has been added;
the existing HUD preview remains at its previously saved revision.

[Eight-keyframe sheet](soul-wisps-keyframes-v1.png) develops the aura from
[Fiery Soul v2](fiery-soul-v2.png) into aggressive, mystical soul wisps: bright
violet cores, hollow curls, translucent torn tails, and asymmetrical hooked
paths. It preserves the stone-rim runes, rune-free crystal and stronger magic
circle of the proposed strongest form.

## Confirmed behavior for the next design

- Only the main Soul gauge receives this effect. Reserves stay visually quiet.
- A dramatic rising burst happens only after the main gauge has been completely
  empty and subsequently reaches full. Ordinary refills settle softly.
- The burst glows strongly, gathers toward the stone, stabilizes, and reduces
  its glow into a restrained resting aura.
- Spending mana leaves a brief lingering aura. If the main gauge does not return
  to full, the remaining wisps dissolve rather than sustain an under-full aura.

These decisions supersede the preview's immediate aura dissolution on spending
for the future proposed effect. They are not implemented by this storyboard.

## Key poses

| Pose | Main Soul | Proposed visual |
| --- | --- | --- |
| 01 Empty | Empty | No wisps or eyes; dim stone markings and magic circle. |
| 02 Refill | Rising, below full | Liquid rises; no exterior burst yet. |
| 03 Full / Burst | Reaches full after emptiness | Brightest, tallest soul-wisp eruption. |
| 04 Gather | Full | Wisps hook back toward the rim and lose some height and light. |
| 05 Settled | Full | Compact, dimmer, restless wisps remain close to the stone. |
| 06 Spend / Linger | Below full | Existing wisps linger briefly; no fresh eruption. |
| 07 Dissolve | Still below full | Tails unravel into faint translucent fragments. |
| 08 Below full | Still below full | No exterior wisps; permanent ornaments remain. |

The frames are pose references, not a frame-by-frame resource accounting trace.
Small reserve quantities in the generated drawing are illustrative. They do not
propose rewards, additional capacity, or independent reserve effects.

## Behavior details to settle after visual review

Proposed handling: remember that the main vessel reached empty and consume that
condition once at its next full recovery, so the burst cannot repeat while full.
If refill reaches full during lingering or fading, gather into the resting aura;
use the dramatic burst only when the empty-to-full condition is armed. Trigger
completion when both actual Soul and the displayed liquid reach full, preserving
the existing resource-versus-presentation separation.

The selected durations are now documented in the
[animated reference](soul-wisps-motion-v1/README.md): 0.45 s burst, 0.75 s gather,
0.90 s settle, 1.50 s linger and 0.60 s fade. Idle motion and transient
rune/circle glow remain subject to feedback on that motion reference.
The existing refill-only eye-completion cue should remain separate. Hidden-state
pause, death/reset and reduced-motion handling must be specified before preview
integration; they must not change resource costs or refill timing.

Next: review the animated reference and resolve integration interruptions before
adding the effect to the HUD. The original generation prompt below is historical.

Generated with the built-in image generation tool using Fiery Soul v2 as the
reference. The prompt below records the visual proposal; confirmed behavior is
listed separately above.

## Generation prompt

Use case: precise-object-edit / animation keyframe reference. Create ONE high-resolution static STORYBOARD concept sheet, NOT an animation and NOT a game implementation. Use the attached HUD design faithfully: strongest-level mana frame with pointed gothic crown, carved stone rim with numerous readable incised violet runes, slightly bold angular magic circle behind it, rune-free dark faceted crystal with evil white eyes, attached unchanged broken 3-red-heart health frame and five small curved reserve vessels. Keep all solid HUD components IDENTICAL in design and scale across panels. The main vessel is the only subject of this effect study; keep the small reserves visually quiet. NO runes or symbols inside ANY crystal, no skulls, no additional faces, no gameplay background.
Requested style change: the purple aura must read as AGGRESSIVE MYSTICAL SOUL WISPS, not ordinary flames. Replace repetitive fire tongues with several asymmetric spectral presences: luminous violet teardrop/comet-like cores, long curling translucent smoke-silk tails, hooked and torn tips, sharp sweeping arcs, hollow negative spaces and subtle lavender inner highlights. Restless, possessed, threatening energy with a low-poly dark-fantasy treatment. Wisps launch upward/outward then curl and coil toward the stone, never across the readable crystal/eyes/hearts. Avoid orange/yellow fire, literal cartoon ghosts, rows of triangular flame tongues, thick fog, broad white bloom or lightning bolts. Purple outer aura stays behind the stone ornaments; inner Soul remains contained in the crystal. The magic circle stays stationary and recognizable.
Layout: clean 4-column by 2-row storyboard on a subdued charcoal background, generous spacing and aura padding, large enough to compare silhouettes. Title 'SOUL WISPS — KEYFRAME STUDY'. Exactly EIGHT numbered panels, read left to right, top row then bottom row. Captions should be short and accurate, no seconds or exact timing:
01 EMPTY — main vessel completely empty; dark faceted glass, NO eyes, no external Soul wisps, stone rune marks and circle dim.
02 REFILL — main Soul liquid near full but still clearly below the top; white eyes visible, no exterior burst yet; stone rim dim. This is refilling after having been empty.
03 FULL / BURST — the instant the previously empty main gauge reaches 100%; the tallest, brightest, aggressive rising soul-wisp eruption. Strong violet glow from carved rim runes and circle; preserve readable facets and stone. Dramatic but not opaque.
04 GATHER — still 100%; the launched wisps hook and spiral back toward the mana frame, tighter and shorter, reduced brightness compared with burst. Suggest coiling spectral tails, not a spinning crystal or moving magic circle.
05 SETTLED — still 100%; compact, low-intensity, slow-looking restless soul wisps close to the rim, restrained glow. Clearly calmer/dimmer than 03 and 04.
06 SPEND / LINGER — main liquid visibly drops to around 70%; eyes remain visible. The compact exterior wisps briefly linger while waiting for recovery; no new eruption. Carved runes/circle lose their full glow.
07 DISSOLVE — same below-full mana level; no full recovery occurred. Remaining soul wisps unravel into thin, torn, transparent purple strands and fade away. Clearly fewer and fainter than 06.
08 BELOW FULL — same main liquid level; no external wisps left. Dim engraved stone runes and faint magic circle remain, white eyes remain; all stone/health/reserve geometry unchanged.
A small single-line footer: 'Empty-to-full: burst. Other refills: soft settle.' This depicts a proposed visual sequence for review, not approved numerical timing. Preserve the original carved-stone style, faceted crystal, rune and reserve design; change only resource display states and the aura's proposed spectral shapes. No extra decorative UI, labels or numeric clocks.
