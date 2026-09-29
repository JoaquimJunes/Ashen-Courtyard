# Soul wisps — animated reference v1

Status: separate motion reference awaiting feedback. The user approved the
[eight key poses](../soul-wisps-keyframes-v1.png) and selected the **Heavier**
timing option. This folder does not change the interactive HUD or Godot.

## Selected timing

| Phase | Duration | Motion |
| --- | --- | --- |
| Burst | 0.45 s | Rise sharply after the previously empty main gauge reaches full. |
| Gather | 0.75 s | Hooked spectral tails curl toward the stone and lose height. |
| Settle | 0.90 s | Reduce glow into a compact, slowly moving aura. |
| Spend / linger | 1.50 s | Existing wisps persist while waiting for recovery. |
| Dissolve | 0.60 s | Cores disappear; trailing ribbons separate and fade. |

Burst → gather → settle totals **2.10 seconds**. Linger starts at accepted
spending, alongside the existing 0.30-second liquid drain, not after it.
The existing refill begins after drain + 0.50-second cooldown and transfers at
half the main vessel's capacity per second. The dramatic burst applies only to
the main gauge, and only after complete emptiness. Other completions use the
0.90-second soft settle. Full means actual and displayed Soul have both arrived.

The slow idle ribbon motion is a visual proposal, with independent overlapping
cycles of about 3.5–8 seconds. There is no extra four-second brightness pulse in
this reference: the settled glow is restrained, and the eyes have their separate
0.40-second refill cue. Reserve vessels have no burst or exterior aura.

## Three directed sequences

1. **Empty → full → spend:** hold empty briefly, wait 0.50 s, refill from one
   reserve over 2 s, burst/gather/settle, then spend 90 Soul. With reserves empty,
   the aura lingers and dissolves. The 0.65-second initial hold and the final
   display hold are presentation pauses, not new gameplay delays.
2. **Ordinary refill:** 210/300 main, 90 reserve; wait 0.50 s, refill over
   0.60 s, then settle softly. No dramatic burst.
3. **Recover during linger:** spend 90 from full; 0.30 s drain + 0.50 s wait +
   0.60 s refill reaches full 1.40 s after spending, before the 1.50 s linger
   expires. The aura softly settles without disappearing or bursting again.

The frame, crystal, heart silhouettes and lossless stone painting are reused
from the reviewed HUD. Extra runes are recessed marks on the stone, no glyphs
are drawn in the crystal, and the stationary magic circle is shown for the
Strongest form only. Wisps are animated curved ribbons with luminous comet
cores, asymmetrical hooks and torn transparent tails. The artwork is drawn
over the aura to keep the stone, eyes and hearts clear.

## Edit and rebuild

- [timeline.js](timeline.js): deterministic, directed sample poses and timing.
  This is a storyboard player, **not** a replacement resource controller.
- [drawing.js](drawing.js): isolated crystal/frame drawing and moving wisps;
  `wispSpecs` sets their placement, lengths, curling direction and ribbon width.
- [player.js](player.js): replay, pause, seeking, sequence selection, reduced
  motion, visibility pause and shared animation time for both displayed sizes.
- [reference.html](reference.html): compact reference layout.
- [build.py](build.py): embeds the drawing, timeline and existing lossless stone
  asset into one offline fragment, with a 1 MB size guard.
- [check.cjs](check.cjs): timing, conservation and browser interaction checks.

From this directory:

```sh
python3 build.py /absolute/output/soul-wisps-motion-reference.html
node check.cjs
```

For a local browser wrapper, use the HUD's existing renderer:

```sh
python3 ../../tools/vendor/visualize/scripts/render.py /absolute/output/soul-wisps-motion-reference.html /tmp/soul-wisps-motion-reference.html
NODE_PATH=<USER_HOME>/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules CHROMIUM_PATH=/usr/bin/chromium node check.cjs --browser
```

The last command uses the temporary wrapper path shown above. The fragment is
self-contained; the browser needs no network. Animation stops at the end, can
be replayed or scrubbed, and pauses offscreen/hidden without catching up.
Reduced motion keeps level timing but makes the wisps static, caps their glow,
and suppresses the bright completion cue. Both views share one sampled state.

## Review boundary

Review this motion before integration. In particular, late recovery during the
fade, repeated spending during a burst, death/reset and stage changes still need
the stateful integration implementation and regression tests. These directed
sequences do not claim to implement arbitrary gameplay interruptions. Keep the
existing HUD preview, offline export, and saved Desktop package intact until
that integration is requested after review.
