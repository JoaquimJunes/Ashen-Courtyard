# Starting relic artwork

This asset was produced with the built-in image-generation tool, using the user's cropped HUD as an edit reference. The extraction is a close visual reconstruction, not a pixel-identical cutout. No game files were changed.

## Files

- `starting-frame-v1.png`: original generated transparent frame, 1633×963.
- `starting-frame-v1.webp`: earlier compressed frame with alpha, retained for reference.
- `starting-frame-v1-lossless.webp`: lossless encoding of the original PNG, now embedded in the interactive preview. Pixel comparison against the PNG reports zero changed pixels.
- `../soulbound-crystal-hud-preview.html`: current interactive preview. Its Strongest full preset has three full hearts, 300/300 mana, and five reserves, three full and two empty. Strongest partial starts at 150/300. The six-stage progression adds separate dynamic ornaments without changing this artwork. Its separate Gameplay start preset keeps zero reserves.
- `courtyard-preview.jpg`: background extracted byte-for-byte from the preview; it is an art-review backdrop, not a new gameplay asset.

The crystal, liquid, eyes, hearts, and reserve fills are separate dynamic layers. The frame artwork can be replaced independently. The main orb uses a front-hemisphere mesh projected into the canvas, with flat lighting; the heart and reserve frames are 2D.

The preview canvas now matches its displayed size and device pixel density (up to 3×), while retaining a logical 1280×720 layout. This removes the fixed-resolution upscaling that softened the stone on high-density displays. Texture downsampling uses high-quality filtering, and glow radii scale with rendering resolution. Resizing changes only presentation, not Soul timing. The original painted stone silhouette and texture have not been repainted or sharpened with artificial edge halos.

The partial reference preset's initial resource picture animates automatically: after 0.5 seconds, reserves refill the main vessel over time. Subsequent accepted casts drain visually for 0.3 seconds before another 0.5-second cooldown. See [Soul behavior](../docs/SOUL_BEHAVIOR.md) for the implemented cycle and current tests. Earlier instant reserve-assisted cast behavior is superseded; only Soul already in the main vessel can pay for a spell.

## Generation prompt

Use case: precise-object-edit / game HUD sprite extraction. Edit the attached HUD artwork into ONE reusable transparent frame asset. This is a surgical extraction, not a redesign. Preserve the EXACT original silhouette, crown shape, carved gothic bridge between the left and top rune plates, circular mana frame, worn bevels, chips, cracks, gray-violet stone coloration, large glowing runes, upper-right stone transition into the horizontal three-heart frame, irregular broken right tip, and its subtle dark soul wisps. Preserve their relative positions and proportions. REMOVE the checkerboard background entirely and output actual alpha transparency, not a drawn checkerboard. Make the INTERIOR of the large circular mana orb completely transparent: remove its purple sphere, liquid, facets and eyes, keep the stone rim unchanged. Remove the THREE red heart gems only and leave the existing near-black bed behind the hearts unchanged. REMOVE ALL FIVE small reserve circles below the main ring completely, leaving transparent background in their places; preserve the main ring and frame above them. Do not add spires, spikes, new symbols, extra texture, text, or ornaments. Do not make it metallic. Do not change the dark low-poly painted style. Keep the complete frame uncut, with a little transparent margin. Single isolated frame, wide landscape composition matching the input aspect ratio. Match the attached drawing as literally and faithfully as possible.

## Validation

Verified loading of the transparent asset; reference and gameplay presets; health and gold overlays; flask exhaustion; partial reserve spending; all-or-nothing failed casts; left-to-right mana overflow; outer-first stamina spending; changing crystal lighting; disappearance of eyes at empty mana; flat reserves staying unchanged under lighting; and layout at 320, 360, 736, and 1024 pixels. The input artwork's checkerboard was removed by image generation. The preview uses actual alpha transparency.
