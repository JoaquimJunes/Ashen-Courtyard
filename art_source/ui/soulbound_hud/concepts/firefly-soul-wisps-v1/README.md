# Firefly Soul-wisp reference pack v1

Standalone images and prompts for the user to generate transitions in Adobe Firefly.
This pack does not modify the interactive HUD preview or the game.
Preview integration requires a separate explicit permission request.

## Start here

Open [START-HERE.html](START-HERE.html) in a browser. It shows both upload images
and the complete copy-ready prompt for every transition. It is an offline,
static instruction sheet: no animation, network requests, scripts or preview dependencies.

All five upload PNGs are **1280×720, opaque RGB black**, not transparent:
[Empty](images/01-empty.png), [Burst](images/02-burst.png),
[Gather](images/03-gather.png), [Settled A](images/04-settled-a.png),
[Settled B](images/05-settled-b.png).

| Transition | First | Last | Final duration |
|---|---|---|---|
| Burst | [01-empty.png](images/01-empty.png) | [02-burst.png](images/02-burst.png) | 0.45 s |
| Gather | [02-burst.png](images/02-burst.png) | [03-gather.png](images/03-gather.png) | 0.75 s |
| Settle | [03-gather.png](images/03-gather.png) | [04-settled-a.png](images/04-settled-a.png) | 0.90 s |
| Full idle | [04-settled-a.png](images/04-settled-a.png) | [05-settled-b.png](images/05-settled-b.png) | 2.00 s |
| Spend / linger | [05-settled-b.png](images/05-settled-b.png) | [04-settled-a.png](images/04-settled-a.png) | 1.50 s |
| Dissolve | [04-settled-a.png](images/04-settled-a.png) | [01-empty.png](images/01-empty.png) | 0.60 s |

Choose Firefly Video, 16:9, and upload the indicated First and Last images.
Paste that transition's full text from the `prompts/` folder. The common prompt
is already included in each file. Keep automatic prompt enhancement off for
the first trial, to preserve the supplied motion directions.

Firefly's documented default is 5 seconds at 24 fps. Generate each motion as
a separate clip, then trim/retime it to the agreed duration; a timing phrase
in a prompt does not guarantee frame-accurate timing. A later 60 fps delivery
is an export/interpolation step, not the native detail of these generations.
An identical endpoint helps joins but does not guarantee matching velocity;
inspect joins before final editing.

Use [Adobe's keyframe instructions](https://helpx.adobe.com/firefly/web/work-with-audio-and-video/work-with-video/generate-videos-using-images.html)
and [video settings](https://helpx.adobe.com/firefly/web/firefly-video-editor/generate-videos/generate-video-using-firefly-models.html).
With image keyframes, transparent-background generation is disabled. With both
keyframes, camera-motion controls are also disabled; the prompt locks the camera.

## Sequence and resource behavior

Keep exterior aura absent from 0.00–2.50 s while the main vessel fills.
Burst 2.50–2.95; gather 2.95–3.70; settle 3.70–4.60; idle 4.60–6.60;
spend/linger 6.60–8.10; dissolve 8.10–8.70; no aura 8.70–10.00.
Liquid and eyes are excluded from Firefly inputs and stay separate.
The dramatic burst is reserved for empty-to-full completion; other refills
settle softly. The cast at 6.60 s spends 90/300 Soul; liquid drains to 70%
over 0.30 s while exterior aura lingers. Reserves stay quiet.

## Artwork and alignment

The painted poses were made with the built-in ImageGen tool, using
[the approved keyframe study](source/approved-keyframes.png), not stills from
the rejected animation. Original generated PNGs and their exact prompts are
preserved under `source/`; see [generation prompts](source/image-generation-prompts.json).

[Alignment sheet](alignment-sheet.png): one fixed crop of panel 08, uniformly
resized and reused in every panel. It stays below full because this sheet
checks placement only, not resource state. Its geometry and artwork are not
regenerated. Screen blending displays the aura around it.

All four poses receive the same canvas transform (1672×941 → 1152×648 centered
inside 1280×720). No per-pose auto-cropping or recentering is used.
The [HUD holdout](source/hud-holdout.svg) is an editable occlusion mask,
not replacement HUD artwork. Apply it during compositing to clear the shared
vessel/stone/hearts/reserves from the VFX layer; the upload images keep intact
painted tails so Firefly sees natural smoke rather than a chopped silhouette. The vessel anchor is approximately (450,435).
The corresponding grayscale [mask](source/hud-holdout.png) is white where
the unchanged HUD must be protected. Do not upload the holdout mask to Firefly.
Settled B is energy-matched to A to avoid an unintended idle brightness pulse.

Use Screen blending on generated black-backed clips for a luminous overlay.
This does not create a genuine alpha channel. Composite behind the unchanged
HUD, and reapply the holdout if generated in-between frames spill across it.
If needed, a later transparent game asset needs a separate alpha workflow.

## Modify and rebuild

Edit artwork via the built-in image-generation tool using the saved prompts.
Keep the same canvas, anchor, empty center and protected heart region.
For export placement or holdout edits, modify
[prepare-pack.cjs](source/prepare-pack.cjs) or [hud-holdout.svg](source/hud-holdout.svg).

Requires Node.js and ImageMagick 7. From this folder run:

```sh
node source/prepare-pack.cjs
python source/validate.py
```

Validation requires Pillow and NumPy. Its report is saved in
[review/validation.json](review/validation.json). It checks all five image sizes,
black margins, protected HUD pixels, matching idle brightness, transition links,
and the hashes of pre-existing HUD files. Image art is still subject to user review.

The machine-readable pair/timing map is [manifest.json](manifest.json).
Preserve this v1 pack when making later revisions; create a new version.

