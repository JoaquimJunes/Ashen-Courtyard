# UAL pixel texture painting copy

Open `UAL_texture_paint.blend` in Steam Blender 5.2.2 LTS. It is prepared for the
**Texture Paint** workspace using **Paint Pixel Art** with anti-aliasing off.

- Paint directly on the mannequin or the image editor.
- The active canvas is `UAL_BaseColor_256`: a **256 × 256** sRGB PNG with nearest
  sampling. The gray colors are only a neutral primer.
- Use **Image → Save** to save `UAL_BaseColor.png`, and **Ctrl+S** for the Blender
  file. The initial texture is also packed into the blend for portability.
- `UAL_UV_layout.png` is a transparent wire overlay at the texture's real size;
  `UAL_UV_layout.svg` is a scalable alternative. Keep either on a separate layer
  if painting in an external editor. `UAL_UV_guide.png` identifies body areas.
- The painting UV map is `CharacterPaint`; original import UV channels remain
  available. The complete atlas is within 0–1 with no overlapping UV triangles.
- The rig is hidden from the viewport and remains in Rest Position. Its 65 bones,
  rest transforms, skin weights and 43 imported animations are retained.

Safe topology cleanup removed exact duplicate vertices with identical skin
weights and a single stray neck triangle left by the original GLB import.
Vertex count: **8,546 → 6,993**. Triangles: **13,743 → 13,742**. Remaining surfaces
have no open or nonmanifold edges. Original corner normals are preserved within
Blender's normal-storage precision. The original `../UAL_reference.blend` is
unchanged; this is a separate painting exercise, not a replacement game model.

Style reference: `../../../references/retro_style_reference.png`, supplied by
Neth on 2026-09-26. Direction: visible texture pixels, faceted forms, restrained
colors and strong light/shadow contrast. This reference is for internal art
study; its creator and redistribution license have not been established.
