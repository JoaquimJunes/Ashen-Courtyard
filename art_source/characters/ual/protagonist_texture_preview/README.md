# Protagonist texture preview

**Preview only — awaiting Neth's visual approval before game integration.**

## Open and edit

Open `Protagonist_texture_preview.blend` in Blender. The Texture Paint workspace
uses `Protagonist_BaseColor_512`, a packed **512 × 512 sRGB** texture, with nearest
sampling on the unchanged `CharacterPaint` UV map. `Protagonist_BaseColor_512.png`
is the matching external texture. Save both the image and the Blender file after
painting; keep the packed image synchronized when sharing the source file.

The full face, hair, scar, stubble, skin shading, toes and shorts are painted.
The nose, eyes, hair silhouette and mannequin joint forms have no new geometry.
Facial modeling remains Neth's later work and may require local texture touch-ups.

## Preserved baseline

The approved source is `../texture_paint/UAL_texture_paint.blend`, including its
previous cleanup. This work does not alter that file or the original game body.
The selected mannequin retains **6,993 vertices, 13,742 triangles and 65 bones**.
Fingerprints compare positions, topology, corner normals, smooth flags, every UV
layer, skin weights, vertex-group names, bone names/hierarchy/rest transforms and
object transforms. The saved copy remains in Rest Position and retains 43 actions.
The extra original Icosphere helper is hidden from renders, not modified.

Only the working copy's texture/material setup, paint-canvas selection and preview
cameras/lights changed. The A-pose and bent-joint inspection use existing bones
temporarily during rendering; they are not saved as new animation clips or rest poses.

## Artwork and projection

- Character reference: Neth's `MainKnightReference.png`.
- Mannequin provenance: existing Quaternius UAL mannequin, CC0, through the
  approved local painting copy.
- Painted source: built-in image generation, using the actual mannequin's
  front/back/head projection guides plus the supplied character reference.
- `painted_projections.png` is the generated painting source, not a model render.
- `bake_texture.py` projects that artwork into the existing UVs, registers the
  close-up projection offset, blends front/back coverage and adds texture bleed.
  It never edits the model. The final atlas is sampled from the resulting PNG.
- `textured_*.png` and `original_*.png` are actual Blender renders with matched
  cameras, pose and lighting. Only these renders appear in the comparison.

Generation direction: keep the four-quadrant template registration and silhouette;
paint warm medium tan skin, subtle muscular shading, short dark brown hair, dark
brows, brown eyes, a painted straight nose, neutral mouth, rugged stubble, healed
diagonal scar over the character's left eyebrow/temple, and charcoal boxer shorts.
Use restrained earthy colors and angular pixel clusters, matte diffuse surfaces,
soft even lighting, no added anatomy or accessories, no text and no watermark.

## Verification

`baseline.json` and `validation.json` record mesh/UV/rig checks and saved-file
verification. The packed image is compared with the delivered PNG after reopening
the Blender file. Front, back, side and face renders were visually reviewed, plus
an internal bent-elbow/knee pose in `inspection_bend.png`. The existing rigid joint
shapes remain visible, as required by the no-modeling constraint.

`preview_checks.json` records the inline comparison's eight view/material states
at desktop and narrow widths, in light and dark themes.

No runtime appearance resource, production scene, animation library or gameplay
file is changed. Asset import and game regression checks belong to the later
integration stage after the texture preview is approved.
