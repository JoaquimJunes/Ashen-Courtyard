# Painted 2D Soul-wisp animation v1

Separate animation reference for review, based on the approved
[keyframe sheet](assets/approved-keyframes.png). **No HUD preview or Godot
integration is included. Ask for explicit permission before any preview change.**
Approval of this movie does not authorize integration.

## Watch and use

- [Play the video](soul-wisps-painted.webm): 10 seconds, 1280×720, 60 fps, VP9,
  charcoal background, no audio. Open it in a WebM-compatible browser/player.
- [Transparent PNG sequence](frames/): `soul-0000.png` through `soul-0599.png`,
  RGBA at 1280×720. Import as an image sequence at **60 fps**, straight alpha.
  Frame zero is 0.000 seconds; frame 599 is 9.983 seconds and occupies the last
  1/60 second. There is no duplicated ending frame or automatic loop.
- [Painted and separated layers](assets/): generated stone, crystal and wisp
  atlas, plus separated stone, crystal, liquid, eyes and rune-emission layers.
- [Editable animation](source/animation.js) uses the painted artwork and
  deforms its texture in 2D. It does not crossfade the eight storyboard panels.

## Timing and quantities

| Time | State |
| --- | --- |
| 0.00–0.50 | Empty main; cooldown; first reserve holds 300 Soul. |
| 0.50–2.50 | Transfer 150 Soul/sec from the first reserve to the main vessel. |
| 2.50–2.95 | Empty-to-full burst: 0.45 s. |
| 2.95–3.70 | Gather toward stone: 0.75 s. |
| 3.70–4.60 | Settle into dimmer, compact wisps: 0.90 s. |
| 4.60–6.60 | Quiet full hold. |
| 6.60–8.10 | Spend 90 Soul once; 0.30 s displayed drain; 1.50 s aura linger. |
| 8.10–8.70 | Dissolve: 0.60 s. |
| 8.70–10.00 | Hold 210/300 main Soul with no exterior aura. |

Reserves are visually quiet and remain empty after supplying the refill. The
eyes are absent at low/empty fill; their separate 0.40-second completion glow
occurs only after refill completes. This directed movie depicts the dramatic
empty-to-full case; arbitrary casts and gameplay interruptions are not implemented.

## Artwork and editing

The built-in image-generation tool produced the painted assets. Exact prompts,
reference role and original generated-file provenance are saved in
[image-prompts.json](source/image-prompts.json). The supplied storyboard remains
the visual authority. No external video-generation service was used.

`animation.js` owns `poseAt` (timing and quantities), `layout` (fixed framing),
`extractLayers` (separating authored rune glow and reserve contents), and
`buildWisps` (painted sprite placement, curved motion and UV deformation).
`specs` inside `buildWisps` controls each wisp's size, position and variation.
The atlas's two isolated right-hand sprites are used; the overlapping left
sprites are retained as source art but excluded from the animation.

The frame and hearts are one fixed painted plate. Crystal and liquid are masked
separately, and a painted crystal-lighting pass lies above the liquid. The eyes
use a separate angular mask. Main-rim rune emission and the stationary geometric
circle are separate from the stone. Alpha-preserving compositing and sprite
deformation happen only in this isolated export; no existing preview renderer is
imported, edited or opened.

## Rebuild and verify

Requirements: Node.js with Playwright, Chromium with WebGL and VP9 WebCodecs,
plus Python/Pillow for validation. In this environment, from this directory:

```sh
NODE_PATH=<USER_HOME>/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules CHROMIUM_PATH=/usr/bin/chromium node source/export.cjs
python3 source/validate.py
node source/check-timing.cjs
NODE_PATH=<USER_HOME>/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules CHROMIUM_PATH=/usr/bin/chromium node source/check-video.cjs
```

`export.cjs --stills` renders just the eight review moments and gameplay-size
check. The full command regenerates this concept folder's derived layers,
frames and video, so copy the folder to a new version before changing the art.
`render.html` is an offline render entry point, not a replacement HUD preview.
Its temporary asset server binds only to localhost and closes after export.

The video is encoded from the same 600 frames, with deterministic timestamps,
one keyframe per second and seek cues. The small muxer follows the
[Matroska element specification](https://www.matroska.org/technical/elements.html)
and [SimpleBlock layout](https://www.matroska.org/technical/notes.html).

## Validation

[Integrity results](validation/integrity.json), [encoding results](validation/encoding.json)
and [playback results](validation/playback.json) record the delivered checks.
Every PNG has transparent exterior pixels, an opaque subject and at least 30px
of canvas padding. The three heart sample points remain identical throughout;
the settled wisps actually move. The video contains exactly 600 frames, one video
track and no audio. Its decoded burst, settled and depleted frames were inspected.
The original 28 protected HUD source/export files retain their pre-work hashes.

Keep this concept separate until the user reviews the animation and explicitly
permits preview changes. This work adds no public gameplay API or save-data change.
