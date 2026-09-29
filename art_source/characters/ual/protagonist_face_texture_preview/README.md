# Updated face — player texture preview

Open `UAL_face_textured_repaired.blend` in Blender. Its 512 × 512 texture is packed
into the file and uses nearest-neighbor filtering. Select Material Preview to
see it. `Protagonist_BaseColor_512.png` is also provided for further painting.

This is a separate review copy of the updated `../UAL_reference.blend`. The
original file remains unchanged. Nothing has been assigned to the game player;
integration still requires visual approval.

The face had inconsistent polygon winding and obsolete custom normals. The copy
corrects eight reversed faces, clears those normals, welds 1,552 coincident
vertices with matching skin weights, removes one stray neck triangle, and fills
16 missing facial skin weights. Two existing weight totals are normalized.
The remaining surface positions and the user's flat shading are preserved.

The previous player texture is reused byte-for-byte. A `CharacterPaint` UV layer
is transferred from the earlier painting copy, with seam correspondence and
facial placement adjusted for the new eyes, nose, and mouth. The original two
UV layers are retained. The face remains editable by painting or UV editing.
Where a joined polygon crossed an old texture seam, it was split along its
existing render triangles (140 polygons). This lets each side keep its own UVs
and prevents texture streaks without moving or adding surface points.

The saved file was reopened and checked: 65 bones, 43 animation actions, no open
or nonmanifold edges, no inconsistent winding, no zero-area geometry, no collapsed
UV triangles, and no unweighted vertices. The repaired facial vertices follow a
head rotation. `repair_report.json` and `validation.json` record these checks.

The front, side, back, and face PNGs are renders of this saved model. `clay_*`
shows the repaired mesh without the texture; `before_face.png` shows the input
mesh under matching neutral lighting. `textured_bend.png` is an internal static
deformation check. Rendering does not save the temporary pose into the blend.
